import XCTest
@testable import Liquidmusic

@MainActor
final class AlbumArtworkTests: XCTestCase {
    func testFirstTrackWithoutArtworkDoesNotHideLaterCandidate() throws {
        let tracks = [track("first"), track("later", artwork: "/preview/later.jpg")]
        let result = try LibraryQueryIndex(tracks: tracks).result(for: LibraryQueryRequest())
        let album = try XCTUnwrap(result.albums.first)
        XCTAssertEqual(album.representative.id, "first")
        XCTAssertEqual(album.count, 2)
        XCTAssertEqual(album.artworkCandidates, [candidate("later", "/preview/later.jpg")])
        XCTAssertTrue(result.albumArtworkCandidates.isEmpty)
    }

    func testDiscTrackAndStableIDOrderIncludesUnknownAndLargestNumbers() throws {
        let tracks = [
            track("unknown-zero", artwork: "/zero", disc: 0, number: 0),
            track("disc2", artwork: "/disc2", disc: 2, number: 1),
            track("b", artwork: "/b", disc: 1, number: 1),
            track("a", artwork: "/a", disc: 1, number: 1),
            track("track2", artwork: "/track2", disc: 1, number: 2),
            track("track-max", artwork: "/track-max", disc: 1, number: .max),
            track("track-unknown", artwork: "/track-unknown", disc: 1, number: -1),
            track("disc-max", artwork: "/disc-max", disc: .max, number: 1),
            track("unknown-negative", artwork: "/negative", disc: -3, number: 0),
            track("unknown-numbered", artwork: "/numbered", disc: 0, number: 1)
        ]
        let expected = ["a", "b", "track2", "track-max", "track-unknown", "disc2", "disc-max",
                        "unknown-numbered", "unknown-negative", "unknown-zero"]
        // 使用固定排列，避免依赖随机洗牌导致结果难以复现。
        for input in [tracks, Array(tracks.reversed()), Array(tracks.dropFirst(3) + tracks.prefix(3))] {
            let selected = try AlbumArtworkSelector().candidates(for: AlbumIdentity(tracks[0]), tracks: input)
            XCTAssertEqual(selected.map(\.trackID), expected)
        }
    }

    func testBlankPathsAreIgnoredAndExactPathsDeduplicateAfterOrdering() throws {
        let spacedPath = " /preview/with spaces.jpg "
        let tracks = [track("nil"), track("empty", artwork: ""), track("blank", artwork: " \n\t"),
                      track("duplicate-late", artwork: "/preview/shared.jpg", number: 2),
                      track("duplicate-first", artwork: "/preview/shared.jpg", number: 1),
                      track("spaced", artwork: spacedPath, number: 3),
                      track("distinct", artwork: spacedPath.trimmingCharacters(in: .whitespaces), number: 4)]
        XCTAssertEqual(try AlbumArtworkSelector().candidates(for: AlbumIdentity(tracks[0]), tracks: tracks), [
            candidate("duplicate-first", "/preview/shared.jpg"), candidate("spaced", spacedPath),
            candidate("distinct", "/preview/with spaces.jpg")
        ])
        XCTAssertTrue(try AlbumArtworkSelector().candidates(for: AlbumIdentity(tracks[0]), tracks: []).isEmpty)
        XCTAssertTrue(try AlbumArtworkSelector().candidates(for: AlbumIdentity(tracks[0]), tracks: Array(tracks.prefix(3))).isEmpty)
    }

    func testSameTitleCompilationsCaseAndSeparatorCollisionsKeepExactIdentity() throws {
        let tracks = [
            track("solo", artwork: "/solo", albumArtist: "Solo"),
            track("guest-a", artwork: "/guest-a", number: 1, artist: "Guest A", albumArtist: "Various"),
            track("guest-b", artwork: "/guest-b", number: 2, artist: "Guest B", albumArtist: "Various"),
            track("case", artwork: "/case", albumArtist: "various"),
            track("separator1", artwork: "/separator1", album: "B\u{1F}C", albumArtist: "A"),
            track("separator2", artwork: "/separator2", album: "C", albumArtist: "A\u{1F}B")
        ]
        let selector = AlbumArtworkSelector()
        XCTAssertEqual(try selector.candidates(for: AlbumIdentity(tracks[1]), tracks: tracks).map(\.trackID),
                       ["guest-a", "guest-b"])
        let result = try LibraryQueryIndex(tracks: tracks).result(for: LibraryQueryRequest())
        XCTAssertEqual(result.albums.count, 5)
        for album in result.albums {
            let expectedIDs = Set(tracks.filter { AlbumIdentity($0) == album.id }.map(\.id))
            XCTAssertEqual(Set(album.artworkCandidates.map(\.trackID)), expectedIDs)
        }
    }

    func testSearchAndAllSortDirectionsRetainFullAlbumCandidatesAndVisibleOrder() throws {
        let tracks = [
            track("a", title: "Alpha Visible", duration: 20, number: 1, artist: "Z"),
            track("b", title: "Hidden", artwork: "/preview/hidden.jpg", number: 2, artist: "X"),
            track("c", title: "Zulu Visible", artwork: "/preview/late.jpg", duration: 10, number: 3, artist: "A"),
            track("o", title: "Middle Visible", duration: 30, artist: "M", album: "Other")
        ]
        let index = try LibraryQueryIndex(tracks: tracks)
        let identity = AlbumIdentity(tracks[0])
        let expected = [candidate("b", "/preview/hidden.jpg"), candidate("c", "/preview/late.jpg")]
        let orders: [TrackSortField: [String]] = [
            .title: ["a", "o", "c"], .artist: ["c", "o", "a"],
            .album: ["o", "a", "c"], .duration: ["c", "a", "o"]
        ]
        for field in TrackSortField.allCases {
            for direction in [SortOrder.forward, .reverse] {
                let sort = [TrackSort(field: field, order: direction)]
                let result = try index.result(for: LibraryQueryRequest(query: "Visible", sortOrder: sort))
                let ids = try XCTUnwrap(orders[field])
                // 专辑同值时原查询始终按标题升序破同值，不能随主字段一起反转。
                let reversedIDs = field == .album ? ["a", "c", "o"] : Array(ids.reversed())
                XCTAssertEqual(result.tracks.map(\.id), direction == .forward ? ids : reversedIDs)
                XCTAssertEqual(result.scopeCount, 4)
                let album = try XCTUnwrap(result.albums.first { $0.id == identity })
                XCTAssertEqual(album.count, 2)
                XCTAssertEqual(album.artworkCandidates, expected)
                XCTAssertEqual(album.representative.id, result.tracks.first { AlbumIdentity($0) == identity }?.id)
                XCTAssertTrue(result.albumArtworkCandidates.isEmpty)

                let detail = try index.result(for: LibraryQueryRequest(query: "Visible", scope: .album(identity), sortOrder: sort))
                XCTAssertEqual(detail.scopeCount, 3)
                XCTAssertEqual(detail.tracks.map(\.id), result.tracks.filter { AlbumIdentity($0) == identity }.map(\.id))
                XCTAssertEqual(detail.albumArtworkCandidates, expected)
            }
        }
        let artist = try index.result(for: LibraryQueryRequest(scope: .artist("Z")))
        XCTAssertEqual(artist.tracks.map(\.id), ["a"])
        XCTAssertEqual(artist.albums.first?.artworkCandidates, expected)
        XCTAssertTrue(artist.albumArtworkCandidates.isEmpty)
    }

    func testEmptyOrMissingAlbumScopeDoesNotPublishStaleCandidates() throws {
        let source = track("source", artwork: "/preview/source.jpg")
        let index = try LibraryQueryIndex(tracks: [source])
        let empty = try index.result(for: LibraryQueryRequest(query: "missing", scope: .album(AlbumIdentity(source))))
        XCTAssertEqual(empty.scopeCount, 1)
        XCTAssertTrue(empty.tracks.isEmpty)
        XCTAssertTrue(empty.albumArtworkCandidates.isEmpty)
        let missing = try index.result(for: LibraryQueryRequest(scope: .album(AlbumIdentity(track("missing", album: "Removed")))))
        XCTAssertEqual(missing.scopeCount, 0)
        XCTAssertTrue(missing.albumArtworkCandidates.isEmpty)
    }

    func testSourceReplacementRemovesCachedPathsAndPreviewUsesSameCandidates() async throws {
        var source = track("source", artwork: "/preview/old.jpg")
        let identity = AlbumIdentity(source)
        let preview = LibraryViewModel.preview(section: .albums, scope: .album(identity), tracks: [source])
        XCTAssertEqual(preview.result.albumArtworkCandidates, [candidate("source", "/preview/old.jpg")])
        let model = LibraryViewModel(section: .albums, scope: .album(identity))
        model.replaceTracks([source])
        try await waitUntilReady(model)
        XCTAssertEqual(model.result.albumArtworkCandidates, preview.result.albumArtworkCandidates)

        source.artworkPath = "/preview/new.jpg"
        model.replaceTracks([source])
        try await waitUntilReady(model)
        XCTAssertEqual(model.result.albumArtworkCandidates, [candidate("source", "/preview/new.jpg")])
        source.artworkPath = nil
        model.replaceTracks([source])
        try await waitUntilReady(model)
        XCTAssertTrue(model.result.albumArtworkCandidates.isEmpty)
        XCTAssertTrue(try XCTUnwrap(model.result.albums.first).artworkCandidates.isEmpty)
        model.replaceTracks([])
        try await waitUntilReady(model)
        XCTAssertTrue(model.result.albums.isEmpty)
        XCTAssertTrue(model.result.albumArtworkCandidates.isEmpty)
        XCTAssertFalse(preview.isQuerying)
        XCTAssertEqual(preview.result.albumArtworkCandidates, [candidate("source", "/preview/old.jpg")])
    }

    func testThousandTrackSnapshotKeepsEachAlbumsCandidatesAcrossSearches() throws {
        // 路径全部虚构，不读取图片或音频；每张专辑仅后九首有封面。
        let tracks = SPXData.largeLibrary.enumerated().map { index, value in
            var track = value
            track.title += "·"
            if index % 10 != 0 { track.artworkPath = "/preview/album-\(index / 10)-\(index % 10).jpg" }
            return track
        }
        let index = try LibraryQueryIndex(tracks: tracks)
        let all = try index.result(for: LibraryQueryRequest())
        XCTAssertEqual(all.tracks.count, 1_000)
        XCTAssertEqual(all.albums.count, 100)
        let expected = Dictionary(uniqueKeysWithValues: all.albums.map { ($0.id, $0.artworkCandidates) })
        XCTAssertTrue(all.albums.allSatisfy { $0.artworkCandidates.count == 9 })
        for (offset, source) in tracks.enumerated() where offset.isMultiple(of: 10) {
            let result = try index.result(for: LibraryQueryRequest(query: source.title, scope: .album(AlbumIdentity(source))))
            XCTAssertEqual(result.tracks.map(\.id), [source.id])
            XCTAssertEqual(result.albums.first?.count, 1)
            XCTAssertEqual(result.albumArtworkCandidates, expected[AlbumIdentity(source)])
            XCTAssertEqual(result.albums.first?.artworkCandidates, expected[AlbumIdentity(source)])
        }
    }

    func testCancelledSelectionAndIndexConstructionRejectEmptyAndNonemptyInput() async throws {
        let source = track("source", artwork: "/preview/source.jpg")
        let identity = AlbumIdentity(source)
        for tracks in [[], [source]] {
            await assertCancelled { _ = try AlbumArtworkSelector().candidates(for: identity, tracks: tracks) }
            await assertCancelled { _ = try LibraryQueryIndex(tracks: tracks) }
        }
        let index = try LibraryQueryIndex(tracks: [source])
        await assertCancelled { _ = try index.result(for: LibraryQueryRequest()) }
    }

    private func assertCancelled(_ work: @escaping @Sendable () throws -> Void,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        let cancelled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do { try work(); return false }
            catch is CancellationError { return true }
            catch { return false }
        }.value
        XCTAssertTrue(cancelled, "已取消的任务应抛出 CancellationError", file: file, line: line)
    }

    private func waitUntilReady(_ model: LibraryViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isQuerying && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isQuerying)
    }

    private func candidate(_ id: String, _ path: String) -> AlbumArtworkCandidate {
        AlbumArtworkCandidate(trackID: id, cachePath: path)
    }

    private func track(_ id: String, title: String? = nil, artwork: String? = nil, duration: Double = 120,
                       disc: Int = 1, number: Int = 0, artist: String = "Artist",
                       album: String = "Shared", albumArtist: String = "Album Artist") -> Track {
        Track(id: id, folderID: "preview", path: "/preview/\(id).m4a", title: title ?? id,
              artist: artist, album: album, albumArtist: albumArtist, duration: duration,
              discNumber: disc, trackNumber: number, artworkPath: artwork, modifiedAt: .distantPast)
    }
}
