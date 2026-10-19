import AppKit
import MediaPlayer

@MainActor
final class SystemMediaController {
    private weak var playback: PlaybackController?
    private let transport: any SystemMediaTransport
    private let clock: @MainActor () -> TimeInterval
    private let loadArtwork: @Sendable (String) async -> Data?
    private var artworkPath: String?
    private var artwork: NSImage?
    private var artworkTask: Task<Void, Never>?
    private var lastSnapshot: NowPlayingSnapshot?
    private var lastPublicationTime: TimeInterval = 0
    private var availability: MediaCommandAvailability?
    private var isShutdown = false

    init(playback: PlaybackController, transport: any SystemMediaTransport = AppleSystemMediaTransport(),
         clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         loadArtwork: @escaping @Sendable (String) async -> Data? = SystemMediaController.cachedArtwork) {
        self.playback = playback
        self.transport = transport
        self.clock = clock
        self.loadArtwork = loadArtwork
        transport.register { [weak self] request in
            // MediaPlayer 不承诺回调的线程；检查与执行同步到主线程后再返回真实状态。
            if Thread.isMainThread {
                return MainActor.assumeIsolated { self?.handle(request) ?? .commandFailed }
            }
            return DispatchQueue.main.sync { self?.handle(request) ?? .commandFailed }
        }
        update(playback)
    }

    nonisolated private static func cachedArtwork(_ path: String) async -> Data? {
        await ArtworkCache.loader.data(at: path)
    }

    func handle(_ request: MediaCommand) -> MPRemoteCommandHandlerStatus {
        guard !isShutdown, let playback else { return .commandFailed }
        guard playback.currentTrack != nil else { return .noSuchContent }
        switch request {
        case .play:
            guard playback.canToggle else { return .commandFailed }
            playback.resume()
        case .pause:
            guard playback.canToggle else { return .commandFailed }
            playback.pause()
        case .toggle:
            guard playback.canToggle else { return .commandFailed }
            playback.toggle()
        case .next:
            guard playback.canSkipNext else { return .noSuchContent }
            playback.next()
        case .previous:
            guard playback.canSkipPrevious else { return .noSuchContent }
            playback.previous()
        case .seek(let position):
            guard playback.canSeek, position.isFinite, position >= 0, position <= playback.duration else { return .commandFailed }
            playback.seek(to: position)
        }
        update(playback, forceProgress: true)
        return .success
    }

    // 只移除本实例注册的目标；shutdown 可重复调用。
    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        artworkTask?.cancel(); artworkTask = nil; artwork = nil; artworkPath = nil
        transport.setEnabled(MediaCommandAvailability())
        transport.unregister()
        transport.publish(NowPlayingSnapshot(), artwork: nil)
        lastSnapshot = nil
    }

    isolated deinit { shutdown() }

    func update(_ playback: PlaybackController, forceProgress: Bool = false) {
        guard !isShutdown else { return }
        let enabled = MediaCommandAvailability(play: playback.canToggle && !playback.wantsToPlay,
                                               pause: playback.canToggle && playback.wantsToPlay, toggle: playback.canToggle,
                                               next: playback.canSkipNext, previous: playback.canSkipPrevious, seek: playback.canSeek)
        if availability != enabled { availability = enabled; transport.setEnabled(enabled) }
        let snapshot = NowPlayingSnapshot(playback: playback)
        if snapshot.metadata?.artworkPath != artworkPath {
            artworkTask?.cancel()
            artworkPath = snapshot.metadata?.artworkPath
            artwork = nil
            if let path = artworkPath {
                artworkTask = Task { [weak self, loadArtwork] in
                    let data = await loadArtwork(path)
                    guard !Task.isCancelled, let self, !self.isShutdown, self.artworkPath == path else { return }
                    self.artwork = data.flatMap(NSImage.init(data:))
                    if let playback = self.playback { self.update(playback, forceProgress: true) }
                    self.artworkTask = nil
                }
            }
        }
        let time = clock()
        let last = lastSnapshot
        let changed = last == nil || last?.metadata != snapshot.metadata || last?.rate != snapshot.rate || last?.phase != snapshot.phase
        let pausedPositionChanged = snapshot.rate == 0 && abs(snapshot.elapsed - (last?.elapsed ?? 0)) > 0.05
        let calibrationDue = snapshot.rate > 0 && time - lastPublicationTime >= 5
        if changed || forceProgress || pausedPositionChanged || calibrationDue {
            transport.publish(snapshot, artwork: artwork)
            lastSnapshot = snapshot
            lastPublicationTime = time
        }
    }
}
