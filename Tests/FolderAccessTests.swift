import XCTest
@testable import Liquidmusic

@MainActor
final class FolderAccessTests: XCTestCase {
    func testAddDuplicateFolderBalancesAccessAndPersistsOneRecord() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let client = BookmarkStub()
        let store = LibraryStore(location: .memory)
        let access = FolderAccessController(client: client)
        let model = LibraryController(store: store, access: access)
        await model.load()
        await model.addFolder(fixture.music)
        let firstID = try XCTUnwrap(model.folders.first?.id)
        await model.addFolder(fixture.music)
        XCTAssertEqual(model.folders.map(\.id), [firstID])
        let records = try await store.folders()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(client.counts.started, 2)
        XCTAssertEqual(client.counts.stopped, 1)
        let activeURL = await access.url(for: firstID)
        XCTAssertEqual(activeURL, fixture.music)
        await model.shutdown().value
        XCTAssertEqual(client.counts.stopped, 2)
    }

    func testRestoreInNewControllerRefreshesStaleBookmark() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let client = BookmarkStub()
        let databaseURL = fixture.root.appendingPathComponent("Database/Library.sqlite")
        let store = LibraryStore(location: .file(databaseURL))
        let originalModel = LibraryController(store: store, access: FolderAccessController(client: client))
        await originalModel.load()
        await originalModel.addFolder(fixture.music)
        let oldBookmark = try XCTUnwrap(originalModel.folders.first?.folder.bookmarkData)
        await originalModel.shutdown().value
        try await store.close()
        client.setStale(true)
        let reopened = LibraryStore(location: .file(databaseURL))
        let access = FolderAccessController(client: client)
        let restored = LibraryController(store: reopened, access: access)
        await restored.load()
        XCTAssertEqual(restored.state, .ready)
        XCTAssertEqual(restored.folders.first?.status, .available)
        let records = try await reopened.folders()
        XCTAssertNotEqual(records.first?.bookmarkData, oldBookmark)
        let active = await access.url(for: try XCTUnwrap(records.first?.id))
        XCTAssertNotNil(active)
        await restored.shutdown().value
        try await reopened.close()
        XCTAssertEqual(client.counts.started, client.counts.stopped)
    }

    func testInvalidBookmarkRemainsVisibleAndCanBeReauthorized() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let client = BookmarkStub()
        let store = LibraryStore(location: .memory)
        let original = try await store.saveFolder(fixture.folder())
        client.setResolveFailure(true)
        let model = LibraryController(store: store, access: FolderAccessController(client: client))
        await model.load()
        XCTAssertEqual(model.state, .ready)
        XCTAssertFalse(try XCTUnwrap(model.folders.first).status.isAvailable)
        client.setResolveFailure(false)
        await model.addFolder(fixture.music, replacing: original)
        XCTAssertEqual(model.folders.map(\.id), [original.id])
        XCTAssertEqual(model.folders.first?.status, .available)
        XCTAssertNil(model.operationError)
        await model.shutdown().value
    }

    func testMissingDirectoryAndBookmarkCreationFailureDoNotLoseRecordsOrLeakScopes() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let client = BookmarkStub()
        let access = FolderAccessController(client: client)
        do { _ = try await access.prepareSelection(fixture.root.appendingPathComponent("Missing")); XCTFail("不存在目录不能授权") }
        catch { }
        XCTAssertEqual(client.counts.started, client.counts.stopped)
        client.setCreateFailure(true)
        do { _ = try await access.prepareSelection(fixture.music); XCTFail("创建书签失败必须报告") }
        catch { }
        XCTAssertEqual(client.counts.started, client.counts.stopped)
        await access.shutdown()
    }

    func testStartReturningFalseDoesNotCauseUnbalancedStop() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let client = BookmarkStub()
        client.setStartResult(false)
        let access = FolderAccessController(client: client)
        let authorization = try await access.prepareSelection(fixture.music)
        try await access.commit(authorization, as: authorization.folder.id)
        await access.shutdown()
        XCTAssertEqual(client.counts.started, 1)
        XCTAssertEqual(client.counts.stopped, 0)
    }

    func testFailedSaveDiscardsPendingAccessAndPreservesExistingAuthorization() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let other = fixture.root.appendingPathComponent("OtherMusic")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let client = BookmarkStub()
        let store = LibraryStore(location: .memory)
        let access = FolderAccessController(client: client)
        let model = LibraryController(store: store, access: access)
        await model.load()
        await model.addFolder(fixture.music)
        await model.addFolder(other)
        let original = try XCTUnwrap(model.folders.first { $0.folder.path == LibraryStore.canonicalPath(fixture.music.path) })
        await model.addFolder(other, replacing: original.folder)
        XCTAssertNotNil(model.operationError)
        XCTAssertEqual(model.folders.count, 2)
        let active = await access.url(for: original.id)
        XCTAssertEqual(active, fixture.music)
        XCTAssertEqual(client.counts.started - client.counts.stopped, 2)
        await model.shutdown().value
        XCTAssertEqual(client.counts.started, client.counts.stopped)
    }

    func testDatabaseFailureIsVisibleAndRetryDoesNotCreateMemoryLibrary() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.remove() }
        let blocker = fixture.root.appendingPathComponent("blocker")
        try Data("阻止创建数据库目录".utf8).write(to: blocker)
        let model = LibraryController(store: LibraryStore(location: .file(blocker.appendingPathComponent("Library.sqlite"))))
        await model.load()
        guard case .failed = model.state else { return XCTFail("应展示数据库错误") }
        await model.load()
        guard case .failed = model.state else { return XCTFail("重试不能隐藏数据库错误") }
        await model.shutdown().value
    }
}

private enum BookmarkStubError: LocalizedError {
    case unavailable
    var errorDescription: String? { "测试中的访问权限已失效" }
}

// 所有可变状态均受锁保护，模拟会从 actor 调用的系统书签接口。
private final class BookmarkStub: FolderBookmarkClient, @unchecked Sendable {
    private let lock = NSLock()
    private var started = 0
    private var stopped = 0
    private var sequence = 0
    private var stale = false
    private var resolveFailure = false
    private var createFailure = false
    private var startResult = true

    var counts: (started: Int, stopped: Int) { lock.withLock { (started, stopped) } }
    func setStale(_ value: Bool) { lock.withLock { stale = value } }
    func setResolveFailure(_ value: Bool) { lock.withLock { resolveFailure = value } }
    func setCreateFailure(_ value: Bool) { lock.withLock { createFailure = value } }
    func setStartResult(_ value: Bool) { lock.withLock { startResult = value } }

    func create(for url: URL) throws -> Data {
        try lock.withLock {
            if createFailure { throw BookmarkStubError.unavailable }
            sequence += 1
            return Data("\(sequence)|\(url.absoluteString)".utf8)
        }
    }
    func resolve(_ data: Data) throws -> ResolvedFolderBookmark {
        try lock.withLock {
            if resolveFailure { throw BookmarkStubError.unavailable }
            let text = String(decoding: data, as: UTF8.self).split(separator: "|").last.map(String.init) ?? ""
            guard let url = URL(string: text), url.isFileURL else { throw BookmarkStubError.unavailable }
            return ResolvedFolderBookmark(url: url, isStale: stale)
        }
    }
    func startAccessing(_ url: URL) -> Bool { lock.withLock { started += 1; return startResult } }
    func stopAccessing(_ url: URL) { lock.withLock { stopped += 1 } }
}
