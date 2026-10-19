import Foundation

actor LibraryScanner {
    static let extensions: Set<String> = ["m4a", "mp3", "flac", "wav", "aiff", "aif"]
    private let store: LibraryStore
    private let access: FolderAccessController
    private let reader: any AudioMetadataReading
    private let artworkCache: ArtworkCache?

    init(store: LibraryStore, access: FolderAccessController,
         reader: any AudioMetadataReading = AudioFileReader(), artworkCache: ArtworkCache? = nil) {
        self.store = store
        self.access = access
        self.reader = reader
        self.artworkCache = artworkCache
    }

    func prepare(folder: LibraryFolder,
                 progress: @escaping @MainActor @Sendable (ScanProgress) -> Void) async throws -> LibraryScanPlan {
        let root = try await access.validatedURL(for: folder.id)
        let registered = try await store.folders()
        let before = try await store.tracks()
        let baseline = Dictionary(uniqueKeysWithValues: before.map { ($0.path, $0) })
        let cache: ArtworkCache
        if let artworkCache { cache = artworkCache }
        else { cache = ArtworkCache(directory: try await store.artworkDirectory()) }
        var issues: [ImportIssue] = []
        var directories = [root]
        var candidates: [URL] = []
        var seen = Set<String>()
        var enumerationComplete = true
        var visited = 0
        await progress(ScanProgress(phase: .discovering, folderName: folder.displayName))
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
        while let directory = directories.popLast() {
            try Task.checkCancellation()
            do {
                let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys,
                                                                          options: [.skipsHiddenFiles])
                for child in children {
                    try Task.checkCancellation()
                    visited += 1
                    do {
                        let values = try child.resourceValues(forKeys: Set(keys))
                        if values.isSymbolicLink == true || values.isPackage == true { continue }
                        if values.isDirectory == true { directories.append(child); continue }
                        guard values.isRegularFile == true, Self.extensions.contains(child.pathExtension.lowercased()) else { continue }
                        let path = LibraryStore.canonicalPath(child.path)
                        seen.insert(path)
                        // 重叠根目录由最具体的已注册目录拥有，扫描顺序不会改变归属。
                        if Self.owner(of: path, among: registered)?.id == folder.id {
                            candidates.append(URL(fileURLWithPath: path))
                        }
                    } catch {
                        enumerationComplete = false
                        issues.append(ImportIssue(folderID: folder.id, filePath: child.path, reason: error.localizedDescription))
                    }
                    if visited.isMultiple(of: 128) {
                        await progress(ScanProgress(phase: .discovering, folderName: folder.displayName, discovered: candidates.count))
                        await Task.yield()
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                enumerationComplete = false
                issues.append(ImportIssue(folderID: folder.id, filePath: directory.path, reason: error.localizedDescription))
            }
        }
        candidates.sort { $0.path < $1.path }
        try Task.checkCancellation()
        var changes: [Track] = []
        var reused = 0
        var skipped = 0
        var lastUpdate = ContinuousClock.now
        await progress(ScanProgress(phase: .indexing, folderName: folder.displayName,
                                    discovered: candidates.count, total: candidates.count))
        for (index, url) in candidates.enumerated() {
            try Task.checkCancellation()
            do {
                let fingerprint = try FileFingerprint.read(url)
                if let old = baseline[url.path], old.folderID == folder.id, fingerprint.matches(old),
                   old.artworkPath.map({ FileManager.default.fileExists(atPath: $0) }) ?? true {
                    reused += 1
                } else {
                    var metadata = try await reader.readMetadata(url)
                    try Task.checkCancellation()
                    guard try FileFingerprint.read(url) == fingerprint else { throw LibraryScanError.fileChanged }
                    metadata.track.folderID = folder.id
                    metadata.track.path = url.path
                    metadata.track.modifiedAt = fingerprint.modifiedAt
                    metadata.track.fileSize = fingerprint.size
                    if let data = metadata.artworkData {
                        do { metadata.track.artworkPath = try await cache.store(data) }
                        catch { metadata.warnings.append(error.localizedDescription) }
                    }
                    for warning in metadata.warnings {
                        issues.append(ImportIssue(folderID: folder.id, filePath: url.path, reason: warning))
                    }
                    changes.append(metadata.track)
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                skipped += 1
                issues.append(ImportIssue(folderID: folder.id, filePath: url.path, reason: "已跳过音频：\(error.localizedDescription)"))
            }
            let now = ContinuousClock.now
            if now - lastUpdate >= .milliseconds(100) || index + 1 == candidates.count {
                await progress(ScanProgress(phase: .indexing, folderName: folder.displayName,
                                            discovered: candidates.count, processed: index + 1,
                                            total: candidates.count, currentFile: url.lastPathComponent))
                lastUpdate = now
            }
        }
        try Task.checkCancellation()
        let missing = enumerationComplete ? before.filter { $0.folderID == folder.id && !seen.contains($0.path) } : []
        return LibraryScanPlan(id: UUID(), folder: folder, rootURL: root, baseline: baseline,
                               changes: changes, missing: missing, reused: reused, skipped: skipped,
                               enumerationComplete: enumerationComplete, issues: issues, scannedAt: .now)
    }

    func commit(_ plan: LibraryScanPlan, confirmed: Bool) async throws {
        guard !plan.requiresConfirmation || confirmed else { throw LibraryScanError.confirmationRequired }
        let root = try await access.validatedURL(for: plan.folder.id)
        guard LibraryStore.canonicalPath(root.path) == plan.folder.path else { throw LibraryScanError.stalePlan }
        for track in plan.changes {
            try Task.checkCancellation()
            guard let fingerprint = try? FileFingerprint.read(track.url), fingerprint.matches(track) else {
                throw LibraryScanError.stalePlan
            }
        }
        for track in plan.missing {
            // 从生成清单到点击确认期间重新出现的文件不能再按“失踪”清理。
            if FileManager.default.fileExists(atPath: track.path) { throw LibraryScanError.stalePlan }
        }
        try Task.checkCancellation()
        try await store.applyScan(plan, confirmed: confirmed)
    }

    private static func owner(of path: String, among folders: [LibraryFolder]) -> LibraryFolder? {
        folders.filter { path.hasPrefix($0.path == "/" ? "/" : $0.path + "/") }
            .sorted { $0.path.count == $1.path.count ? $0.id < $1.id : $0.path.count > $1.path.count }.first
    }
}
