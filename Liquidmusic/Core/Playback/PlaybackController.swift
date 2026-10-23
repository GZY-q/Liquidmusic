import AVFoundation
import Observation

enum PlaybackStatus: Equatable, Sendable {
    case idle, loading, waiting, playing, paused, ended, failed
}

// UI 只依赖控制器；后续在这里衔接 AVAudioEngine 的音频处理链。
@MainActor @Observable
final class PlaybackController {
    private(set) var queue = PlaybackQueue()
    private(set) var status: PlaybackStatus = .idle
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var wantsToPlay = false
    @ObservationIgnored var onPlaybackStarted: (@MainActor (Track) -> Void)?
    @ObservationIgnored private var recordedGeneration: UUID?
    var errorMessage: String?
    var volume: Double = 0.7 {
        didSet {
            let normalized = volume.isFinite ? min(max(volume, 0), 1) : 0.7
            if volume != normalized { volume = normalized }
            updateVolumes()
        }
    }
    var mode: PlaybackMode {
        get { queue.mode }
        set {
            if queue.mode != newValue { discardPreparedTrack() }
            queue.mode = newValue
            systemMedia?.update(self)
        }
    }
    var currentTrack: Track? { queue.current }
    var isPlaying: Bool { status == .playing }
    var canToggle: Bool { currentTrack != nil && status != .failed && status != .idle }
    var canSeek: Bool { canToggle && status != .loading && duration > 0 }
    var canSkipNext: Bool { !isShutdown && queue.canAdvance }
    var canSkipPrevious: Bool { !isShutdown && (canSeek || queue.canGoBack) }
    var statusText: String {
        switch status {
        case .idle: "选择一首歌曲开始聆听"
        case .loading: "正在载入…"
        case .waiting: "正在缓冲…"
        case .playing: "正在播放"
        case .paused: "已暂停"
        case .ended: "播放结束"
        case .failed: "播放失败，请重新选择文件"
        }
    }

    private(set) var isCrossfading = false
    private(set) var crossfadeEnabled = false
    private(set) var crossfadeDuration: Double = 6
    @ObservationIgnored private var player: AVPlayer
    @ObservationIgnored private let makePlayer: @MainActor () -> AVPlayer
    @ObservationIgnored private var prepared: PreparedTrack?
    @ObservationIgnored private var outgoingPlayer: AVPlayer?
    @ObservationIgnored private var outgoingAccess: AudioFileAccess?
    @ObservationIgnored private var envelope: CrossfadeEnvelope?
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    @ObservationIgnored private var failedPreparationID: UUID?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var lastProgressPublicationTime: TimeInterval = 0
    @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var durationObservation: NSKeyValueObservation?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var loadGeneration = UUID()
    @ObservationIgnored private var pendingSeek: UUID?
    @ObservationIgnored private var fileAccess: AudioFileAccess?
    @ObservationIgnored private var systemMedia: SystemMediaController?
    @ObservationIgnored private var isShutdown = false

    init(connectSystemMedia: Bool = true, makePlayer: @escaping @MainActor () -> AVPlayer = { AVPlayer() }) {
        self.makePlayer = makePlayer
        self.player = makePlayer()
        player.volume = Float(volume)
        observePlayer()
        if connectSystemMedia { self.connectSystemMedia() }
    }

    private func observePlayer() {
        let observedPlayer = player
        // 普通播放只需每秒四次进度更新；交叉渐变开启时才保留曲尾检测精度。
        let interval = crossfadeEnabled ? 0.05 : 0.25
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: interval, preferredTimescale: 600), queue: .main) { [weak self, weak observedPlayer] _ in
            // 读取执行时的当前 item，避免旧条目的已排队时间事件污染新条目。
            MainActor.assumeIsolated {
                guard let self, self.player === observedPlayer, !self.isShutdown, self.pendingSeek == nil,
                      self.status != .ended, self.status != .failed else { return }
                let seconds = self.player.currentTime().seconds
                let now = ProcessInfo.processInfo.systemUptime
                // 渐变的曲尾检测与界面进度解耦，开启渐变也不让 UI 每秒刷新二十次。
                if seconds.isFinite, now - self.lastProgressPublicationTime >= 0.24 {
                    let position = min(max(0, seconds), self.duration)
                    if self.elapsed != position { self.elapsed = position }
                    self.lastProgressPublicationTime = now
                    self.systemMedia?.update(self)
                }
                self.prepareOrBeginCrossfade()
            }
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self, weak observedPlayer] _, _ in
            Task { @MainActor [weak self, weak observedPlayer] in
                guard let self, self.player === observedPlayer else { return }
                self.synchronizeStatus()
            }
        }
    }

    private func stopObservingPlayer() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        rateObservation?.invalidate()
        rateObservation = nil
    }

    func configureCrossfade(enabled: Bool, duration: Double) {
        let normalized = duration.isFinite ? min(12, max(1, duration)) : 6
        guard enabled != crossfadeEnabled || normalized != crossfadeDuration else { return }
        let cadenceChanged = enabled != crossfadeEnabled
        crossfadeEnabled = enabled
        crossfadeDuration = normalized
        discardPreparedTrack()
        if !enabled { finishCrossfade() }
        if cadenceChanged, !isShutdown {
            stopObservingPlayer()
            observePlayer()
        }
    }

    func connectSystemMedia(transport: (any SystemMediaTransport)? = nil) {
        guard !isShutdown, systemMedia == nil else { return }
        systemMedia = SystemMediaController(playback: self, transport: transport ?? AppleSystemMediaTransport())
        systemMedia?.update(self)
    }

    func play(_ track: Track, in tracks: [Track]) {
        guard !isShutdown else { return }
        let playlist = tracks.contains(where: { $0.id == track.id }) ? tracks : [track]
        queue.replace(with: playlist, startingAt: track)
        loadCurrent()
    }

    func playNext(_ track: Track) {
        guard !isShutdown else { return }
        discardPreparedTrack()
        let wasEmpty = currentTrack == nil
        queue.insertNext(track)
        if wasEmpty { loadCurrent() }
        systemMedia?.update(self)
    }

    func jump(to entry: QueueEntry) {
        guard !isShutdown, queue.jump(to: entry.id) else { return }
        loadCurrent()
    }

    func toggle() { wantsToPlay ? pause() : resume() }

    func resume() {
        guard canToggle else { return }
        if status == .ended {
            recordedGeneration = nil
            seek(to: 0)
        }
        wantsToPlay = true
        if player.currentItem?.status == .readyToPlay { player.play() }
        outgoingPlayer?.play()
        if isCrossfading { startFadeTask() }
        synchronizeStatus()
    }

    func pause() {
        guard !isShutdown else { return }
        wantsToPlay = false
        player.pause()
        outgoingPlayer?.pause()
        fadeTask?.cancel()
        fadeTask = nil
        synchronizeStatus()
    }

    func next() {
        guard !isShutdown else { return }
        finishCrossfade()
        discardPreparedTrack()
        if queue.advance() { loadCurrent() } else { pause() }
    }

    func previous() {
        guard !isShutdown else { return }
        if elapsed > 3 { seek(to: 0) }
        else if queue.previous() { loadCurrent() }
        else { seek(to: 0) }
    }

    func seek(to seconds: Double) {
        guard canSeek, seconds.isFinite else { return }
        finishCrossfade()
        discardPreparedTrack()
        let position = min(max(0, seconds), duration)
        let seekID = UUID()
        let generation = loadGeneration
        pendingSeek = seekID
        elapsed = position
        if status == .ended { status = .paused }
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == generation, self.pendingSeek == seekID else { return }
                self.pendingSeek = nil
                if finished { self.elapsed = position }
                self.synchronizeStatus()
            }
        }
        systemMedia?.update(self, forceProgress: true)
    }

    // 由应用终止通知调用；也供测试显式清理，防止观察者和文件授权悬挂。
    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        loadGeneration = UUID()
        wantsToPlay = false
        finishCrossfade()
        discardPreparedTrack()
        player.pause()
        clearCurrentItem()
        stopObservingPlayer()
        systemMedia?.shutdown()
        systemMedia = nil
        queue = PlaybackQueue()
        elapsed = 0
        duration = 0
        status = .idle
        errorMessage = nil
    }

    isolated deinit { shutdown() }

    // 只构造展示状态，不加载虚拟音频、不自动播放或连接系统媒体。
    static func preview(track: Track) -> PlaybackController {
        let playback = PlaybackController(connectSystemMedia: false)
        playback.queue.replace(with: [track], startingAt: track)
        playback.duration = track.duration
        playback.elapsed = track.duration * 0.35
        playback.status = .paused
        return playback
    }

    private func clearCurrentItem(preservingAudio: Bool = false) {
        pendingSeek = nil
        statusObservation?.invalidate()
        statusObservation = nil
        durationObservation?.invalidate()
        durationObservation = nil
        for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
        itemObservers.removeAll()
        player.currentItem?.cancelPendingSeeks()
        if !preservingAudio { player.replaceCurrentItem(with: nil) }
        // 必须先解除 AVPlayer 对旧文件的使用，再释放它的 security scope。
        fileAccess = nil
    }

    private func loadCurrent() {
        guard let track = currentTrack else { return }
        finishCrossfade()
        discardPreparedTrack()
        let generation = UUID()
        loadGeneration = generation
        player.pause()
        clearCurrentItem()
        elapsed = 0
        duration = track.duration.isFinite ? max(0, track.duration) : 0
        errorMessage = nil
        status = .loading
        wantsToPlay = true
        fileAccess = AudioFileAccess(track.url)
        guard FileManager.default.isReadableFile(atPath: track.path) else {
            fail("无法访问「\(track.title)」。文件可能已移动，请重新选择音频文件。")
            return
        }
        let item = AVPlayerItem(url: track.url)
        observeItem(item, generation: generation)
        player.replaceCurrentItem(with: item)
        systemMedia?.update(self)
    }

    private func observeItem(_ item: AVPlayerItem, generation: UUID) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == generation, !self.isShutdown else { return }
                self.itemStatusChanged()
            }
        }
        durationObservation = item.observe(\.duration, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == generation, !self.isShutdown else { return }
                self.refreshDuration()
            }
        }
        observe(.AVPlayerItemDidPlayToEndTime, item: item, generation: generation) { playback in
            guard playback.status != .failed, playback.status != .ended else { return }
            if playback.queue.advance(automatically: true) { playback.loadCurrent() }
            else {
                playback.wantsToPlay = false
                playback.player.pause()
                playback.pendingSeek = nil
                playback.elapsed = playback.duration
                playback.status = .ended
                playback.systemMedia?.update(playback)
            }
        }
        observe(.AVPlayerItemFailedToPlayToEndTime, item: item, generation: generation) { playback in
            playback.fail(playback.player.currentItem?.error?.localizedDescription ?? "歌曲播放中断，请重新选择或跳过这首歌曲。")
        }
    }

    private func observe(_ name: Notification.Name, item: AVPlayerItem, generation: UUID,
                         action: @escaping @MainActor @Sendable (PlaybackController) -> Void) {
        let observer = NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == generation, !self.isShutdown else { return }
                action(self)
            }
        }
        itemObservers.append(observer)
    }

    private func itemStatusChanged() {
        guard let item = player.currentItem, status != .failed else { return }
        switch item.status {
        case .failed:
            fail(item.error?.localizedDescription ?? "无法解码这首歌曲。")
        case .readyToPlay:
            refreshDuration()
            if wantsToPlay { player.play() }
            synchronizeStatus()
        case .unknown: break
        @unknown default: break
        }
    }

    private func refreshDuration() {
        if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
            duration = seconds
        }
    }

    private func synchronizeStatus() {
        guard !isShutdown, status != .failed, status != .ended, let item = player.currentItem else { return }
        if item.status == .failed { itemStatusChanged(); return }
        if item.status != .readyToPlay { status = .loading }
        else if !wantsToPlay { status = .paused }
        else { status = player.timeControlStatus == .playing ? .playing : .waiting }
        if status == .playing, recordedGeneration != loadGeneration, let track = currentTrack {
            recordedGeneration = loadGeneration
            onPlaybackStarted?(track)
        }
        systemMedia?.update(self)
    }

    private func fail(_ message: String) {
        finishCrossfade()
        discardPreparedTrack()
        wantsToPlay = false
        pendingSeek = nil
        player.pause()
        status = .failed
        errorMessage = message
        systemMedia?.update(self)
    }

    // 准备阶段只推进队列副本；下一首可播放且进入重叠区间后才提交真实队列。
    private func prepareOrBeginCrossfade() {
        guard crossfadeEnabled, !isCrossfading, wantsToPlay, status == .playing,
              pendingSeek == nil, duration > 0, mode != .repeatOne else { return }
        // 使用实时音频位置，不依赖已经限频的 UI 进度。
        let remaining = duration - player.currentTime().seconds
        guard remaining > 0.1, remaining <= crossfadeDuration + 2 else { return }
        if prepared == nil {
            var candidate = queue
            guard candidate.advance(automatically: true),
                  let entry = candidate.currentEntry, entry.id != queue.currentEntryID,
                  entry.id != failedPreparationID else { return }
            let access = AudioFileAccess(entry.track.url)
            guard FileManager.default.isReadableFile(atPath: entry.track.path) else {
                failedPreparationID = entry.id
                return
            }
            let nextPlayer = makePlayer()
            nextPlayer.volume = 0
            nextPlayer.replaceCurrentItem(with: AVPlayerItem(url: entry.track.url))
            prepared = PreparedTrack(queue: candidate, player: nextPlayer, access: access)
        }
        guard let prepared, let item = prepared.player.currentItem else { return }
        if item.status == .failed {
            let id = prepared.queue.currentEntryID
            discardPreparedTrack()
            failedPreparationID = id
            return
        }
        guard item.status == .readyToPlay else { return }
        let overlap = CrossfadeEnvelope.duration(requested: crossfadeDuration, outgoing: duration,
                                                incoming: item.duration.seconds)
        guard overlap > 0.1, remaining <= overlap else { return }
        beginCrossfade(prepared, duration: min(overlap, remaining))
    }

    private func beginCrossfade(_ prepared: PreparedTrack, duration overlap: Double) {
        guard let item = prepared.player.currentItem else { return }
        self.prepared = nil
        outgoingPlayer = player
        outgoingAccess = fileAccess
        stopObservingPlayer()
        clearCurrentItem(preservingAudio: true)
        loadGeneration = UUID()
        queue = prepared.queue
        player = prepared.player
        fileAccess = prepared.access
        elapsed = 0
        duration = item.duration.seconds
        errorMessage = nil
        envelope = CrossfadeEnvelope(duration: overlap)
        isCrossfading = true
        status = .waiting
        observePlayer()
        observeItem(item, generation: loadGeneration)
        updateVolumes()
        player.play()
        systemMedia?.update(self, forceProgress: true)
        startFadeTask()
    }

    private func startFadeTask() {
        guard let envelope else { return }
        fadeTask?.cancel()
        let overlap = envelope.duration
        fadeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled, let self, self.isCrossfading else { return }
                // 使用音频时间而非墙钟，暂停期间不会悄悄完成渐变。
                self.updateVolumes()
                if self.player.currentTime().seconds >= overlap {
                    self.finishCrossfade()
                    return
                }
            }
        }
    }

    private func updateVolumes() {
        let gains = envelope?.gains(at: player.currentTime().seconds) ?? (incoming: 1.0, outgoing: 0.0)
        player.volume = Float(volume * gains.incoming)
        outgoingPlayer?.volume = Float(volume * gains.outgoing)
    }

    private func finishCrossfade() {
        fadeTask?.cancel()
        fadeTask = nil
        outgoingPlayer?.pause()
        outgoingPlayer?.replaceCurrentItem(with: nil)
        outgoingPlayer = nil
        outgoingAccess = nil
        envelope = nil
        isCrossfading = false
        player.volume = Float(volume)
    }

    private func discardPreparedTrack() {
        prepared?.player.pause()
        prepared?.player.replaceCurrentItem(with: nil)
        prepared = nil
        failedPreparationID = nil
    }
}

@MainActor
private struct PreparedTrack {
    let queue: PlaybackQueue
    let player: AVPlayer
    let access: AudioFileAccess
}
