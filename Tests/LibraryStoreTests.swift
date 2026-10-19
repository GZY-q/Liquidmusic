import XCTest
@testable import Liquidmusic

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testMigrationsAndRecordsSurviveReopeningDatabase() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("Database/Library.sqlite")
        let store = LibraryStore(location: .file(url))
        let folder = try await store.saveFolder(fixture.folder())
        let saved = try await store.upsertTracks([fixture.track(folderID: folder.id)])
        let issue = ImportIssue(folderID: folder.id, filePath: "/test/broken.flac", reason: "无法解码")
        try await store.recordIssue(issue)
        try await store.close()
        let reopened = LibraryStore(location: .file(url))
        let folders = try await reopened.folders()
        let tracks = try await reopened.tracks(folderID: folder.id)
        let issues = try await reopened.issues(folderID: folder.id)
        XCTAssertEqual(folders.map(\.id), [folder.id])
        XCTAssertEqual(folders.first?.bookmarkData, folder.bookmarkData)
        XCTAssertEqual(tracks.map(\.id), saved.map(\.id))
        XCTAssertEqual(tracks.first?.title, "初始标题")
        XCTAssertEqual(issues.map(\.reason), ["无法解码"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("Artwork").path))
        try await reopened.close()
    }

    func testRepeatedUpsertUsesCanonicalPathAndStableUUID() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let store = LibraryStore(location: .memory)
        let folder = try await store.saveFolder(fixture.folder())
        let first = try await store.upsertTracks([fixture.track(folderID: folder.id)])
        var changed = fixture.track(folderID: folder.id)
        changed.id = "另一个临时ID"
        changed.path = fixture.music.appendingPathComponent("unused/../song.wav").path
        changed.title = "更新标题"
        let second = try await store.upsertTracks([changed, changed])
        let all = try await store.tracks()
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(first.first?.id)))
        XCTAssertEqual(second.map(\.id), [first[0].id, first[0].id])
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "更新标题")
    }

    func testFolderDeduplicationAndReauthorizationPreserveIdentity() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let store = LibraryStore(location: .memory)
        var original = fixture.folder()
        original.lastScanAt = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try await store.saveFolder(original)
        var duplicate = fixture.folder()
        duplicate.bookmarkData = Data("新书签".utf8)
        let second = try await store.saveFolder(duplicate)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.lastScanAt, first.lastScanAt)
        XCTAssertEqual(second.bookmarkData, duplicate.bookmarkData)
        let count = try await store.folders().count
        XCTAssertEqual(count, 1)
    }

    func testFolderFilterAndPathConflictDoNotMergeDifferentFolders() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let store = LibraryStore(location: .memory)
        let first = try await store.saveFolder(fixture.folder())
        let otherURL = fixture.root.appendingPathComponent("OtherMusic")
        let second = try await store.saveFolder(LibraryFolder(path: otherURL.path, displayName: "其他音乐", bookmarkData: Data()))
        var otherTrack = fixture.track(folderID: second.id)
        otherTrack.path = otherURL.appendingPathComponent("song.wav").path
        _ = try await store.upsertTracks([fixture.track(folderID: first.id), otherTrack])
        let selected = try await store.tracks(folderID: second.id)
        XCTAssertEqual(selected.map(\.folderID), [second.id])
        var conflict = first
        conflict.path = second.path
        do { _ = try await store.saveFolder(conflict); XCTFail("不应覆盖其他文件夹身份") }
        catch { XCTAssertTrue(error is LibraryStoreError) }
        let retained = try await store.folders()
        XCTAssertEqual(retained.count, 2)
    }

    func testFailedBatchRollsBackAndInvalidDurationIsRejected() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let store = LibraryStore(location: .memory)
        let folder = try await store.saveFolder(fixture.folder())
        let valid = fixture.track(folderID: folder.id)
        var orphan = valid
        orphan.path = fixture.music.appendingPathComponent("orphan.wav").path
        orphan.folderID = "不存在的文件夹"
        do { _ = try await store.upsertTracks([valid, orphan]); XCTFail("必须拒绝没有所属文件夹的歌曲") }
        catch { }
        let afterFailure = try await store.tracks()
        XCTAssertTrue(afterFailure.isEmpty)
        for duration in [Double.nan, .infinity, 0, -1] {
            var invalid = valid
            invalid.duration = duration
            do { _ = try await store.upsertTracks([invalid]); XCTFail("必须拒绝无效时长") }
            catch { XCTAssertTrue(error is LibraryStoreError) }
        }
    }

    func testDatabaseFailureDoesNotFallBackToMemory() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let blocker = fixture.root.appendingPathComponent("NotADirectory")
        try Data("不是文件夹".utf8).write(to: blocker)
        let store = LibraryStore(location: .file(blocker.appendingPathComponent("Library.sqlite")))
        for _ in 0..<2 {
            do { try await store.open(); XCTFail("磁盘路径失败不能静默切换内存数据库") }
            catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }
}

// 测试只使用本用例创建的临时目录，不访问真实音乐库。
struct LibraryFixture {
    let root: URL
    let music: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        music = root.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
    }
    func folder() -> LibraryFolder {
        LibraryFolder(path: music.path, displayName: "Music", bookmarkData: Data(music.absoluteString.utf8))
    }
    func track(folderID: String) -> Track {
        Track(id: "导入前临时ID", folderID: folderID, path: music.appendingPathComponent("song.wav").path,
              title: "初始标题", artist: "艺术家", album: "专辑", albumArtist: "艺术家", duration: 120,
              modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
