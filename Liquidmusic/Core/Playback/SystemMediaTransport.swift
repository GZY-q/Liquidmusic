import AppKit
import MediaPlayer

enum MediaCommand: Sendable {
    case play, pause, toggle, next, previous, seek(Double)
}

struct MediaCommandAvailability: Equatable, Sendable {
    var play = false, pause = false, toggle = false, next = false, previous = false, seek = false
}

enum MediaPlaybackPhase: Sendable { case playing, paused, stopped }

struct NowPlayingMetadata: Equatable, Sendable {
    let entryID: UUID?
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let artworkPath: String?
}

struct NowPlayingSnapshot: Sendable {
    var metadata: NowPlayingMetadata?
    var elapsed = 0.0
    var rate = 0.0
    var phase: MediaPlaybackPhase = .stopped

    @MainActor init(playback: PlaybackController) {
        if let track = playback.currentTrack {
            metadata = NowPlayingMetadata(entryID: playback.queue.currentEntryID, title: track.title,
                                          artist: track.artist, album: track.album, duration: playback.duration,
                                          artworkPath: track.artworkPath)
        }
        elapsed = playback.elapsed
        rate = playback.isPlaying ? 1 : 0
        phase = playback.isPlaying ? .playing : (playback.status == .idle || playback.status == .failed || playback.status == .ended ? .stopped : .paused)
    }

    init() {}
}

// 注入传输层，让测试验证注册、返回状态和发布内容，不触碰真实媒体键/控制中心。
@MainActor
protocol SystemMediaTransport: AnyObject {
    func register(_ handler: @escaping @Sendable (MediaCommand) -> MPRemoteCommandHandlerStatus)
    func setEnabled(_ availability: MediaCommandAvailability)
    func publish(_ snapshot: NowPlayingSnapshot, artwork: NSImage?)
    func unregister()
}

@MainActor
final class AppleSystemMediaTransport: SystemMediaTransport {
    private let commands = MPRemoteCommandCenter.shared()
    private var targets: [(MPRemoteCommand, Any)] = []
    private var metadata: NowPlayingMetadata?
    private var info: [String: Any] = [:]
    private var artworkImage: NSImage?
    private var artwork: MPMediaItemArtwork?

    func register(_ handler: @escaping @Sendable (MediaCommand) -> MPRemoteCommandHandlerStatus) {
        guard targets.isEmpty else { return }
        let mappings: [(MPRemoteCommand, MediaCommand)] = [
            (commands.playCommand, .play), (commands.pauseCommand, .pause), (commands.togglePlayPauseCommand, .toggle),
            (commands.nextTrackCommand, .next), (commands.previousTrackCommand, .previous)
        ]
        for (command, request) in mappings {
            targets.append((command, command.addTarget { _ in handler(request) }))
        }
        let seek = commands.changePlaybackPositionCommand
        let token = seek.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return handler(.seek(event.positionTime))
        }
        targets.append((seek, token))
    }

    func setEnabled(_ availability: MediaCommandAvailability) {
        commands.playCommand.isEnabled = availability.play
        commands.pauseCommand.isEnabled = availability.pause
        commands.togglePlayPauseCommand.isEnabled = availability.toggle
        commands.nextTrackCommand.isEnabled = availability.next
        commands.previousTrackCommand.isEnabled = availability.previous
        commands.changePlaybackPositionCommand.isEnabled = availability.seek
    }

    func publish(_ snapshot: NowPlayingSnapshot, artwork image: NSImage?) {
        let center = MPNowPlayingInfoCenter.default()
        guard let metadata = snapshot.metadata else {
            self.metadata = nil; info = [:]; artworkImage = nil; artwork = nil
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        // 静态字典仅在曲目/标签/时长变化时重建，进度发布复用现有字典和封面对象。
        if self.metadata != metadata {
            self.metadata = metadata
            info = [MPMediaItemPropertyTitle: metadata.title, MPMediaItemPropertyArtist: metadata.artist,
                    MPMediaItemPropertyAlbumTitle: metadata.album, MPMediaItemPropertyPlaybackDuration: metadata.duration,
                    MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
                    MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue]
        }
        if image !== artworkImage {
            artworkImage = image
            artwork = image.map { image in MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        }
        info[MPMediaItemPropertyArtwork] = artwork
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = snapshot.elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.rate
        center.nowPlayingInfo = info
        switch snapshot.phase {
        case .playing: center.playbackState = .playing
        case .paused: center.playbackState = .paused
        case .stopped: center.playbackState = .stopped
        }
    }

    func unregister() {
        for (command, token) in targets { command.isEnabled = false; command.removeTarget(token) }
        targets = []
    }
}
