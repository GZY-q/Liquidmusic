import XCTest
@testable import Liquidmusic

@MainActor
final class LibraryQueryTests: XCTestCase {
    func testThousandTrackIndexQueriesAndPreviewUseCompleteSyntheticSnapshot() throws {
        let clock = ContinuousClock()
        let start = clock.now
        let index = try LibraryQueryIndex(tracks: SPXData.largeLibrary)
        let built = clock.now
        let all = try index.result(for: LibraryQueryRequest())
        XCTAssertEqual(all.tracks.count, 1_000)
        XCTAssertEqual(all.albums.count, 100)
        XCTAssertEqual(all.artists.count, 10)
        for field in TrackSortField.allCases {
            let request = LibraryQueryRequest(scope: .artist("艺术家 3"), sortOrder: [TrackSort(field: field)])
            let result = try index.result(for: request)
            XCTAssertEqual(result.tracks.count, 100)
            XCTAssertEqual(result.albums.count, 10)
            XCTAssertTrue(result.tracks.allSatisfy { $0.artist == "艺术家 3" })
        }
        let search = try index.result(for: LibraryQueryRequest(query: "模拟歌曲 1000"))
        XCTAssertEqual(search.tracks.map(\.id), ["scale-999"])
        let queried = clock.now
        let preview = LibraryViewModel.preview(tracks: SPXData.largeLibrary)
        XCTAssertEqual(preview.result.tracks.count, 1_000)
        XCTAssertFalse(preview.isQuerying)
        // 记录规模数据，不用受机器负载影响的严格毫秒阈值制造偶发失败。
        print("M7_SCALE index1000=\(start.duration(to: built)) sixQueries=\(built.duration(to: queried))")
    }

    func testSearchMatchesTitleArtistAlbumAndChineseWithCaseAndDiacriticFolding() throws {
        let tracks = [
            track("1", title: "Café at Dawn"),
            track("2", title: "Second", artist: "Beyoncé"),
            track("3", title: "Third", album: "Été"),
            track("4", title: "夜航", artist: "林间来信", album: "蓝色时刻")
        ]
        let index = try LibraryQueryIndex(tracks: tracks)
        for (query, ids) in [(" CAFE ", ["1"]), ("BEYONCE", ["2"]), ("ete", ["3"]),
                             ("夜", ["4"]), ("来信", ["4"]), ("蓝色", ["4"]), ("不存在", [])] {
            XCTAssertEqual(try index.result(for: LibraryQueryRequest(query: query)).tracks.map(\.id), ids)
        }
        XCTAssertEqual(try index.result(for: LibraryQueryRequest(query: " \n")).tracks.count, 4)
    }

    func testFourSortFieldsAndNumericDurationInBothDirections() throws {
        let tracks = [
            track("a", title: "Track 10", artist: "C", album: "B", duration: 9),
            track("b", title: "Track 2", artist: "A", album: "C", duration: 600),
            track("c", title: "Track 1", artist: "B", album: "A", duration: 65)
        ]
        let expected: [TrackSortField: [String]] = [
            .title: ["c", "b", "a"], .artist: ["b", "c", "a"],
            .album: ["c", "a", "b"], .duration: ["a", "c", "b"]
        ]
        let index = try LibraryQueryIndex(tracks: tracks)
        for field in TrackSortField.allCases {
            for order in [SortOrder.forward, .reverse] {
                let result = try index.result(for: LibraryQueryRequest(sortOrder: [TrackSort(field: field, order: order)]))
                let ids = try XCTUnwrap(expected[field])
                XCTAssertEqual(result.tracks.map(\.id), order == .forward ? ids : ids.reversed())
            }
        }
    }

    func testSortTiesAreStableAndMultipleComparatorsAreRespected() throws {
        let tracks = [track("c", title: "Same", artist: "A", duration: 10),
                      track("a", title: "Same", artist: "A", duration: 10),
                      track("b", title: "Same", artist: "B", duration: 10)]
        let request = LibraryQueryRequest(sortOrder: [TrackSort(field: .duration), TrackSort(field: .artist, order: .reverse)])
        for input in [tracks, Array(tracks.reversed()), [tracks[1], tracks[2], tracks[0]]] {
            XCTAssertEqual(try LibraryQueryIndex(tracks: input).result(for: request).tracks.map(\.id), ["b", "a", "c"])
        }
    }

    func testAlbumGroupingSeparatesSameTitleAndKeepsCompilationTogether() throws {
        let tracks = [track("1", artist: "Solo A", album: "Same", albumArtist: "Solo A"),
                      track("2", artist: "Solo B", album: "Same", albumArtist: "Solo B"),
                      track("3", artist: "Guest A", album: "Collection", albumArtist: "Various"),
                      track("4", artist: "Guest B", album: "Collection", albumArtist: "Various")]
        let index = try LibraryQueryIndex(tracks: tracks)
        let result = try index.result(for: LibraryQueryRequest())
        XCTAssertEqual(result.albums.count, 3)
        XCTAssertEqual(result.albums.first { $0.id.title == "Collection" }?.count, 2)
        let scope = LibraryScope.album(AlbumIdentity(tracks[1]))
        XCTAssertEqual(try index.result(for: LibraryQueryRequest(scope: scope)).tracks.map(\.id), ["2"])
        XCTAssertEqual(result.artists.map(\.id), ["Guest A", "Guest B", "Solo A", "Solo B"])
        XCTAssertFalse(result.artists.contains { $0.id == "Various" })
    }

    func testAlbumIdentityDoesNotCollideWhenLabelsContainSeparator() throws {
        let first = track("1", album: "B\u{1F}C", albumArtist: "A")
        let second = track("2", album: "C", albumArtist: "A\u{1F}B")
        XCTAssertEqual(first.albumKey, second.albumKey)
        let result = try LibraryQueryIndex(tracks: [first, second]).result(for: LibraryQueryRequest())
        XCTAssertEqual(result.albums.count, 2)
    }

    func testScopeSearchAndSortCombineWithoutLeakingOtherArtists() throws {
        let tracks = [track("1", title: "Keep Long", artist: "A", duration: 600),
                      track("2", title: "Keep Short", artist: "A", duration: 9),
                      track("3", title: "Other", artist: "A"),
                      track("4", title: "Keep", artist: "B")]
        let index = try LibraryQueryIndex(tracks: tracks)
        var request = LibraryQueryRequest(query: "keep", scope: .artist("A"), sortOrder: [TrackSort(field: .duration)])
        let result = try index.result(for: request)
        XCTAssertEqual(result.scopeCount, 3)
        XCTAssertEqual(result.tracks.map(\.id), ["2", "1"])
        request.query = ""
        XCTAssertEqual(try index.result(for: request).tracks.count, 3)
    }

    func testRapidSearchSortAndSourceReplacementOnlyPublishLatestRequest() async throws {
        let model = LibraryViewModel()
        model.replaceTracks((0..<1_000).map { track("\($0)", title: "Old \($0)") })
        model.query = "Old"
        model.sortOrder = [TrackSort(field: .duration, order: .reverse)]
        model.replaceTracks([track("new", title: "Latest", duration: 12)])
        model.query = "missing"
        model.query = "LATEST"
        try await waitUntilReady(model)
        XCTAssertEqual(model.result.tracks.map(\.id), ["new"])
        XCTAssertEqual(model.trackCount, 1)
        model.query = "Old"
        try await waitUntilReady(model)
        XCTAssertTrue(model.result.tracks.isEmpty)
        model.query = ""
        try await waitUntilReady(model)
        XCTAssertEqual(model.result.tracks.map(\.id), ["new"])
    }

    func testPreviewSnapshotsStayStableWithoutSchedulingInitialEmptyQueries() async throws {
        let models = LibrarySection.allCases.map { LibraryViewModel.preview(section: $0) }
        let detail = LibraryViewModel.preview(section: .albums, scope: .album(AlbumIdentity(SPXData.tracks[0])))
        try await Task.sleep(for: .milliseconds(50))
        for model in models {
            XCTAssertFalse(model.isQuerying)
            XCTAssertEqual(model.result.tracks.count, model.section?.isSmart == true ? 0 : SPXData.tracks.count)
        }
        XCTAssertEqual(detail.result.tracks.count, 2)
        XCTAssertFalse(detail.isQuerying)
    }

    func testNavigationReturnsToGroupingAndChangingSectionClearsScope() async throws {
        let model = LibraryViewModel(section: .albums)
        model.replaceTracks(SPXData.tracks)
        try await waitUntilReady(model)
        let album = try XCTUnwrap(model.result.albums.first)
        model.openAlbum(album)
        try await waitUntilReady(model)
        XCTAssertTrue(model.showsSongs)
        XCTAssertEqual(model.title, album.id.title)
        XCTAssertTrue(model.result.tracks.allSatisfy { AlbumIdentity($0) == album.id })
        model.goBack()
        try await waitUntilReady(model)
        XCTAssertNil(model.scope)
        XCTAssertEqual(model.section, .albums)
        XCTAssertFalse(model.showsSongs)
        model.section = .artists
        try await waitUntilReady(model)
        let artist = try XCTUnwrap(model.result.artists.first)
        model.openArtist(artist)
        try await waitUntilReady(model)
        XCTAssertTrue(model.result.tracks.allSatisfy { $0.artist == artist.id })
        model.query = artist.id
        model.section = .allMusic
        try await waitUntilReady(model)
        XCTAssertNil(model.scope)
        XCTAssertEqual(model.query, artist.id)
        XCTAssertNotEqual(LibrarySection.songs.id, LibrarySection.allMusic.id)
    }

    func testPlayUsesVisibleFilteredSortedSnapshotAndIgnoresStaleSelection() async throws {
        let model = LibraryViewModel()
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        var tracks = [track("long", title: "Keep", duration: 600), track("excluded", title: "Other"),
                      track("short", title: "Keep", duration: 9), track("middle", title: "Keep", duration: 65)]
        let path = try audioURL().path
        for index in tracks.indices { tracks[index].path = path }
        model.replaceTracks(tracks)
        model.query = "Keep"
        model.sortOrder = [TrackSort(field: .duration)]
        try await waitUntilReady(model)
        model.play(["middle"], using: playback)
        XCTAssertEqual(playback.queue.entries.map(\.track.id), ["short", "middle", "long"])
        XCTAssertEqual(playback.currentTrack?.id, "middle")
        let entryIDs = playback.queue.entries.map(\.id)
        model.play(["excluded"], using: playback)
        XCTAssertEqual(playback.queue.entries.map(\.id), entryIDs)
        model.query = ""
        try await waitUntilReady(model)
        XCTAssertEqual(model.result.tracks.count, 4)
    }

    func testMultiSelectionPlayNextRetainsVisibleOrderForEmptyAndExistingQueues() async throws {
        let model = LibraryViewModel()
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        var tracks = [track("a", title: "A"), track("b", title: "B"), track("c", title: "C")]
        let path = try audioURL().path
        for index in tracks.indices { tracks[index].path = path }
        model.replaceTracks(tracks)
        try await waitUntilReady(model)
        model.playNext(["a", "b", "c"], using: playback)
        XCTAssertEqual(playback.queue.entries.map(\.track.id), ["a", "b", "c"])
        XCTAssertEqual(playback.currentTrack?.id, "a")
        model.playNext(["b", "c"], using: playback)
        XCTAssertEqual(playback.queue.entries.map(\.track.id), ["a", "b", "c", "b", "c"])
    }

    private func track(_ id: String, title: String = "Song", artist: String = "Artist", album: String = "Album",
                       albumArtist: String? = nil, duration: Double = 60) -> Track {
        Track(id: id, folderID: "test", path: "/test/\(id).wav", title: title, artist: artist,
              album: album, albumArtist: albumArtist ?? artist, duration: duration, modifiedAt: .distantPast)
    }

    private func waitUntilReady(_ model: LibraryViewModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isQuerying {
            if ContinuousClock.now >= deadline { XCTFail("等待资料库查询超时"); throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func audioURL() throws -> URL {
        let bundle = Bundle(for: LibraryQueryTests.self)
        return try XCTUnwrap(bundle.url(forResource: "tone", withExtension: "wav")
                             ?? bundle.url(forResource: "tone", withExtension: "wav", subdirectory: "Fixtures"))
    }
}
