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
    var errorMessage: String?
    var volume: Double = 0.7 {
        didSet {
            let normalized = volume.isFinite ? min(max(volume, 0), 1) : 0.7
            if volume != normalized { volume = normalized }
            player.volume = Float(normalized)
        }
    }
    var mode: PlaybackMode {
        get { queue.mode }
        set { queue.mode = newValue; systemMedia?.update(self) }
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

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var durationObservation: NSKeyValueObservation?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var loadGeneration = UUID()
    @ObservationIgnored private var pendingSeek: UUID?
    @ObservationIgnored private var fileAccess: AudioFileAccess?
    @ObservationIgnored private var systemMedia: SystemMediaController?
    @ObservationIgnored private var isShutdown = false

    init(connectSystemMedia: Bool = true) {
        player.volume = Float(volume)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            // 读取执行时的当前 item，避免旧条目的已排队时间事件污染新条目。
            MainActor.assumeIsolated {
                guard let self, !self.isShutdown, self.pendingSeek == nil,
                      self.status != .ended, self.status != .failed else { return }
                let seconds = self.player.currentTime().seconds
                if seconds.isFinite { self.elapsed = min(max(0, seconds), self.duration) }
                self.systemMedia?.update(self)
            }
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.synchronizeStatus() }
        }
        if connectSystemMedia { self.connectSystemMedia() }
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
        if status == .ended { seek(to: 0) }
        wantsToPlay = true
        if player.currentItem?.status == .readyToPlay { player.play() }
        synchronizeStatus()
    }

    func pause() {
        guard !isShutdown else { return }
        wantsToPlay = false
        player.pause()
        synchronizeStatus()
    }

    func next() {
        guard !isShutdown else { return }
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
        player.pause()
        clearCurrentItem()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        rateObservation?.invalidate()
        rateObservation = nil
        systemMedia?.shutdown()
        systemMedia = nil
        queue = PlaybackQueue()
        elapsed = 0
        duration = 0
        status = .idle
        errorMessage = nil
    }

    isolated deinit { shutdown() }

    private func clearCurrentItem() {
        pendingSeek = nil
        statusObservation?.invalidate()
        statusObservation = nil
        durationObservation?.invalidate()
        durationObservation = nil
        for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
        itemObservers.removeAll()
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        // 必须先解除 AVPlayer 对旧文件的使用，再释放它的 security scope。
        fileAccess = nil
    }

    private func loadCurrent() {
        guard let track = currentTrack else { return }
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
        player.replaceCurrentItem(with: item)
        systemMedia?.update(self)
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
        systemMedia?.update(self)
    }

    private func fail(_ message: String) {
        wantsToPlay = false
        pendingSeek = nil
        player.pause()
        status = .failed
        errorMessage = message
        systemMedia?.update(self)
    }
}
