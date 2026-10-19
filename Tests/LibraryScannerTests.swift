import XCTest
import ImageIO
@testable import Liquidmusic

@MainActor
final class LibraryScannerTests: XCTestCase {
    func testNativeMetadataReadsID3AndM4ATagsAndEmbeddedArtwork() async throws {
        for ext in ["mp3", "m4a"] {
            let url = try fixtureURL("tagged", ext: ext)
            let metadata = try await AudioFileReader().readMetadata(url)
            XCTAssertEqual(metadata.track.title, "Fixture Song")
            XCTAssertEqual(metadata.track.artist, "Fixture Artist")
            XCTAssertEqual(metadata.track.album, "Fixture Album")
            XCTAssertEqual(metadata.track.albumArtist, "Fixture Collection")
            XCTAssertEqual(metadata.track.trackNumber, 3)
            XCTAssertEqual(metadata.track.discNumber, 2)
            XCTAssertGreaterThan(metadata.track.duration, 0)
            if ext == "mp3" { XCTAssertNotNil(metadata.artworkData) }
        }
    }

    func testDiscoveryIndexesFormatsAndSkipsHiddenPackagesSymlinksAndBrokenAudio() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        _ = try fixture.audio("UPPER.WAV")
        _ = try fixture.audio("Nested/song.aiff", source: "tone", ext: "aiff")
        _ = try fixture.audio("tagged.mp3", source: "tagged", ext: "mp3")
        _ = try fixture.audio("song.m4a", source: "tagged", ext: "m4a")
        _ = try fixture.audio("song.flac", source: "tone", ext: "flac")
        _ = try fixture.audio(".hidden.wav")
        _ = try fixture.audio("Ignored.bundle/song.wav")
        try Data("不是音频".utf8).write(to: fixture.music.appendingPathComponent("broken.mp3"), options: .withoutOverwriting)
        try Data("说明".utf8).write(to: fixture.music.appendingPathComponent("readme.txt"), options: .withoutOverwriting)
        try FileManager.default.createSymbolicLink(at: fixture.music.appendingPathComponent("Loop"), withDestinationURL: fixture.music)
        let env = try await environment(fixture)
        let plan = try await env.scanner.prepare(folder: env.folder) { _ in }
        XCTAssertTrue(plan.enumerationComplete)
        XCTAssertEqual(plan.changes.count + plan.skipped, 6)
        XCTAssertTrue(plan.changes.contains { $0.path.hasSuffix("UPPER.WAV") })
        XCTAssertTrue(plan.changes.contains { $0.path.hasSuffix("song.aiff") })
        XCTAssertTrue(plan.changes.contains { $0.path.hasSuffix("tagged.mp3") })
        XCTAssertTrue(plan.changes.contains { $0.path.hasSuffix("song.m4a") })
        XCTAssertTrue(plan.issues.contains { $0.filePath.hasSuffix("broken.mp3") })
        // FLAC 是否接受由实际 AVFoundation 解码能力决定，失败必须进入报告。
        XCTAssertTrue(plan.changes.contains { $0.path.hasSuffix("song.flac") } || plan.issues.contains { $0.filePath.hasSuffix("song.flac") })
        try await env.scanner.commit(plan, confirmed: false)
        let tracks = try await env.store.tracks()
        XCTAssertEqual(tracks.count, plan.changes.count)
        XCTAssertNotNil(tracks.first { $0.path.hasSuffix("tagged.mp3") }?.artworkPath)
        let issues = try await env.store.issues(folderID: env.folder.id)
        XCTAssertEqual(issues.count, plan.issues.count)
        await env.access.shutdown()
    }

    func testSecondScanReusesUnchangedMetadataAndPreservesIDs() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        _ = try fixture.audio("song.wav")
        let reader = CountingMetadataReader()
        let env = try await environment(fixture, reader: reader)
        let first = try await env.scanner.prepare(folder: env.folder) { _ in }
        try await env.scanner.commit(first, confirmed: false)
        let original = try await env.store.tracks()
        let second = try await env.scanner.prepare(folder: env.folder) { _ in }
        XCTAssertEqual(second.reused, 1)
        XCTAssertTrue(second.changes.isEmpty)
        let count = await reader.count
        XCTAssertEqual(count, 1)
        try await env.scanner.commit(second, confirmed: false)
        let again = try await env.store.tracks()
        XCTAssertEqual(again.map(\.id), original.map(\.id))
        await env.access.shutdown()
    }

    func testUpdatesRequireConfirmationAndKeepStableID() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let url = try fixture.audio("song.wav")
        let env = try await environment(fixture)
        try await env.scanner.commit(env.scanner.prepare(folder: env.folder) { _ in }, confirmed: false)
        let initialTracks = try await env.store.tracks()
        let original = try XCTUnwrap(initialTracks.first)
        try FileManager.default.setAttributes([.modificationDate: original.modifiedAt.addingTimeInterval(5)], ofItemAtPath: url.path)
        let plan = try await env.scanner.prepare(folder: env.folder) { _ in }
        XCTAssertEqual(plan.updates.count, 1)
        do { try await env.scanner.commit(plan, confirmed: false); XCTFail("覆盖现有索引必须确认") }
        catch { XCTAssertTrue(error is LibraryScanError) }
        let beforeApproval = try await env.store.tracks()
        XCTAssertEqual(beforeApproval.first?.modifiedAt, original.modifiedAt)
        try await env.scanner.commit(plan, confirmed: true)
        let updated = try await env.store.tracks()
        XCTAssertEqual(updated.first?.id, original.id)
        XCTAssertGreaterThan(try XCTUnwrap(updated.first?.modifiedAt), original.modifiedAt)
        await env.access.shutdown()
    }

    func testMissingIndexIsOnlyRemovedAfterExplicitApproval() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let env = try await environment(fixture)
        let ghost = fixture.track("missing.wav", folderID: env.folder.id)
        _ = try await env.store.upsertTracks([ghost])
        let plan = try await env.scanner.prepare(folder: env.folder) { _ in }
        XCTAssertEqual(plan.missing.count, 1)
        do { try await env.scanner.commit(plan, confirmed: false); XCTFail("未确认不能清理") }
        catch { }
        let retained = try await env.store.tracks()
        XCTAssertEqual(retained.count, 1)
        try await env.scanner.commit(plan, confirmed: true)
        let removed = try await env.store.tracks()
        XCTAssertTrue(removed.isEmpty)
        await env.access.shutdown()
    }

    func testFileReappearingAfterReviewPlanInvalidatesCleanup() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let env = try await environment(fixture)
        _ = try await env.store.upsertTracks([fixture.track("missing.wav", folderID: env.folder.id)])
        let plan = try await env.scanner.prepare(folder: env.folder) { _ in }
        _ = try fixture.audio("missing.wav")
        do { try await env.scanner.commit(plan, confirmed: true); XCTFail("清单已过时，不能删除恢复的文件索引") }
        catch { XCTAssertTrue(error is LibraryScanError) }
        let retained = try await env.store.tracks()
        XCTAssertEqual(retained.count, 1)
        await env.access.shutdown()
    }

    func testIncompleteEnumerationNeverProposesMissingCleanup() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let blocked = fixture.music.appendingPathComponent("Blocked")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }
        let env = try await environment(fixture)
        _ = try await env.store.upsertTracks([fixture.track("old.wav", folderID: env.folder.id)])
        let plan = try await env.scanner.prepare(folder: env.folder) { _ in }
        XCTAssertFalse(plan.enumerationComplete)
        XCTAssertTrue(plan.missing.isEmpty)
        XCTAssertFalse(plan.issues.isEmpty)
        try await env.scanner.commit(plan, confirmed: false)
        let retained = try await env.store.tracks()
        XCTAssertEqual(retained.count, 1)
        await env.access.shutdown()
    }

    func testOverlappingFoldersUseMostSpecificOwnerWithoutDuplicates() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        _ = try fixture.audio("parent.wav")
        _ = try fixture.audio("Nested/child.wav")
        let env = try await environment(fixture)
        let grant = try await env.access.prepareSelection(fixture.music.appendingPathComponent("Nested"))
        let child = try await env.store.saveFolder(grant.folder)
        try await env.access.commit(grant, as: child.id)
        let parentPlan = try await env.scanner.prepare(folder: env.folder) { _ in }
        let childPlan = try await env.scanner.prepare(folder: child) { _ in }
        XCTAssertEqual(parentPlan.changes.count, 1)
        XCTAssertEqual(childPlan.changes.count, 1)
        try await env.scanner.commit(parentPlan, confirmed: false)
        try await env.scanner.commit(childPlan, confirmed: false)
        let all = try await env.store.tracks()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first { $0.path.hasSuffix("child.wav") }?.folderID, child.id)
        await env.access.shutdown()
    }

    func testStaleFileOrDatabaseStateRejectsPlanBeforeAnyWrites() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let url = try fixture.audio("song.wav")
        let env = try await environment(fixture)
        let plan = try await env.scanner.prepare(folder: env.folder) { _ in }
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(5)], ofItemAtPath: url.path)
        do { try await env.scanner.commit(plan, confirmed: false); XCTFail("文件变化后必须重新扫描") }
        catch { }
        let fresh = try await env.scanner.prepare(folder: env.folder) { _ in }
        var conflict = fixture.track("song.wav", folderID: env.folder.id)
        conflict.title = "并发写入"
        _ = try await env.store.upsertTracks([conflict])
        do { try await env.scanner.commit(fresh, confirmed: false); XCTFail("不能覆盖扫描后的并发写入") }
        catch { }
        let retained = try await env.store.tracks()
        XCTAssertEqual(retained.map(\.title), ["并发写入"])
        await env.access.shutdown()
    }

    func testArtworkIsDownsampledDeduplicatedAndInvalidArtworkDoesNotRejectAudio() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let image = try Data(contentsOf: fixtureURL("cover", ext: "jpg"))
        let cache = ArtworkCache(directory: fixture.root.appendingPathComponent("Artwork"))
        let stored = try await cache.store(image)
        let first = try XCTUnwrap(stored)
        let second = try await cache.store(image)
        XCTAssertEqual(first, second)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: first) as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), 512)
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int), 512)
        _ = try fixture.audio("song.wav")
        let env = try await environment(fixture, reader: BadArtworkReader())
        let plan = try await env.scanner.prepare(folder: env.folder) { _ in }
        XCTAssertEqual(plan.changes.count, 1)
        XCTAssertEqual(plan.skipped, 0)
        XCTAssertNil(plan.changes.first?.artworkPath)
        XCTAssertFalse(plan.issues.isEmpty)
        await env.access.shutdown()
    }

    func testControllerRefreshesTracksAndRestoresIndexWithoutRescanning() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        _ = try fixture.audio("song.wav")
        let store = LibraryStore(location: .file(fixture.root.appendingPathComponent("Database/Library.sqlite")))
        let access = FolderAccessController(client: ScanBookmarkClient())
        let controller = LibraryController(store: store, access: access)
        await controller.load()
        await controller.addFolder(fixture.music)
        controller.startScan()
        try await eventually { !controller.isScanning }
        XCTAssertEqual(controller.tracks.count, 1)
        let app = AppModel(playback: PlaybackController(connectSystemMedia: false), library: controller)
        XCTAssertEqual(app.tracks.count, 1)
        await controller.shutdown().value
        try await store.close()
        let restored = LibraryController(store: LibraryStore(location: .file(fixture.root.appendingPathComponent("Database/Library.sqlite"))),
                                         access: FolderAccessController(client: ScanBookmarkClient()))
        await restored.load()
        XCTAssertEqual(restored.tracks.count, 1)
        XCTAssertNil(restored.scanProgress)
        await restored.shutdown().value
    }

    func testControllerCancellationIgnoresLateReaderResultAndPreservesOldIndex() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let url = try fixture.audio("song.wav")
        let metadata = try await AudioFileReader().readMetadata(url)
        let gate = BlockingMetadataReader()
        let env = try await environment(fixture, reader: gate)
        _ = try await env.store.upsertTracks([fixture.track("song.wav", folderID: env.folder.id)])
        let controller = LibraryController(store: env.store, access: env.access, scanner: env.scanner)
        await controller.load()
        controller.startScan()
        try await eventually { await gate.started }
        controller.cancelScan()
        await gate.finish(metadata)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(controller.isScanning)
        XCTAssertEqual(controller.scanProgress?.phase, .cancelled)
        XCTAssertNil(controller.pendingReview)
        let retained = try await env.store.tracks()
        XCTAssertEqual(retained.map(\.title), ["原索引"])
        await controller.shutdown().value
    }

    func testControllerWaitsForApprovalAndCancellationPreservesExistingIndex() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let env = try await environment(fixture)
        _ = try await env.store.upsertTracks([fixture.track("missing.wav", folderID: env.folder.id)])
        let controller = LibraryController(store: env.store, access: env.access, scanner: env.scanner)
        await controller.load()
        controller.startScan()
        try await eventually { controller.pendingReview != nil }
        XCTAssertEqual(controller.tracks.count, 1)
        controller.cancelScan()
        let afterCancel = try await env.store.tracks()
        XCTAssertEqual(afterCancel.count, 1)
        controller.startScan()
        try await eventually { controller.pendingReview != nil }
        controller.applyReviewedChanges()
        try await eventually { !controller.isScanning }
        XCTAssertTrue(controller.tracks.isEmpty)
        XCTAssertEqual(controller.scanReports.first?.removed, 1)
        await controller.shutdown().value
    }

    func testNewFolderSelectionAutomaticallyIndexesInProductionConfiguration() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        _ = try fixture.audio("song.wav")
        let controller = LibraryController(store: LibraryStore(location: .memory),
                                           access: FolderAccessController(client: ScanBookmarkClient()),
                                           automaticallyScanNewFolders: true)
        await controller.load()
        await controller.addFolder(fixture.music)
        try await eventually { controller.tracks.count == 1 && !controller.isScanning }
        XCTAssertEqual(controller.scanProgress?.phase, .finished)
        await controller.shutdown().value
    }

    func testUnavailableRootCannotPrepareCleanup() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let env = try await environment(fixture)
        _ = try await env.store.upsertTracks([fixture.track("old.wav", folderID: env.folder.id)])
        await env.access.shutdown()
        do { _ = try await env.scanner.prepare(folder: env.folder) { _ in }; XCTFail("失去授权后不能扫描或清理") }
        catch { XCTAssertTrue(error is LibraryScanError) }
        let retained = try await env.store.tracks()
        XCTAssertEqual(retained.count, 1)
    }

    func testV1DatabaseMigrationAddsFingerprintWithoutLosingExistingRecords() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("Library.sqlite")
        try Data(contentsOf: fixtureURL("v1", ext: "sqlite")).write(to: url, options: .withoutOverwriting)
        let store = LibraryStore(location: .file(url))
        let existing = try await store.tracks()
        XCTAssertEqual(existing.first?.id, "stable-existing-id")
        XCTAssertEqual(existing.first?.title, "Legacy Song")
        XCTAssertNil(existing.first?.fileSize)
        var changed = try XCTUnwrap(existing.first)
        changed.fileSize = 1024
        let updated = try await store.upsertTracks([changed])
        XCTAssertEqual(updated.first?.id, "stable-existing-id")
        try await store.close()
        let reopened = LibraryStore(location: .file(url))
        let retained = try await reopened.tracks()
        XCTAssertEqual(retained.first?.fileSize, 1024)
        try await reopened.close()
    }

    private func environment(_ fixture: ScanFixture, reader: any AudioMetadataReading = AudioFileReader()) async throws -> ScanEnvironment {
        let store = LibraryStore(location: .memory)
        let access = FolderAccessController(client: ScanBookmarkClient())
        let grant = try await access.prepareSelection(fixture.music)
        let folder = try await store.saveFolder(grant.folder)
        try await access.commit(grant, as: folder.id)
        let scanner = LibraryScanner(store: store, access: access, reader: reader,
                                     artworkCache: ArtworkCache(directory: fixture.root.appendingPathComponent("Artwork")))
        return ScanEnvironment(store: store, access: access, scanner: scanner, folder: folder)
    }

    private func eventually(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            if ContinuousClock.now >= deadline { XCTFail("等待扫描状态超时"); throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private struct ScanEnvironment {
    let store: LibraryStore
    let access: FolderAccessController
    let scanner: LibraryScanner
    let folder: LibraryFolder
}

private actor CountingMetadataReader: AudioMetadataReading {
    private(set) var count = 0
    func readMetadata(_ url: URL) async throws -> AudioMetadata { count += 1; return try await AudioFileReader().readMetadata(url) }
}

private actor BadArtworkReader: AudioMetadataReading {
    func readMetadata(_ url: URL) async throws -> AudioMetadata {
        var result = try await AudioFileReader().readMetadata(url)
        result.artworkData = Data("不是图片".utf8)
        return result
    }
}

private actor BlockingMetadataReader: AudioMetadataReading {
    private(set) var started = false
    private var continuation: CheckedContinuation<AudioMetadata, Never>?
    func readMetadata(_ url: URL) async throws -> AudioMetadata {
        await withCheckedContinuation { continuation = $0; started = true }
    }
    func finish(_ metadata: AudioMetadata) { continuation?.resume(returning: metadata); continuation = nil }
}

private struct ScanBookmarkClient: FolderBookmarkClient {
    func create(for url: URL) throws -> Data { Data(url.absoluteString.utf8) }
    func resolve(_ data: Data) throws -> ResolvedFolderBookmark {
        guard let url = URL(string: String(decoding: data, as: UTF8.self)) else { throw CocoaError(.fileReadUnknown) }
        return ResolvedFolderBookmark(url: url, isStale: false)
    }
    func startAccessing(_ url: URL) -> Bool { false }
    func stopAccessing(_ url: URL) { }
}

private func fixtureURL(_ name: String, ext: String) throws -> URL {
    let bundle = Bundle(for: LibraryScannerTests.self)
    return try XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
        ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
}

private struct ScanFixture {
    let root: URL
    let music: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        music = root.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
    }
    func audio(_ path: String, source: String = "tone", ext: String = "wav") throws -> URL {
        let target = music.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: fixtureURL(source, ext: ext)).write(to: target, options: .withoutOverwriting)
        return target
    }
    func track(_ path: String, folderID: String) -> Track {
        Track(id: UUID().uuidString, folderID: folderID, path: LibraryStore.canonicalPath(music.appendingPathComponent(path).path),
              title: "原索引", artist: "未知艺术家", album: "未知专辑", albumArtist: "未知艺术家", duration: 0.4)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
