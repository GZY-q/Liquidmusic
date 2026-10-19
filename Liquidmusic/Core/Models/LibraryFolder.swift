import Foundation

struct LibraryFolder: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var path: String
    var displayName: String
    var bookmarkData: Data
    var lastScanAt: Date?
}

struct ImportIssue: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var folderID: String
    var filePath: String
    var reason: String
    var occurredAt: Date = .now
}

enum FolderAccessStatus: Equatable, Sendable {
    case available
    case needsAuthorization(String)

    var isAvailable: Bool { self == .available }
    var message: String {
        switch self {
        case .available: "访问权限已保存"
        case .needsAuthorization(let reason): reason
        }
    }
}

struct FolderAccessSnapshot: Identifiable, Equatable, Sendable {
    let folder: LibraryFolder
    let status: FolderAccessStatus
    var id: String { folder.id }
}
