import AVFoundation
import MediaPlayer
import XCTest
@testable import Liquidmusic

@MainActor
final class CrossfadeTests: XCTestCase {
    func testOneSecondCrossfadeUsesConfiguredAudioDuration() async throws {
        try await verifyConfiguredDuration(1)
    }

    func testSixSecondCrossfadeUsesConfiguredAudioDuration() async throws {
        try await verifyConfiguredDuration(6)
    }

    func testTwelveSecondCrossfadeUsesConfiguredAudioDuration() async throws {
        try await verifyConfiguredDuration(12)
    }

    func testMediaCommandsDuringOverlapPublishIncomingEntryAndSeekStopsOutgoing() async throws {
        let fixture = try AudioFixture(duration: 8)
        defer { fixture.remove() }
        var players: [AVPlayer] = []
        let playback = PlaybackController(connectSystemMedia: false) {
            let player = AVPlayer()
            player.isMuted = true
            players.append(player)
            return player
        }
        defer { playback.shutdown() }
        let transport = RecordingMediaTransport()
        playback.connectSystemMedia(transport: transport)
        let handler = try XCTUnwrap(transport.handler)
        playback.volume = 0.8
        playback.configureCrossfade(enabled: true, duration: 2)
        let tracks = tracks(fixture, count: 2)
        playback.play(tracks[0], in: tracks)
        let incomingID = playback.queue.entries[1].id
        try await eventually { playback.isPlaying }
        playback.seek(to: 5.8)
        try await eventually { playback.isCrossfading && playback.isPlaying && playback.elapsed > 0.2 }
        XCTAssertEqual(transport.publications.last?.snapshot.metadata?.entryID, incomingID)
        XCTAssertEqual(transport.publications.last?.snapshot.rate, 1)
        XCTAssertFalse(transport.enabled.next)
        XCTAssertTrue(transport.enabled.previous)
        XCTAssertEqual(handler(.pause), .success)
        XCTAssertEqual(transport.publications.last?.snapshot.rate, 0)
        XCTAssertTrue(players.allSatisfy { $0.rate == 0 })
        XCTAssertEqual(handler(.play), .success)
        try await eventually { playback.isPlaying }
        XCTAssertEqual(handler(.seek(1)), .success)
        XCTAssertFalse(playback.isCrossfading)
        XCTAssertNil(players[0].currentItem)
        XCTAssertEqual(try XCTUnwrap(transport.publications.last?.snapshot.elapsed), 1, accuracy: 0.01)
        XCTAssertEqual(transport.publications.last?.snapshot.metadata?.entryID, incomingID)
        playback.shutdown()
        XCTAssertEqual(transport.unregisterCount, 1)
        XCTAssertNil(transport.publications.last?.snapshot.metadata)
        XCTAssertEqual(handler(.play), .commandFailed)
    }

    func testOverlapGainsPauseResumeAndNaturalCompletion() async throws {
        let fixture = try AudioFixture(duration: 8)
        defer { fixture.remove() }
        var players: [AVPlayer] = []
        let playback = PlaybackController(connectSystemMedia: false) {
            let player = AVPlayer()
            player.isMuted = true
            players.append(player)
            return player
        }
        defer { playback.shutdown() }
        playback.volume = 0.8
        playback.configureCrossfade(enabled: true, duration: 2)
        let tracks = tracks(fixture, count: 2)
        playback.play(tracks[0], in: tracks)
        try await eventually { playback.isPlaying }
        playback.seek(to: 5.8)
        try await eventually { playback.isCrossfading && playback.elapsed > 0.25 }
        XCTAssertEqual(playback.currentTrack?.id, "1")
        XCTAssertEqual(playback.queue.historyEntries.map(\.track.id), ["0"])
        XCTAssertEqual(players.count, 2)
        XCTAssertGreaterThan(players[0].volume, 0)
        XCTAssertGreaterThan(players[1].volume, 0)
        XCTAssertEqual(players[0].volume + players[1].volume, 0.8, accuracy: 0.02)
        playback.pause()
        let position = players[1].currentTime().seconds
        let gains = players.map(\.volume)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(playback.isCrossfading)
        XCTAssertEqual(players[0].rate, 0)
        XCTAssertEqual(players[1].rate, 0)
        XCTAssertEqual(players[1].currentTime().seconds, position, accuracy: 0.08)
        XCTAssertEqual(players[1].volume, gains[1], accuracy: 0.04)
        playback.volume = 0.4
        XCTAssertEqual(players[0].volume + players[1].volume, 0.4, accuracy: 0.02)
        playback.resume()
        try await eventually { !playback.isCrossfading && playback.isPlaying }
        XCTAssertNil(players[0].currentItem)
        XCTAssertEqual(players[1].volume, 0.4, accuracy: 0.001)
        XCTAssertEqual(playback.currentTrack?.id, "1")
    }

    func testSeekDisableRapidNextAndShutdownReleaseBothPlayers() async throws {
        let fixture = try AudioFixture(duration: 8)
        defer { fixture.remove() }
        var players: [AVPlayer] = []
        let playback = PlaybackController(connectSystemMedia: false) {
            let player = AVPlayer()
            player.isMuted = true
            players.append(player)
            return player
        }
        defer { playback.shutdown() }
        playback.volume = 0
        playback.configureCrossfade(enabled: true, duration: 2)
        let tracks = tracks(fixture, count: 4)
        playback.play(tracks[0], in: tracks)
        try await eventually { playback.isPlaying }
        playback.seek(to: 6)
        try await eventually { playback.isCrossfading }
        playback.seek(to: 1)
        XCTAssertFalse(playback.isCrossfading)
        XCTAssertNil(players[0].currentItem)
        try await eventually { playback.elapsed >= 1 && playback.elapsed < 2 }
        playback.seek(to: 6)
        try await eventually { playback.isCrossfading }
        playback.configureCrossfade(enabled: false, duration: 2)
        XCTAssertFalse(playback.isCrossfading)
        XCTAssertEqual(playback.currentTrack?.id, "2")
        playback.configureCrossfade(enabled: true, duration: 2)
        playback.seek(to: 6)
        try await eventually { playback.isCrossfading }
        playback.previous()
        playback.next()
        playback.shutdown()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(players.allSatisfy { $0.currentItem == nil && $0.rate == 0 })
        XCTAssertEqual(playback.status, .idle)
    }

    func testRepeatOneAndDisabledModeDoNotOverlap() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        let tracks = tracks(fixture, count: 2)
        playback.configureCrossfade(enabled: true, duration: 2)
        playback.mode = .repeatOne
        playback.play(tracks[0], in: tracks)
        try await eventually { playback.isPlaying }
        playback.seek(to: 2.8)
        try await eventually { playback.elapsed < 0.5 }
        XCTAssertEqual(playback.currentTrack?.id, "0")
        XCTAssertFalse(playback.isCrossfading)
        playback.configureCrossfade(enabled: false, duration: 2)
        playback.mode = .sequential
        playback.seek(to: 2.8)
        try await eventually { playback.currentTrack?.id == "1" }
        XCTAssertFalse(playback.isCrossfading)
    }

    func testPriorityChangeInvalidatesPreparedTrackAndDuplicateEntriesStayDistinct() async throws {
        let fixture = try AudioFixture(duration: 8)
        defer { fixture.remove() }
        var players: [AVPlayer] = []
        let playback = PlaybackController(connectSystemMedia: false) {
            let player = AVPlayer()
            player.isMuted = true
            players.append(player)
            return player
        }
        defer { playback.shutdown() }
        playback.volume = 0
        playback.configureCrossfade(enabled: true, duration: 1)
        let track = fixture.track
        playback.play(track, in: [track, track])
        let firstID = playback.queue.currentEntryID
        try await eventually { playback.isPlaying }
        playback.seek(to: 5.1)
        try await eventually { players.count == 2 }
        playback.pause()
        playback.playNext(track)
        let priority = playback.queue.upcomingEntries.first?.id
        XCTAssertNil(players[1].currentItem)
        playback.seek(to: 6.9)
        playback.resume()
        try await eventually { playback.isCrossfading }
        XCTAssertEqual(playback.queue.currentEntryID, priority)
        XCTAssertNotEqual(playback.queue.currentEntryID, firstID)
        XCTAssertEqual(playback.queue.historyEntries.map(\.id), [firstID!])
    }

    func testUnreadableNextTrackDoesNotInterruptCurrentEarly() async throws {
        let fixture = try AudioFixture(duration: 4)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        playback.configureCrossfade(enabled: true, duration: 2)
        var broken = fixture.track
        broken.id = "missing"
        broken.path = fixture.directory.appendingPathComponent("missing.wav").path
        playback.play(fixture.track, in: [fixture.track, broken])
        try await eventually { playback.isPlaying }
        playback.seek(to: 2.1)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(playback.currentTrack?.id, fixture.track.id)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertFalse(playback.isCrossfading)
        XCTAssertNil(playback.errorMessage)
        try await eventually { playback.status == .failed }
        XCTAssertEqual(playback.currentTrack?.id, "missing")
    }

    func testRepeatAllAndShuffleCommitPredictedEntryExactlyOnce() async throws {
        let fixture = try AudioFixture(duration: 4)
        defer { fixture.remove() }
        for mode in [PlaybackMode.repeatAll, .shuffle] {
            let playback = PlaybackController(connectSystemMedia: false)
            playback.volume = 0
            defer { playback.shutdown() }
            let tracks = tracks(fixture, count: 3)
            playback.configureCrossfade(enabled: true, duration: 1)
            playback.mode = mode
            playback.play(tracks[2], in: tracks)
            var expectedQueue = playback.queue
            XCTAssertTrue(expectedQueue.advance(automatically: true))
            try await eventually { playback.isPlaying }
            playback.seek(to: 2.9)
            try await eventually { playback.isCrossfading }
            XCTAssertEqual(playback.queue.currentEntryID, expectedQueue.currentEntryID)
            XCTAssertEqual(playback.queue.upcomingEntries.map(\.id), expectedQueue.upcomingEntries.map(\.id))
            try await eventually { !playback.isCrossfading }
            XCTAssertEqual(playback.queue.historyEntries.map(\.id), expectedQueue.historyEntries.map(\.id))
        }
    }

    func testReleasingControllerDuringOverlapStopsBothPlayers() async throws {
        let fixture = try AudioFixture(duration: 4)
        defer { fixture.remove() }
        var players: [AVPlayer] = []
        var playback: PlaybackController? = PlaybackController(connectSystemMedia: false) {
            let player = AVPlayer()
            player.isMuted = true
            players.append(player)
            return player
        }
        weak var weakPlayback = playback
        playback?.volume = 0
        playback?.configureCrossfade(enabled: true, duration: 1)
        let tracks = tracks(fixture, count: 2)
        playback?.play(tracks[0], in: tracks)
        try await eventually { playback?.isPlaying == true }
        playback?.seek(to: 2.9)
        try await eventually { playback?.isCrossfading == true }
        playback = nil
        try await eventually { weakPlayback == nil }
        XCTAssertTrue(players.allSatisfy { $0.currentItem == nil && $0.rate == 0 })
    }

    private func tracks(_ fixture: AudioFixture, count: Int) -> [Track] {
        (0..<count).map {
            var track = fixture.track
            track.id = "\($0)"
            return track
        }
    }

    private func verifyConfiguredDuration(_ requested: Double) async throws {
        let fixture = try AudioFixture(duration: 30)
        defer { fixture.remove() }
        var players: [AVPlayer] = []
        let playback = PlaybackController(connectSystemMedia: false) {
            let player = AVPlayer()
            player.isMuted = true
            players.append(player)
            return player
        }
        defer { playback.shutdown() }
        playback.volume = 0.8
        playback.configureCrossfade(enabled: true, duration: requested)
        let tracks = tracks(fixture, count: 2)
        playback.play(tracks[0], in: tracks)
        try await eventually { playback.isPlaying }
        playback.seek(to: fixture.duration - requested - 0.4)
        try await eventually { playback.isCrossfading }
        XCTAssertEqual(playback.currentTrack?.id, "1")
        try await eventually(timeout: requested + 2) { playback.elapsed >= requested / 2 }
        XCTAssertTrue(playback.isCrossfading)
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players[1].volume, Float(0.8 * playback.elapsed / requested), accuracy: 0.08)
        XCTAssertEqual(players[0].volume + players[1].volume, 0.8, accuracy: 0.02)
        try await eventually(timeout: requested + 2) { !playback.isCrossfading }
        // 由真实音频时钟推进整个渐变，不能用控制器 seek 提前结束来冒充时长验证。
        XCTAssertGreaterThanOrEqual(playback.elapsed, requested - 0.25)
        XCTAssertLessThan(playback.elapsed, requested + 0.75)
        XCTAssertNil(players[0].currentItem)
        XCTAssertEqual(players[1].volume, 0.8, accuracy: 0.001)
        XCTAssertEqual(playback.queue.historyEntries.count, 1)
        XCTAssertNil(playback.errorMessage)
    }

    private func eventually(timeout: Double = 6, _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while !condition() {
            if ContinuousClock.now >= deadline { XCTFail("等待交叉渐变状态超时"); throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
