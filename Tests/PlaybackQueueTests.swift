import XCTest
@testable import Liquidmusic

final class PlaybackQueueTests: XCTestCase {
    func testThousandEntryProjectionAndInsertionsKeepOrderAndDoNotConsumeQueue() {
        for mode in [PlaybackMode.sequential, .shuffle] {
            let clock = ContinuousClock()
            var queue = PlaybackQueue(shuffleSeed: 42)
            queue.mode = mode
            queue.replace(with: SPXData.largeLibrary, startingAt: SPXData.largeLibrary[0])
            let original = queue.upcomingEntries.map(\.id)
            let insertedAt = clock.now
            for index in 0..<20 { queue.insertNext(extra("insert-\(index)")) }
            let projectedAt = clock.now
            let projection = queue.upcomingEntries
            let finished = clock.now
            XCTAssertEqual(projection.count, 1_019)
            XCTAssertEqual(Set(projection.map(\.id)).count, projection.count)
            XCTAssertEqual(projection.prefix(20).map(\.track.id), (0..<20).reversed().map { "insert-\($0)" })
            XCTAssertEqual(Array(projection.dropFirst(20).map(\.id)), original)
            XCTAssertEqual(queue.current?.id, "scale-0")
            XCTAssertTrue(queue.historyEntries.isEmpty)
            // 投影首项应与真实下一首相符，读取投影不得消耗候选或随机源。
            XCTAssertTrue(queue.advance())
            XCTAssertEqual(queue.currentEntryID, projection.first?.id)
            print("M7_SCALE mode=\(mode.rawValue) insert20=\(insertedAt.duration(to: projectedAt)) projection1019=\(projectedAt.duration(to: finished))")
        }
    }

    func testEmptyQueueIsSafeInEveryMode() {
        for mode in PlaybackMode.allCases {
            var queue = PlaybackQueue(shuffleSeed: 1)
            queue.mode = mode
            queue.replace(with: [], startingAt: tracks()[0])
            XCTAssertNil(queue.currentEntry)
            XCTAssertFalse(queue.advance())
            XCTAssertFalse(queue.advance(automatically: true))
            XCTAssertFalse(queue.previous())
            XCTAssertFalse(queue.jump(to: UUID()))
            XCTAssertTrue(queue.upcomingEntries.isEmpty)
        }
    }

    func testSingleTrackStopsOrRepeatsAccordingToModeWithoutSelfHistory() {
        for mode in PlaybackMode.allCases {
            var queue = makeQueue(count: 1, mode: mode)
            let id = queue.currentEntryID
            XCTAssertEqual(queue.advance(automatically: true), mode != .sequential)
            XCTAssertEqual(queue.currentEntryID, id)
            XCTAssertEqual(queue.advance(), mode == .repeatAll || mode == .shuffle)
            XCTAssertFalse(queue.previous())
            XCTAssertTrue(queue.historyEntries.isEmpty)
            XCTAssertTrue(queue.upcomingEntries.isEmpty)
        }
    }

    func testSequentialMiddleAndEndKeepCurrentEntryAndActualHistory() {
        let tracks = tracks(count: 3)
        var queue = PlaybackQueue(shuffleSeed: 1)
        queue.replace(with: tracks, startingAt: tracks[1])
        XCTAssertEqual(queue.upcomingEntries.map(\.track.id), ["2"])
        XCTAssertTrue(queue.advance(automatically: true))
        let last = queue.currentEntryID
        XCTAssertFalse(queue.advance(automatically: true))
        XCTAssertEqual(queue.currentEntryID, last)
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.current?.id, "1")
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.currentEntryID, last)
    }

    func testRepeatAllWrapsAndPreviousFollowsHistoryAcrossBoundary() {
        var queue = makeQueue(count: 3, mode: .repeatAll)
        let first = queue.currentEntryID
        queue.advance(); queue.advance()
        let last = queue.currentEntryID
        XCTAssertTrue(queue.advance(automatically: true))
        XCTAssertEqual(queue.currentEntryID, first)
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.currentEntryID, last)
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.currentEntryID, first)
    }

    func testRepeatOneNaturalEndDoesNotConsumeInsertionButManualNextDoes() {
        var queue = makeQueue(count: 2, mode: .repeatOne)
        let first = queue.currentEntryID
        queue.insertNext(extra("inserted"))
        let inserted = queue.upcomingEntries[0].id
        for _ in 0..<3 {
            XCTAssertTrue(queue.advance(automatically: true))
            XCTAssertEqual(queue.currentEntryID, first)
            XCTAssertEqual(queue.upcomingEntries.first?.id, inserted)
        }
        XCTAssertTrue(queue.historyEntries.isEmpty)
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.currentEntryID, inserted)
        XCTAssertTrue(queue.advance(automatically: true))
        XCTAssertEqual(queue.currentEntryID, inserted)
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current?.id, "1")
        XCTAssertFalse(queue.advance())
    }

    func testRepeatedInsertionsAreNewestFirstAndResumeOriginalOrder() {
        var queue = makeQueue(count: 3)
        queue.insertNext(extra("X")); queue.insertNext(extra("Y"))
        XCTAssertEqual(queue.upcomingEntries.map(\.track.id), ["Y", "X", "1", "2"])
        var visited: [String] = []
        while queue.advance() { visited.append(queue.current!.id) }
        XCTAssertEqual(visited, ["Y", "X", "1", "2"])
        XCTAssertEqual(queue.historyEntries.map(\.track.id), ["0", "Y", "X", "1"])
    }

    func testInsertIntoEmptyQueueDoesNotLeaveCurrentInPriorityList() {
        var queue = PlaybackQueue(shuffleSeed: 1)
        queue.insertNext(extra("first"))
        XCTAssertEqual(queue.current?.id, "first")
        XCTAssertTrue(queue.upcomingEntries.isEmpty)
        XCTAssertFalse(queue.advance())
        queue.insertNext(extra("second"))
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current?.id, "second")
        XCTAssertFalse(queue.advance())
    }

    func testDuplicateTracksUseEntryIDsAndStaleJumpDoesNotChangeQueue() {
        let track = tracks()[0]
        var queue = PlaybackQueue(shuffleSeed: 1)
        queue.replace(with: [track, track, extra("other")], startingAt: track)
        let ids = queue.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertTrue(queue.jump(to: ids[1]))
        XCTAssertEqual(queue.currentEntryID, ids[1])
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.currentEntryID, ids[2])
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.currentEntryID, ids[1])
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.currentEntryID, ids[0])
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.currentEntryID, ids[1])
        let history = queue.historyEntries
        XCTAssertFalse(queue.jump(to: UUID()))
        XCTAssertEqual(queue.historyEntries, history)
        XCTAssertEqual(queue.currentEntryID, ids[1])
    }

    func testShuffleHasNoRepeatsWithinEachCycleAndNoImmediateRepeatAcrossCycles() {
        // 多个固定种子验证不变量，不依赖某次洗牌恰巧产生特定顺序。
        for seed in UInt64(0)..<32 {
            var queue = makeQueue(count: 6, mode: .shuffle, seed: seed)
            for _ in 0..<4 {
                var seen: Set<UUID> = [queue.currentEntryID!]
                for _ in 1..<queue.entries.count {
                    XCTAssertTrue(queue.advance(automatically: true))
                    XCTAssertTrue(seen.insert(queue.currentEntryID!).inserted)
                }
                XCTAssertEqual(seen, Set(queue.entries.map(\.id)))
                let last = queue.currentEntryID
                XCTAssertTrue(queue.advance())
                XCTAssertNotEqual(queue.currentEntryID, last)
            }
        }
    }

    func testShuffleInsertionsPreserveUnplayedCandidateOrderAndDoNotRepeatVisitedEntries() {
        for seed in UInt64(0)..<16 {
            var queue = makeQueue(count: 6, mode: .shuffle, seed: seed)
            queue.advance(); queue.advance()
            let visited = Set(queue.historyEntries.map(\.id) + [queue.currentEntryID!])
            let remaining = queue.upcomingEntries.map(\.id)
            queue.insertNext(extra("X")); queue.insertNext(extra("Y"))
            queue.advance()
            XCTAssertEqual(queue.current?.id, "Y")
            queue.advance()
            XCTAssertEqual(queue.current?.id, "X")
            XCTAssertEqual(queue.upcomingEntries.map(\.id), remaining)
            for id in remaining {
                XCTAssertTrue(queue.advance())
                XCTAssertEqual(queue.currentEntryID, id)
                XCTAssertFalse(visited.contains(id))
            }
            let last = queue.currentEntryID
            queue.advance()
            XCTAssertNotEqual(queue.currentEntryID, last)
        }
    }

    func testJumpingToPriorityEntryConsumesItWithoutReplayingItInLinearTail() {
        var queue = makeQueue(count: 3)
        queue.insertNext(extra("X")); queue.insertNext(extra("Y"))
        let target = queue.entries.first { $0.track.id == "X" }!
        queue.jump(to: target.id)
        XCTAssertEqual(queue.upcomingEntries.map(\.track.id), ["Y", "1", "2"])
        for expected in ["Y", "1", "2"] {
            XCTAssertTrue(queue.advance())
            XCTAssertEqual(queue.current?.id, expected)
        }
        XCTAssertFalse(queue.advance())
    }

    func testShuffleJumpConsumesOrdinaryCandidateAndPriorityEntry() {
        var queue = makeQueue(count: 5, mode: .shuffle)
        let ordinary = queue.upcomingEntries[1]
        queue.jump(to: ordinary.id)
        XCTAssertFalse(queue.upcomingEntries.contains { $0.id == ordinary.id })
        queue.insertNext(extra("X")); queue.insertNext(extra("Y"))
        let target = queue.entries.first { $0.track.id == "X" }!
        queue.jump(to: target.id)
        let upcoming = queue.upcomingEntries
        XCTAssertEqual(upcoming.first?.track.id, "Y")
        XCTAssertFalse(upcoming.contains { $0.id == target.id || $0.id == ordinary.id })
        XCTAssertEqual(Set(upcoming.map(\.id)).count, upcoming.count)
        for entry in upcoming {
            queue.advance()
            XCTAssertEqual(queue.currentEntryID, entry.id)
        }
    }

    func testShufflePreviousAndForwardRetraceActualHistoryWithoutReshuffling() {
        var queue = makeQueue(count: 6, mode: .shuffle)
        XCTAssertFalse(queue.previous())
        queue.advance(); queue.advance(); queue.advance()
        let current = queue.currentEntryID
        let history = queue.historyEntries.map(\.id)
        let remaining = queue.upcomingEntries.map(\.id)
        queue.previous()
        XCTAssertEqual(queue.currentEntryID, history[2])
        queue.previous()
        XCTAssertEqual(queue.currentEntryID, history[1])
        XCTAssertEqual(Array(queue.upcomingEntries.prefix(2)).map(\.id), [history[2], current!])
        queue.advance(); queue.advance()
        XCTAssertEqual(queue.currentEntryID, current)
        XCTAssertEqual(queue.upcomingEntries.map(\.id), remaining)
    }

    func testModeChangesPreserveHistoryAndPendingPriorityAndSameModeDoesNotReshuffle() {
        var queue = makeQueue(count: 5, mode: .shuffle)
        queue.advance()
        let remaining = queue.upcomingEntries.map(\.id)
        queue.mode = .shuffle
        XCTAssertEqual(queue.upcomingEntries.map(\.id), remaining)
        let history = queue.historyEntries
        queue.insertNext(extra("X"))
        for mode in PlaybackMode.allCases {
            queue.mode = mode
            XCTAssertEqual(queue.historyEntries, history)
            XCTAssertEqual(queue.upcomingEntries.first?.track.id, "X")
        }
        queue.advance()
        XCTAssertEqual(queue.current?.id, "X")
        XCTAssertFalse(queue.upcomingEntries.contains { $0.id == queue.currentEntryID })
    }

    func testReplaceResetsNavigationAndPriorityButRetainsMode() {
        var queue = makeQueue(count: 4, mode: .shuffle)
        queue.advance(); queue.insertNext(extra("old")); queue.previous()
        let newTracks = [extra("newA"), extra("newB")]
        queue.replace(with: newTracks, startingAt: newTracks[0])
        XCTAssertEqual(queue.mode, .shuffle)
        XCTAssertEqual(queue.current?.id, "newA")
        XCTAssertTrue(queue.historyEntries.isEmpty)
        XCTAssertEqual(queue.upcomingEntries.map(\.track.id), ["newB"])
        queue.replace(with: newTracks, startingAt: extra("not-present"))
        XCTAssertEqual(queue.current?.id, "newA")
    }

    func testUpcomingProjectionMatchesManualTraversalWithoutMutatingQueue() {
        for mode in PlaybackMode.allCases {
            var queue = makeQueue(count: 5, mode: mode)
            queue.advance(); queue.advance(); queue.previous()
            queue.insertNext(extra("X")); queue.insertNext(extra("Y"))
            let current = queue.currentEntryID
            let history = queue.historyEntries
            let upcoming = queue.upcomingEntries
            XCTAssertEqual(queue.upcomingEntries, upcoming)
            XCTAssertEqual(queue.currentEntryID, current)
            XCTAssertEqual(queue.historyEntries, history)
            for expected in upcoming {
                XCTAssertTrue(queue.advance())
                XCTAssertEqual(queue.currentEntryID, expected.id)
            }
        }
    }

    func testHistoryIsBoundedDuringLongRunningRepeatPlayback() {
        var queue = makeQueue(count: 3, mode: .repeatAll)
        for _ in 0..<1_000 { queue.advance() }
        XCTAssertEqual(queue.historyEntries.count, 200)
        let previous = queue.historyEntries.last?.id
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.currentEntryID, previous)
    }

    private func makeQueue(count: Int = 6, mode: PlaybackMode = .sequential, seed: UInt64 = 1) -> PlaybackQueue {
        let tracks = tracks(count: count)
        var queue = PlaybackQueue(shuffleSeed: seed)
        queue.mode = mode
        queue.replace(with: tracks, startingAt: tracks[0])
        return queue
    }
    private func tracks(count: Int = 6) -> [Track] { (0..<count).map { extra("\($0)") } }
    private func extra(_ id: String) -> Track {
        Track(id: id, folderID: "test", path: "/test/\(id).wav", title: id, artist: "Artist",
              album: "Album", albumArtist: "Artist", duration: 60, modifiedAt: .distantPast)
    }
}

final class PlaybackScrubTests: XCTestCase {
    func testDragKeepsTemporaryPositionAcrossPlaybackTicksAndOnlyCommitsOnRelease() {
        let id = UUID()
        var scrub = PlaybackScrubState()
        scrub.begin(entryID: id, elapsed: 10, duration: 100)
        XCTAssertNil(scrub.update(45, entryID: id, duration: 100))
        XCTAssertEqual(scrub.displayedPosition(elapsed: 11, duration: 100), 45)
        XCTAssertEqual(scrub.displayedPosition(elapsed: 12, duration: 100), 45)
        XCTAssertEqual(scrub.finish(entryID: id, duration: 100), 45)
        XCTAssertEqual(scrub.displayedPosition(elapsed: 46, duration: 100), 46)
        XCTAssertNil(scrub.finish(entryID: id, duration: 100))
    }

    func testKeyboardWritesSeekImmediatelyAndClampInvalidInput() {
        let id = UUID()
        var scrub = PlaybackScrubState()
        XCTAssertEqual(scrub.update(25, entryID: id, duration: 100), 25)
        XCTAssertEqual(scrub.update(-10, entryID: id, duration: 100), 0)
        XCTAssertEqual(scrub.update(200, entryID: id, duration: 100), 100)
        XCTAssertNil(scrub.update(.nan, entryID: id, duration: 100))
        XCTAssertNil(scrub.update(20, entryID: nil, duration: 100))
    }

    func testChangingEntryRejectsOldDragAndCancellationRestoresLivePosition() {
        let old = UUID(), new = UUID()
        var scrub = PlaybackScrubState()
        scrub.begin(entryID: old, elapsed: 10, duration: 100)
        scrub.update(80, entryID: old, duration: 100)
        XCTAssertNil(scrub.update(90, entryID: new, duration: 100))
        XCTAssertNil(scrub.finish(entryID: new, duration: 100))
        XCTAssertEqual(scrub.displayedPosition(elapsed: 2, duration: 100), 2)
        scrub.begin(entryID: new, elapsed: 2, duration: 100)
        scrub.update(40, entryID: new, duration: 100)
        scrub.cancel()
        XCTAssertNil(scrub.finish(entryID: new, duration: 100))
        XCTAssertEqual(scrub.displayedPosition(elapsed: 3, duration: 100), 3)
    }

    func testDurationChangeClampsPendingSeekAtRelease() {
        let id = UUID()
        var scrub = PlaybackScrubState()
        scrub.begin(entryID: id, elapsed: 10, duration: 100)
        scrub.update(90, entryID: id, duration: 100)
        XCTAssertEqual(scrub.finish(entryID: id, duration: 60), 60)
    }
}
