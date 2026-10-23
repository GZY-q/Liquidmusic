import Foundation
import GRDB

enum LibraryLocation: Sendable {
    case applicationSupport
    case file(URL)
    case memory
}

enum LibraryStoreError: LocalizedError {
    case invalidTrack
    case folderPathConflict

    var errorDescription: String? {
        switch self {
        case .invalidTrack: "歌曲路径、所属文件夹或音频时长无效，无法保存索引。"
        case .folderPathConflict: "这个位置已属于另一个音乐文件夹，请选择对应的原文件夹。"
        }
    }
}

extension LibraryFolder: FetchableRecord, PersistableRecord {
    static let databaseTableName = "libraryFolder"
}
extension Track: FetchableRecord, PersistableRecord {
    static let databaseTableName = "track"
}
extension ImportIssue: FetchableRecord, PersistableRecord {
    static let databaseTableName = "importIssue"
}

extension ListeningActivity: FetchableRecord, PersistableRecord {
    static let databaseTableName = "listeningActivity"
}

// 所有磁盘访问都在独立 actor 上执行；初始化仅保存配置，不打开真实数据库。
actor LibraryStore {
    private let location: LibraryLocation
    private var database: DatabaseQueue?
    private var artworkURL: URL?

    init(location: LibraryLocation) { self.location = location }

    func open() throws { _ = try connection() }

    func listeningActivity(paths: [String], playedPath: String? = nil, at date: Date = .now) throws -> [String: ListeningActivity] {
        try connection().write { db in
            for path in Set(paths + (playedPath.map { [$0] } ?? [])) {
                try db.execute(sql: "INSERT OR IGNORE INTO listeningActivity (path, addedAt, playCount) VALUES (?, ?, 0)",
                               arguments: [path, date])
            }
            if let playedPath {
                try db.execute(sql: "UPDATE listeningActivity SET lastPlayedAt = ?, playCount = playCount + 1 WHERE path = ?",
                               arguments: [date, playedPath])
            }
            return Dictionary(uniqueKeysWithValues: try ListeningActivity.fetchAll(db).map { ($0.path, $0) })
        }
    }

    func preferences() throws -> AppPreferences {
        try connection().read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT value FROM appSettings WHERE id = 1") else {
                return AppPreferences()
            }
            return try JSONDecoder().decode(AppPreferences.self, from: data).normalized
        }
    }

    func savePreferences(_ preferences: AppPreferences) throws {
        let data = try JSONEncoder().encode(preferences.normalized)
        try connection().write { db in
            try db.execute(sql: "INSERT INTO appSettings (id, value) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET value = excluded.value",
                           arguments: [data])
        }
    }

    func artworkDirectory() throws -> URL? {
        _ = try connection()
        return artworkURL
    }

    func close() throws {
        try database?.close()
        database = nil
    }

    func folders() throws -> [LibraryFolder] {
        try connection().read { db in
            try LibraryFolder.order(Column("displayName"), Column("id")).fetchAll(db)
        }
    }

    // 相同路径保持原 ID；重新授权通过 ID 更新，不能覆盖另一个文件夹的身份。
    @discardableResult
    func saveFolder(_ folder: LibraryFolder) throws -> LibraryFolder {
        var value = folder
        value.path = Self.canonicalPath(folder.path)
        let normalized = value
        return try connection().write { db in
            let sameID = try LibraryFolder.fetchOne(db, key: normalized.id)
            let samePath = try LibraryFolder.filter(Column("path") == normalized.path).fetchOne(db)
            if sameID != nil, let samePath, samePath.id != normalized.id {
                throw LibraryStoreError.folderPathConflict
            }
            var saved = normalized
            if sameID == nil, let samePath {
                saved.id = samePath.id
                saved.lastScanAt = samePath.lastScanAt
            }
            try saved.save(db)
            return saved
        }
    }

    func tracks(folderID: String? = nil) throws -> [Track] {
        try connection().read { db in
            var request = Track.all()
            if let folderID { request = request.filter(Column("folderID") == folderID) }
            return try request.order(Column("title"), Column("id")).fetchAll(db)
        }
    }

    // 整批事务写入；首次入库生成 UUID，后续重扫用规范路径找到并保留稳定 ID。
    @discardableResult
    func upsertTracks(_ tracks: [Track]) throws -> [Track] {
        let normalized = try tracks.map { track in
            guard track.path.hasPrefix("/"), !track.folderID.isEmpty,
                  track.duration.isFinite, track.duration > 0 else { throw LibraryStoreError.invalidTrack }
            var result = track
            result.path = Self.canonicalPath(track.path)
            return result
        }
        return try connection().write { db in
            try normalized.map { track in
                var saved = track
                let existing = try Track.filter(Column("path") == track.path).fetchOne(db)
                saved.id = existing?.id ?? UUID().uuidString
                try saved.save(db)
                return saved
            }
        }
    }

    func recordIssue(_ issue: ImportIssue) throws {
        try connection().write { db in try issue.insert(db) }
    }

    func issues(folderID: String) throws -> [ImportIssue] {
        try connection().read { db in
            try ImportIssue.filter(Column("folderID") == folderID)
                .order(Column("occurredAt"), Column("id")).fetchAll(db)
        }
    }

    // 扫描方案原子应用；已有行的覆盖/删除必须由调用方传入用户确认结果。
    func applyScan(_ plan: LibraryScanPlan, confirmed: Bool) throws {
        guard !plan.requiresConfirmation || confirmed else { throw LibraryScanError.confirmationRequired }
        try Task.checkCancellation()
        try connection().write { db in
            guard var folder = try LibraryFolder.fetchOne(db, key: plan.folder.id), folder.path == plan.folder.path else {
                throw LibraryScanError.stalePlan
            }
            for track in plan.changes + plan.missing {
                let current = try Track.filter(Column("path") == track.path).fetchOne(db)
                guard current == plan.baseline[track.path] else { throw LibraryScanError.stalePlan }
            }
            for track in plan.changes {
                try Task.checkCancellation()
                guard track.duration.isFinite, track.duration > 0, track.folderID == folder.id else {
                    throw LibraryStoreError.invalidTrack
                }
                var record = track
                record.id = plan.baseline[track.path]?.id ?? UUID().uuidString
                try record.save(db)
            }
            if plan.enumerationComplete {
                for track in plan.missing { try Track.deleteOne(db, key: track.id) }
                folder.lastScanAt = plan.scannedAt
                try folder.update(db)
            }
            for issue in plan.issues { try issue.insert(db) }
            try Task.checkCancellation()
        }
    }

    nonisolated static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func connection() throws -> DatabaseQueue {
        if let database { return database }
        let opened: DatabaseQueue
        switch location {
        case .memory:
            opened = try DatabaseQueue()
        case .applicationSupport:
            opened = try openFile(LibraryPaths.applicationSupportDirectory().appendingPathComponent("Library.sqlite"))
        case .file(let url):
            opened = try openFile(url)
        }
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_library") { db in
            try db.create(table: "libraryFolder") { table in
                table.primaryKey("id", .text)
                table.column("path", .text).notNull().unique()
                table.column("displayName", .text).notNull()
                table.column("bookmarkData", .blob).notNull()
                table.column("lastScanAt", .datetime)
            }
            try db.create(table: "track") { table in
                table.primaryKey("id", .text)
                table.column("folderID", .text).notNull().indexed().references("libraryFolder", onDelete: .restrict)
                table.column("path", .text).notNull().unique()
                for name in ["title", "artist", "album", "albumArtist"] { table.column(name, .text).notNull() }
                table.column("duration", .double).notNull()
                table.column("discNumber", .integer).notNull().defaults(to: 0)
                table.column("trackNumber", .integer).notNull().defaults(to: 0)
                table.column("artworkPath", .text)
                table.column("modifiedAt", .datetime).notNull()
            }
            try db.create(table: "importIssue") { table in
                table.primaryKey("id", .text)
                table.column("folderID", .text).notNull().indexed().references("libraryFolder", onDelete: .restrict)
                table.column("filePath", .text).notNull()
                table.column("reason", .text).notNull()
                table.column("occurredAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2_fileFingerprint") { db in
            try db.alter(table: "track") { table in table.add(column: "fileSize", .integer) }
        }
        // 迁移失败不保留半初始化连接，不启用自动清库或内存回退。
        migrator.registerMigration("v3_appSettings") { db in
            try db.create(table: "appSettings") { table in
                table.primaryKey("id", .integer)
                table.column("value", .blob).notNull()
            }
        }
        migrator.registerMigration("v4_listeningActivity") { db in
            try db.create(table: "listeningActivity") { table in
                table.primaryKey("path", .text)
                table.column("addedAt", .datetime).notNull()
                table.column("lastPlayedAt", .datetime)
                table.column("playCount", .integer).notNull().defaults(to: 0)
            }
        }
        try migrator.migrate(opened)
        database = opened
        return opened
    }

    private func openFile(_ url: URL) throws -> DatabaseQueue {
        let root = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Artwork", isDirectory: true),
                                                withIntermediateDirectories: true)
        artworkURL = root.appendingPathComponent("Artwork", isDirectory: true)
        return try DatabaseQueue(path: url.path)
    }
}
