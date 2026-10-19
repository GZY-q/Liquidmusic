import AppKit
import Observation

enum LibraryConnectionState: Equatable, Sendable {
    case idle, loading, ready, failed(String)
}

@MainActor @Observable
final class LibraryController {
    private(set) var state: LibraryConnectionState = .idle
    private(set) var folders: [FolderAccessSnapshot] = []
    private(set) var isWorking = false
    private(set) var tracks: [Track] = []
    private(set) var isScanning = false
    private(set) var scanProgress: ScanProgress?
    private(set) var scanReports: [ScanReport] = []
    private(set) var pendingReview: LibraryScanPlan?
    var operationError: String?
    let store: LibraryStore
    let access: FolderAccessController
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var panel: NSOpenPanel?
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration = UUID()
    @ObservationIgnored private var remainingFolders: [String] = []
    @ObservationIgnored private let scanner: LibraryScanner
    @ObservationIgnored private let automaticallyScanNewFolders: Bool

    var isBusy: Bool { isWorking || isScanning }

    init(store: LibraryStore, access: FolderAccessController = FolderAccessController(),
         scanner: LibraryScanner? = nil, automaticallyScanNewFolders: Bool = false) {
        self.store = store
        self.access = access
        self.scanner = scanner ?? LibraryScanner(store: store, access: access)
        self.automaticallyScanNewFolders = automaticallyScanNewFolders
    }

    func start() {
        guard loadTask == nil, !stopped, !isBusy else { return }
        loadTask = Task { [weak self] in
            await self?.load()
            self?.loadTask = nil
        }
    }

    func load() async {
        guard !stopped, !isBusy else { return }
        isWorking = true
        state = .loading
        defer { isWorking = false }
        do {
            try await store.open()
            let records = try await store.folders()
            var restored: [FolderAccessSnapshot] = []
            for folder in records {
                try Task.checkCancellation()
                guard !stopped else { return }
                let authorization: FolderAuthorization
                do { authorization = try await access.prepareRestoration(folder) }
                catch {
                    await access.release(folder.id)
                    restored.append(FolderAccessSnapshot(folder: folder, status: .needsAuthorization(error.localizedDescription)))
                    continue
                }
                do {
                    let saved: LibraryFolder
                    if authorization.folder == folder { saved = folder }
                    else { saved = try await store.saveFolder(authorization.folder) }
                    try Task.checkCancellation()
                    guard !stopped else { await access.discard(authorization); return }
                    try await access.commit(authorization, as: saved.id)
                    restored.append(FolderAccessSnapshot(folder: saved, status: .available))
                } catch {
                    await access.discard(authorization)
                    throw error
                }
            }
            try Task.checkCancellation()
            guard !stopped else { return }
            let indexed = try await store.tracks()
            try Task.checkCancellation()
            guard !stopped else { return }
            folders = restored
            tracks = indexed
            state = .ready
        } catch is CancellationError {
            if !stopped { state = .idle }
        } catch {
            if !stopped { state = .failed("无法打开资料库：\(error.localizedDescription)") }
        }
    }

    func chooseFolder(replacing folder: LibraryFolder? = nil) {
        guard state == .ready, !stopped, !isBusy, panel == nil else { return }
        let window = NSApplication.shared.keyWindow
        guard window?.attachedSheet == nil else { return }
        let chooser = NSOpenPanel()
        if let folder { chooser.title = "重新授权「\(folder.displayName)」" }
        else { chooser.title = "添加音乐文件夹" }
        chooser.prompt = "选择文件夹"
        chooser.canChooseFiles = false
        chooser.canChooseDirectories = true
        chooser.allowsMultipleSelection = false
        chooser.canCreateDirectories = false
        panel = chooser
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak chooser] response in
            guard let self else { return }
            let url = chooser?.url
            self.panel = nil
            guard response == .OK, let url else { return }
            self.loadTask = Task { [weak self] in
                await self?.addFolder(url, replacing: folder)
                self?.loadTask = nil
            }
        }
        if let window { chooser.beginSheetModal(for: window, completionHandler: completion) }
        else { chooser.begin(completionHandler: completion) }
    }

    func addFolder(_ url: URL, replacing folder: LibraryFolder? = nil) async {
        guard state == .ready, !stopped, !isBusy else { return }
        isWorking = true
        operationError = nil
        defer { isWorking = false }
        do {
            let authorization = try await access.prepareSelection(url, replacing: folder)
            do {
                try Task.checkCancellation()
                let saved = try await store.saveFolder(authorization.folder)
                try Task.checkCancellation()
                guard !stopped else { await access.discard(authorization); return }
                try await access.commit(authorization, as: saved.id)
                let snapshot = FolderAccessSnapshot(folder: saved, status: .available)
                if let index = folders.firstIndex(where: { $0.id == saved.id }) { folders[index] = snapshot }
                else { folders.append(snapshot) }
                folders.sort { $0.folder.displayName.localizedStandardCompare($1.folder.displayName) == .orderedAscending }
                if automaticallyScanNewFolders {
                    Task { [weak self] in self?.startScan(folderIDs: [saved.id]) }
                }
            } catch {
                await access.discard(authorization)
                throw error
            }
        } catch is CancellationError {
            // 取消或应用退出不显示失败，已有授权不会提前释放。
        } catch {
            if !stopped { operationError = "无法保存文件夹访问权限：\(error.localizedDescription)" }
        }
    }

    @discardableResult
    func shutdown() -> Task<Void, Never> {
        stopped = true
        scanGeneration = UUID()
        scanTask?.cancel()
        scanTask = nil
        loadTask?.cancel()
        loadTask = nil
        panel?.cancel(nil)
        panel = nil
        return Task { [access] in await access.shutdown() }
    }

    isolated deinit { loadTask?.cancel(); scanTask?.cancel() }

    func startScan(folderIDs: [String]? = nil) {
        guard state == .ready, !stopped, !isBusy else { return }
        let requested = Set(folderIDs ?? folders.filter(\.status.isAvailable).map(\.id))
        remainingFolders = folders.filter { requested.contains($0.id) && $0.status.isAvailable }
            .sorted { $0.folder.path.count > $1.folder.path.count }.map(\.id)
        guard !remainingFolders.isEmpty else { return }
        scanGeneration = UUID()
        let generation = scanGeneration
        operationError = nil
        scanReports = []
        pendingReview = nil
        isScanning = true
        scanTask = Task { [weak self] in await self?.scanNext(generation: generation) }
    }

    func cancelScan() {
        guard scanProgress?.phase != .saving else { return }
        scanGeneration = UUID()
        scanTask?.cancel()
        scanTask = nil
        pendingReview = nil
        remainingFolders = []
        isScanning = false
        if var progress = scanProgress { progress.phase = .cancelled; scanProgress = progress }
    }

    func applyReviewedChanges() {
        guard let plan = pendingReview, isScanning else { return }
        let generation = scanGeneration
        pendingReview = nil
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.saveScan(plan, confirmed: true, generation: generation)
                await self.scanNext(generation: generation)
            } catch { self.handleScanError(error, generation: generation) }
        }
    }

    private func scanNext(generation: UUID) async {
        do {
            while !remainingFolders.isEmpty {
                try Task.checkCancellation()
                guard generation == scanGeneration, !stopped else { return }
                let id = remainingFolders.removeFirst()
                guard let snapshot = folders.first(where: { $0.id == id }) else { continue }
                let plan = try await scanner.prepare(folder: snapshot.folder) { [weak self] progress in
                    guard let self, self.scanGeneration == generation, !self.stopped else { return }
                    self.scanProgress = progress
                }
                try Task.checkCancellation()
                guard generation == scanGeneration, !stopped else { return }
                if plan.requiresConfirmation {
                    pendingReview = plan
                    scanProgress = ScanProgress(phase: .reviewing, folderName: plan.folder.displayName)
                    scanTask = nil
                    return
                }
                try await saveScan(plan, confirmed: false, generation: generation)
            }
            guard generation == scanGeneration, !stopped else { return }
            isScanning = false
            scanTask = nil
            if var progress = scanProgress { progress.phase = .finished; scanProgress = progress }
        } catch { handleScanError(error, generation: generation) }
    }

    private func saveScan(_ plan: LibraryScanPlan, confirmed: Bool, generation: UUID) async throws {
        guard generation == scanGeneration, !stopped else { throw CancellationError() }
        scanProgress = ScanProgress(phase: .saving, folderName: plan.folder.displayName)
        try await scanner.commit(plan, confirmed: confirmed)
        let updated = try await store.tracks()
        guard generation == scanGeneration, !stopped else { return }
        tracks = updated
        scanReports.append(plan.report)
        if let index = folders.firstIndex(where: { $0.id == plan.folder.id }), plan.enumerationComplete {
            let folder = try await store.folders().first { $0.id == plan.folder.id } ?? plan.folder
            guard generation == scanGeneration, !stopped else { return }
            folders[index] = FolderAccessSnapshot(folder: folder, status: .available)
        }
    }

    private func handleScanError(_ error: Error, generation: UUID) {
        guard generation == scanGeneration, !stopped else { return }
        isScanning = false
        scanTask = nil
        pendingReview = nil
        remainingFolders = []
        if var progress = scanProgress {
            progress.phase = error is CancellationError ? .cancelled : .failed
            scanProgress = progress
        }
        if !(error is CancellationError) { operationError = "扫描未完成：\(error.localizedDescription)" }
    }

    static func preview() -> LibraryController {
        let model = LibraryController(store: LibraryStore(location: .memory))
        model.state = .ready
        model.folders = [FolderAccessSnapshot(folder: LibraryFolder(path: "/preview/Music", displayName: "我的音乐", bookmarkData: Data()), status: .available)]
        return model
    }
}
