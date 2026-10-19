import Foundation
import Darwin

struct ResolvedFolderBookmark: Sendable {
    let url: URL
    let isStale: Bool
}

// 协议用于测试权限失效与过期书签，不依赖测试机的沙盒权限状态。
protocol FolderBookmarkClient: Sendable {
    func create(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> ResolvedFolderBookmark
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

struct SystemFolderBookmarkClient: FolderBookmarkClient {
    func create(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                             includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    func resolve(_ data: Data) throws -> ResolvedFolderBookmark {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return ResolvedFolderBookmark(url: url, isStale: stale)
    }
    func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

enum FolderAccessError: LocalizedError {
    case notReadableDirectory
    case noPendingAuthorization

    var errorDescription: String? {
        switch self {
        case .notReadableDirectory: "文件夹不存在或无法读取，请重新选择音乐文件夹。"
        case .noPendingAuthorization: "这次授权已取消，请重新选择文件夹。"
        }
    }
}

struct FolderAuthorization: Sendable {
    let token: UUID
    let folder: LibraryFolder
}

// 不暴露给 UI 的资源租约；最后一个持有者释放时配对 stop，失败路径也自动清理。
private final class FolderScopeLease: Sendable {
    let url: URL
    private let started: Bool
    private let client: any FolderBookmarkClient
    init(url: URL, client: any FolderBookmarkClient) {
        self.url = url
        self.client = client
        started = client.startAccessing(url)
    }
    deinit { if started { client.stopAccessing(url) } }
}

actor FolderAccessController {
    private let client: any FolderBookmarkClient
    private var pending: [UUID: FolderScopeLease] = [:]
    private var active: [String: FolderScopeLease] = [:]

    init(client: any FolderBookmarkClient = SystemFolderBookmarkClient()) { self.client = client }

    func prepareSelection(_ url: URL, replacing folder: LibraryFolder? = nil) throws -> FolderAuthorization {
        let lease = try readableLease(url)
        let bookmark = try client.create(for: url)
        let record = LibraryFolder(id: folder?.id ?? UUID().uuidString,
                                   path: LibraryStore.canonicalPath(url.path), displayName: url.lastPathComponent,
                                   bookmarkData: bookmark, lastScanAt: folder?.lastScanAt)
        return stage(lease, folder: record)
    }

    func prepareRestoration(_ folder: LibraryFolder) throws -> FolderAuthorization {
        let resolved = try client.resolve(folder.bookmarkData)
        let lease = try readableLease(resolved.url)
        var refreshed = folder
        refreshed.path = LibraryStore.canonicalPath(resolved.url.path)
        refreshed.displayName = resolved.url.lastPathComponent
        if resolved.isStale { refreshed.bookmarkData = try client.create(for: resolved.url) }
        return stage(lease, folder: refreshed)
    }

    // 只有数据库保存成功才用新租约替换旧租约；写库失败可丢弃临时授权，旧播放不中断。
    func commit(_ authorization: FolderAuthorization, as folderID: String) throws {
        guard let lease = pending.removeValue(forKey: authorization.token) else {
            throw FolderAccessError.noPendingAuthorization
        }
        active[folderID] = lease
    }

    func discard(_ authorization: FolderAuthorization) { pending[authorization.token] = nil }
    func url(for folderID: String) -> URL? { active[folderID]?.url }
    func validatedURL(for folderID: String) throws -> URL {
        guard let url = active[folderID]?.url else { throw LibraryScanError.noFolderAccess }
        try Self.verifyDirectory(url)
        return url
    }
    func release(_ folderID: String) { active[folderID] = nil }
    func shutdown() { pending.removeAll(); active.removeAll() }

    private func stage(_ lease: FolderScopeLease, folder: LibraryFolder) -> FolderAuthorization {
        let token = UUID()
        pending[token] = lease
        return FolderAuthorization(token: token, folder: folder)
    }

    private func readableLease(_ url: URL) throws -> FolderScopeLease {
        let lease = FolderScopeLease(url: url, client: client)
        try Self.verifyDirectory(url)
        return lease
    }

    private static func verifyDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard url.isFileURL, values.isDirectory == true, values.isReadable == true else {
            throw FolderAccessError.notReadableDirectory
        }
        // POSIX 权限信息不足以证明沙盒允许读取；只尝试打开根目录，不枚举文件。
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else { throw FolderAccessError.notReadableDirectory }
        Darwin.close(descriptor)
    }
}
