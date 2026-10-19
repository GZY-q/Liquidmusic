import Foundation

struct FileFingerprint: Equatable, Sendable {
    let modifiedAt: Date
    let size: Int64

    static func read(_ url: URL) throws -> FileFingerprint {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let date = values.contentModificationDate, let size = values.fileSize else {
            throw CocoaError(.fileReadUnknown)
        }
        return FileFingerprint(modifiedAt: date, size: Int64(size))
    }

    func matches(_ track: Track) -> Bool {
        // SQLite 日期精度为毫秒；文件系统可能提供更高精度。
        track.fileSize == size && abs(track.modifiedAt.timeIntervalSince(modifiedAt)) < 0.001
    }
}

struct AudioMetadata: Sendable {
    var track: Track
    var artworkData: Data?
    var warnings: [String] = []
}

protocol AudioMetadataReading: Sendable {
    func readMetadata(_ url: URL) async throws -> AudioMetadata
}

enum ScanPhase: Equatable, Sendable {
    case discovering, indexing, reviewing, saving, finished, cancelled, failed
}

struct ScanProgress: Sendable {
    var phase: ScanPhase
    var folderName: String
    var discovered = 0
    var processed = 0
    var total = 0
    var currentFile: String?
}

struct ScanReport: Identifiable, Sendable {
    let id: UUID
    let folderName: String
    let added: Int
    let updated: Int
    let reused: Int
    let skipped: Int
    let removed: Int
    let enumerationComplete: Bool
    let issues: [ImportIssue]
}

// 扫描阶段只生成值类型方案；已有索引的修改/删除必须经过用户确认。
struct LibraryScanPlan: Identifiable, Sendable {
    let id: UUID
    let folder: LibraryFolder
    let rootURL: URL
    let baseline: [String: Track]
    let changes: [Track]
    let missing: [Track]
    let reused: Int
    let skipped: Int
    let enumerationComplete: Bool
    let issues: [ImportIssue]
    let scannedAt: Date

    var additions: [Track] { changes.filter { baseline[$0.path] == nil } }
    var updates: [Track] { changes.filter { baseline[$0.path] != nil } }
    var requiresConfirmation: Bool { !updates.isEmpty || !missing.isEmpty }
    var report: ScanReport {
        ScanReport(id: id, folderName: folder.displayName, added: additions.count, updated: updates.count,
                   reused: reused, skipped: skipped, removed: missing.count,
                   enumerationComplete: enumerationComplete, issues: issues)
    }
}

enum LibraryScanError: LocalizedError {
    case stalePlan
    case confirmationRequired
    case fileChanged
    case noFolderAccess

    var errorDescription: String? {
        switch self {
        case .stalePlan: "文件或资料库在扫描后发生变化，请重新扫描后再确认。"
        case .confirmationRequired: "已有索引的变更尚未获得确认。"
        case .fileChanged: "文件在读取时发生变化，已保留原索引，请稍后重新扫描。"
        case .noFolderAccess: "音乐文件夹当前不可读取，请重新授权后再扫描。"
        }
    }
}
