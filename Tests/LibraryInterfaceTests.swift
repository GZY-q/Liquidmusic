import XCTest
@testable import Liquidmusic

@MainActor
final class LibraryInterfaceTests: XCTestCase {
    func testSmartListsRankFilterAndKeepAlbumOrder() throws {
        let tracks = SPXData.tracks
        let first = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        let activity = [
            tracks[0].path: ListeningActivity(path: tracks[0].path, addedAt: first, lastPlayedAt: later, playCount: 1),
            tracks[2].path: ListeningActivity(path: tracks[2].path, addedAt: later, lastPlayedAt: first, playCount: 3)
        ]
        let index = try LibraryQueryIndex(tracks: tracks)
        let recent = try index.result(for: LibraryQueryRequest(section: .recentlyPlayed, activity: activity))
        XCTAssertEqual(recent.tracks.map(\.id), [tracks[0].id, tracks[2].id])
        XCTAssertEqual(recent.albums.map(\.id), [AlbumIdentity(tracks[0]), AlbumIdentity(tracks[2])])
        let frequent = try index.result(for: LibraryQueryRequest(section: .mostPlayed, activity: activity))
        XCTAssertEqual(frequent.tracks.map(\.id), [tracks[2].id, tracks[0].id])
        let added = try index.result(for: LibraryQueryRequest(section: .recentlyAdded, activity: activity))
        XCTAssertEqual(added.tracks.prefix(2).map(\.id), [tracks[2].id, tracks[0].id])
        let filtered = try index.result(for: LibraryQueryRequest(query: tracks[0].artist, section: .mostPlayed, activity: activity))
        XCTAssertEqual(filtered.tracks.map(\.id), [tracks[0].id])
        XCTAssertEqual(filtered.scopeCount, 2)
        XCTAssertTrue(try index.result(for: LibraryQueryRequest(section: .mostPlayed)).tracks.isEmpty)
    }

    func testActivityPersistsWithoutChangingTracksAndRetainsFirstAddedDate() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("activity.sqlite")
        let store = LibraryStore(location: .file(url))
        let folder = try await store.saveFolder(fixture.folder())
        let tracks = try await store.upsertTracks([fixture.track(folderID: folder.id)])
        let path = tracks[0].path
        let first = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        _ = try await store.listeningActivity(paths: [path], at: first)
        _ = try await store.listeningActivity(paths: [path], playedPath: path, at: later)
        let activity = try await store.listeningActivity(paths: [path], playedPath: path, at: later)
        XCTAssertEqual(activity[path]?.addedAt, first)
        XCTAssertEqual(activity[path]?.lastPlayedAt, later)
        XCTAssertEqual(activity[path]?.playCount, 2)
        let after = try await store.tracks()
        XCTAssertEqual(after, tracks)
        try await store.close()
        let reopened = LibraryStore(location: .file(url))
        let restored = try await reopened.listeningActivity(paths: [path])
        XCTAssertEqual(restored, activity)
        try await reopened.close()
    }

    func testOldDatabaseMigrationPreservesTracksAndPreferences() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let bundle = Bundle(for: LibraryInterfaceTests.self)
        let source = try XCTUnwrap(bundle.url(forResource: "v1", withExtension: "sqlite")
                                  ?? bundle.url(forResource: "v1", withExtension: "sqlite", subdirectory: "Fixtures"))
        let url = fixture.root.appendingPathComponent("legacy.sqlite")
        try FileManager.default.copyItem(at: source, to: url)
        let store = LibraryStore(location: .file(url))
        let tracks = try await store.tracks()
        XCTAssertFalse(tracks.isEmpty)
        let records = try await store.listeningActivity(paths: tracks.map(\.path))
        XCTAssertEqual(records.count, tracks.count)
        XCTAssertTrue(records.values.allSatisfy { $0.playCount == 0 && $0.lastPlayedAt == nil })
        let preferences = try await store.preferences()
        XCTAssertEqual(preferences, AppPreferences())
        let after = try await store.tracks()
        XCTAssertEqual(after, tracks)
        try await store.close()
    }

    func testConcurrentRecordRequestsDoNotLoseCounts() async throws {
        let activity = ListeningActivityController(store: LibraryStore(location: .memory))
        let tracks = SPXData.tracks
        let initial = activity.synchronize(tracks)
        let first = activity.recordPlayback(tracks[0])
        let second = activity.recordPlayback(tracks[0])
        let last = activity.recordPlayback(tracks[1])
        await initial.value
        await first.value
        await second.value
        await last.value
        XCTAssertNil(activity.error)
        XCTAssertEqual(activity.records[tracks[0].path]?.playCount, 2)
        XCTAssertEqual(activity.records[tracks[1].path]?.playCount, 1)
        XCTAssertEqual(activity.records.count, tracks.count)
    }

    func testNavigationBackForwardAndBranchingRetainDisplayMode() async throws {
        let model = LibraryViewModel.preview(section: .albums)
        let album = try XCTUnwrap(model.result.albums.first)
        model.displayMode = .list
        model.openAlbum(album)
        model.goBack()
        XCTAssertNil(model.scope)
        XCTAssertEqual(model.displayMode, .list)
        XCTAssertTrue(model.canGoForward)
        model.goForward()
        XCTAssertEqual(model.scope, .album(album.id))
        model.section = .recentlyPlayed
        XCTAssertNil(model.scope)
        model.goBack()
        XCTAssertEqual(model.scope, .album(album.id))
        model.section = .artists
        XCTAssertFalse(model.canGoForward)
        XCTAssertEqual(model.title, "艺术家")
    }

    func testLatestActivityRefreshWinsDuringNavigation() async throws {
        let model = LibraryViewModel(section: .recentlyPlayed)
        model.replaceTracks(SPXData.tracks)
        let track = SPXData.tracks[0]
        model.replaceActivity([track.path: ListeningActivity(path: track.path, addedAt: .now, lastPlayedAt: .now, playCount: 1)])
        model.section = .mostPlayed
        try await eventually { !model.isQuerying }
        XCTAssertEqual(model.result.tracks.map(\.id), [track.id])
        model.replaceTracks([SPXData.tracks[1]])
        try await eventually { !model.isQuerying }
        XCTAssertTrue(model.result.tracks.isEmpty)
    }

    func testPlaybackCountsOnlyStartedLoadsAndNotPauseSeekOrFailure() async throws {
        let fixture = try AudioFixture(duration: 8)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        var started: [String] = []
        playback.onPlaybackStarted = { started.append($0.id) }
        playback.play(fixture.track, in: [fixture.track])
        try await eventually { started.count == 1 }
        playback.pause()
        playback.seek(to: 1)
        playback.resume()
        try await eventually { playback.isPlaying }
        XCTAssertEqual(started.count, 1)
        playback.play(fixture.track, in: [fixture.track])
        try await eventually { started.count == 2 }
        var missing = fixture.track
        missing.path = fixture.directory.appendingPathComponent("missing.wav").path
        playback.play(missing, in: [missing])
        XCTAssertEqual(playback.status, .failed)
        XCTAssertEqual(started.count, 2)
    }

    func testCrossfadePublishesOneStartedEventPerTrack() async throws {
        let first = try AudioFixture(duration: 2)
        let second = try AudioFixture(duration: 3)
        defer { first.remove(); second.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        playback.configureCrossfade(enabled: true, duration: 1)
        defer { playback.shutdown() }
        var started: [String] = []
        playback.onPlaybackStarted = { started.append($0.id) }
        playback.play(first.track, in: [first.track, second.track])
        try await eventually { started.count == 2 }
        playback.pause()
        XCTAssertEqual(started, [first.track.id, second.track.id])
    }

    private func eventually(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        while !condition() {
            if ContinuousClock.now >= deadline { XCTFail("等待状态超时"); throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
