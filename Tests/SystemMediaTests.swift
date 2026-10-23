import AppKit
import MediaPlayer
import XCTest
@testable import Liquidmusic

@MainActor
final class SystemMediaTests: XCTestCase {
    func testEmptyCommandsShutdownAndLateCallbackAreSafeWithoutSystemRegistration() throws {
        let playback = PlaybackController(connectSystemMedia: false)
        let transport = RecordingMediaTransport()
        let media = SystemMediaController(playback: playback, transport: transport)
        defer { playback.shutdown() }
        XCTAssertEqual(transport.registrationCount, 1)
        XCTAssertEqual(transport.enabled, MediaCommandAvailability())
        for command in [MediaCommand.play, .pause, .toggle, .next, .previous, .seek(1)] {
            XCTAssertEqual(media.handle(command), .noSuchContent)
        }
        let lateHandler = try XCTUnwrap(transport.handler)
        media.shutdown(); media.shutdown()
        XCTAssertEqual(transport.unregisterCount, 1)
        XCTAssertNil(transport.publications.last?.snapshot.metadata)
        XCTAssertEqual(transport.publications.last?.snapshot.phase, .stopped)
        XCTAssertEqual(lateHandler(.play), .commandFailed)
        XCTAssertEqual(transport.enabled, MediaCommandAvailability())
    }

    func testCommandsControlSamePlayerAndRejectInvalidSeekAndMissingSuccessor() async throws {
        let fixture = try AudioFixture(duration: 6)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        playback.play(fixture.track, in: [fixture.track])
        try await eventually { playback.canSeek && playback.isPlaying }
        let transport = RecordingMediaTransport()
        let media = SystemMediaController(playback: playback, transport: transport)
        defer { media.shutdown() }
        XCTAssertTrue(transport.enabled.pause)
        XCTAssertFalse(transport.enabled.play)
        XCTAssertFalse(transport.enabled.next)
        XCTAssertEqual(media.handle(.pause), .success)
        XCTAssertFalse(playback.wantsToPlay)
        XCTAssertEqual(media.handle(.seek(2)), .success)
        XCTAssertEqual(playback.elapsed, 2, accuracy: 0.01)
        for position in [-1.0, 7, .nan, .infinity] { XCTAssertEqual(media.handle(.seek(position)), .commandFailed) }
        XCTAssertEqual(media.handle(.next), .noSuchContent)
        XCTAssertEqual(media.handle(.play), .success)
        XCTAssertTrue(playback.wantsToPlay)
        XCTAssertEqual(media.handle(.toggle), .success)
        XCTAssertFalse(playback.wantsToPlay)
        XCTAssertEqual(media.handle(.previous), .success)
        XCTAssertEqual(playback.elapsed, 0, accuracy: 0.01)
        playback.mode = .repeatAll
        media.update(playback)
        XCTAssertTrue(transport.enabled.next)
    }

    func testFailureDisablesPlayAndSeekButAllowsSkippingToValidContent() async throws {
        let fixture = try AudioFixture(duration: 6)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        var missing = fixture.track
        missing.id = "missing"; missing.path = fixture.directory.appendingPathComponent("missing.wav").path
        playback.play(missing, in: [missing, fixture.track])
        let transport = RecordingMediaTransport()
        let media = SystemMediaController(playback: playback, transport: transport)
        defer { media.shutdown() }
        XCTAssertEqual(transport.publications.last?.snapshot.phase, .stopped)
        XCTAssertFalse(transport.enabled.toggle)
        XCTAssertFalse(transport.enabled.seek)
        XCTAssertTrue(transport.enabled.next)
        XCTAssertEqual(media.handle(.play), .commandFailed)
        XCTAssertEqual(media.handle(.seek(0)), .commandFailed)
        XCTAssertEqual(media.handle(.next), .success)
        XCTAssertEqual(playback.currentTrack?.id, fixture.track.id)
        try await eventually { playback.isPlaying }
        media.update(playback)
        XCTAssertEqual(transport.publications.last?.snapshot.rate, 1)
    }

    func testPublicationThrottlesTicksAndImmediatelyPublishesPauseAndSeek() async throws {
        let fixture = try AudioFixture(duration: 6)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        playback.play(fixture.track, in: [fixture.track])
        try await eventually { playback.isPlaying }
        let transport = RecordingMediaTransport()
        let clock = MediaTestClock()
        let media = SystemMediaController(playback: playback, transport: transport, clock: { clock.now })
        defer { media.shutdown() }
        for index in 1..<50 { clock.now = Double(index) / 10; media.update(playback) }
        XCTAssertEqual(transport.publications.count, 1)
        clock.now = 5
        media.update(playback)
        XCTAssertEqual(transport.publications.count, 2)
        XCTAssertEqual(media.handle(.pause), .success)
        XCTAssertEqual(transport.publications.last?.snapshot.rate, 0)
        let pausedCount = transport.publications.count
        for _ in 0..<20 { media.update(playback) }
        XCTAssertEqual(transport.publications.count, pausedCount)
        XCTAssertEqual(media.handle(.seek(3)), .success)
        XCTAssertEqual(transport.publications.count, pausedCount + 1)
        XCTAssertEqual(transport.publications.last?.snapshot.elapsed, 3)
    }

    func testPlayerMediaConnectionIsIdempotentAndReleasesHandlersOnShutdown() throws {
        let transport = RecordingMediaTransport(), ignored = RecordingMediaTransport()
        var playback: PlaybackController? = PlaybackController(connectSystemMedia: false)
        weak let weakPlayback = playback
        playback?.connectSystemMedia(transport: transport)
        playback?.connectSystemMedia(transport: ignored)
        XCTAssertEqual(transport.registrationCount, 1)
        XCTAssertEqual(ignored.registrationCount, 0)
        let handler = try XCTUnwrap(transport.handler)
        playback?.shutdown(); playback?.shutdown()
        playback = nil
        XCTAssertNil(weakPlayback)
        XCTAssertEqual(transport.unregisterCount, 1)
        XCTAssertEqual(handler(.pause), .commandFailed)
    }

    func testBackgroundCommandSynchronouslyChecksAndExecutesOnMainActor() async throws {
        let fixture = try AudioFixture(duration: 6)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        playback.play(fixture.track, in: [fixture.track])
        try await eventually { playback.isPlaying }
        let transport = RecordingMediaTransport()
        let media = SystemMediaController(playback: playback, transport: transport)
        defer { media.shutdown() }
        let handler = try XCTUnwrap(transport.handler)
        let result = await Task.detached { handler(.pause) }.value
        XCTAssertEqual(result, .success)
        XCTAssertFalse(playback.wantsToPlay)
        XCTAssertEqual(playback.status, .paused)
    }

    func testArtworkLateResultsCannotReplaceNewCoverAndSamePathIsReused() async throws {
        let fixture = try AudioFixture(duration: 6)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        var first = fixture.track, second = fixture.track
        first.id = "first"; first.artworkPath = "/mock/first.jpg"
        second.id = "second"; second.artworkPath = "/mock/second.jpg"
        playback.play(first, in: [first, second])
        let loader = ControlledMediaArtworkLoader()
        let transport = RecordingMediaTransport()
        let media = SystemMediaController(playback: playback, transport: transport, loadArtwork: { await loader.read($0) })
        defer { media.shutdown() }
        try await eventuallyAsync { await loader.contains("/mock/first.jpg") }
        playback.play(second, in: [second])
        media.update(playback)
        try await eventuallyAsync { await loader.contains("/mock/second.jpg") }
        let data = try coverData()
        await loader.complete("/mock/second.jpg", data: data)
        try await eventually { transport.publications.last?.hasArtwork == true }
        playback.pause()
        media.update(playback)
        let count = transport.publications.count
        await loader.complete("/mock/first.jpg", data: data)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(transport.publications.count, count)
        XCTAssertEqual(transport.publications.last?.snapshot.metadata?.entryID, playback.queue.currentEntryID)
        playback.play(second, in: [second])
        media.update(playback)
        XCTAssertTrue(transport.publications.last?.hasArtwork == true)
        let reads = await loader.readCount
        XCTAssertEqual(reads, 2)
    }

    func testShutdownRejectsLateArtworkWithoutPublishingAgain() async throws {
        let fixture = try AudioFixture(duration: 6)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        var track = fixture.track
        track.artworkPath = "/mock/cover.jpg"
        playback.play(track, in: [track])
        let loader = ControlledMediaArtworkLoader(), transport = RecordingMediaTransport()
        var media: SystemMediaController? = SystemMediaController(playback: playback, transport: transport, loadArtwork: { await loader.read($0) })
        weak let weakMedia = media
        try await eventuallyAsync { await loader.contains("/mock/cover.jpg") }
        media?.shutdown(); media = nil
        XCTAssertNil(weakMedia)
        let count = transport.publications.count
        await loader.complete("/mock/cover.jpg", data: try coverData())
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(transport.publications.count, count)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async throws {
        try await eventuallyAsync { condition() }
    }
    private func eventuallyAsync(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            if ContinuousClock.now >= deadline { XCTFail("等待媒体集成状态超时"); throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func coverData() throws -> Data {
        let bundle = Bundle(for: SystemMediaTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "cover", withExtension: "jpg")
                                ?? bundle.url(forResource: "cover", withExtension: "jpg", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

@MainActor
final class RecordingMediaTransport: SystemMediaTransport {
    struct Publication { let snapshot: NowPlayingSnapshot; let hasArtwork: Bool }
    var handler: (@Sendable (MediaCommand) -> MPRemoteCommandHandlerStatus)?
    var enabled = MediaCommandAvailability()
    var publications: [Publication] = []
    var registrationCount = 0, unregisterCount = 0
    func register(_ handler: @escaping @Sendable (MediaCommand) -> MPRemoteCommandHandlerStatus) {
        self.handler = handler; registrationCount += 1
    }
    func setEnabled(_ availability: MediaCommandAvailability) { enabled = availability }
    func publish(_ snapshot: NowPlayingSnapshot, artwork: NSImage?) {
        publications.append(Publication(snapshot: snapshot, hasArtwork: artwork != nil))
    }
    func unregister() { handler = nil; unregisterCount += 1 }
}

// 故意忽略取消，验证迟到的封面不能覆盖新曲目或终止状态。
private actor ControlledMediaArtworkLoader {
    private var requests: [String: CheckedContinuation<Data?, Never>] = [:]
    private(set) var readCount = 0
    func read(_ path: String) async -> Data? {
        readCount += 1
        return await withCheckedContinuation { requests[path] = $0 }
    }
    func contains(_ path: String) -> Bool { requests[path] != nil }
    func complete(_ path: String, data: Data) { requests.removeValue(forKey: path)?.resume(returning: data) }
}

@MainActor private final class MediaTestClock { var now = 0.0 }
