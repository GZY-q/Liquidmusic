import XCTest
@testable import Liquidmusic

@MainActor
final class PlaybackModeIntegrationTests: XCTestCase {
    func testNaturalRepeatOneKeepsPriorityUntilManualNext() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        let tracks = tracks(fixture, ids: ["first", "last", "inserted"])
        playback.mode = .repeatOne
        playback.play(tracks[0], in: Array(tracks.prefix(2)))
        try await eventually { playback.isPlaying && playback.canSeek }
        playback.playNext(tracks[2])
        let current = playback.queue.currentEntryID
        let priority = playback.queue.upcomingEntries.first?.id
        playback.seek(to: 2.9)
        try await eventually { playback.isPlaying && playback.elapsed < 0.6 }
        XCTAssertEqual(playback.queue.currentEntryID, current)
        XCTAssertEqual(playback.queue.upcomingEntries.first?.id, priority)
        XCTAssertTrue(playback.queue.historyEntries.isEmpty)
        playback.next()
        XCTAssertEqual(playback.queue.currentEntryID, priority)
        try await eventually { playback.isPlaying }
        XCTAssertNil(playback.errorMessage)
    }

    func testNaturalRepeatAllWrapsToFirstEntryAndManualPreviousReturnsToLast() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        let tracks = tracks(fixture, ids: ["first", "last"])
        playback.mode = .repeatAll
        playback.play(tracks[1], in: tracks)
        try await eventually { playback.isPlaying && playback.canSeek }
        let last = playback.queue.currentEntryID
        playback.seek(to: 2.9)
        try await eventually { playback.currentTrack?.id == "first" && playback.isPlaying }
        playback.previous()
        XCTAssertEqual(playback.queue.currentEntryID, last)
        try await eventually { playback.isPlaying }
        XCTAssertNil(playback.errorMessage)
    }

    func testPreviousRestartsAfterThreeSecondsAndRapidDuplicateEntryJumpsStayIsolated() async throws {
        let fixture = try AudioFixture(duration: 6)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        let tracks = tracks(fixture, ids: ["duplicate", "last"])
        playback.play(tracks[0], in: [tracks[0], tracks[0], tracks[1]])
        let first = playback.queue.entries[0]
        let second = playback.queue.entries[1]
        playback.jump(to: second)
        try await eventually { playback.isPlaying && playback.canSeek }
        playback.pause()
        playback.seek(to: 4)
        try await Task.sleep(for: .milliseconds(300))
        playback.previous()
        XCTAssertEqual(playback.queue.currentEntryID, second.id)
        try await eventually { playback.elapsed < 0.2 }
        playback.previous()
        XCTAssertEqual(playback.queue.currentEntryID, first.id)
        playback.next()
        XCTAssertEqual(playback.queue.currentEntryID, second.id)
        playback.next(); playback.previous(); playback.next()
        playback.mode = .shuffle
        playback.previous()
        XCTAssertEqual(playback.queue.currentEntryID, second.id)
        let selected = playback.queue.currentEntryID
        playback.jump(to: QueueEntry(track: tracks[0]))
        XCTAssertEqual(playback.queue.currentEntryID, selected)
        try await eventually { playback.isPlaying && playback.canSeek }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(playback.queue.currentEntryID, second.id)
        XCTAssertEqual(playback.duration, 6, accuracy: 0.05)
        XCTAssertLessThan(playback.elapsed, 1)
        XCTAssertNil(playback.errorMessage)
    }

    private func tracks(_ fixture: AudioFixture, ids: [String]) -> [Track] {
        ids.map { id in
            var track = fixture.track
            track.id = id
            track.title = id
            return track
        }
    }

    private func eventually(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            if ContinuousClock.now >= deadline { XCTFail("等待播放模式状态超时"); throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
