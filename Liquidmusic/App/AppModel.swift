import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    let playback: PlaybackController
    let library: LibraryController?
    let settings: SettingsController
    let activity: ListeningActivityController
    private var temporaryTracks: [Track]
    var tracks: [Track] {
        guard let library else { return temporaryTracks }
        let paths = Set(library.tracks.map(\.path))
        return library.tracks + temporaryTracks.filter { !paths.contains($0.path) }
    }
    private(set) var isImporting = false
    var importError: String?
    private(set) var importWarnings: [String] = []
    @ObservationIgnored private let fileReader: any AudioFileReading
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var importGeneration = UUID()
    @ObservationIgnored private var openPanel: NSOpenPanel?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var settingsTask: Task<Void, Never>?

    init(playback: PlaybackController, fileReader: any AudioFileReading = AudioFileReader(), tracks: [Track] = [], library: LibraryController? = nil) {
        self.playback = playback
        self.library = library
        self.fileReader = fileReader
        self.temporaryTracks = tracks
        self.settings = SettingsController(store: library?.store, playback: playback)
        let activity = ListeningActivityController(store: library?.store)
        self.activity = activity
        playback.onPlaybackStarted = { [weak activity] track in activity?.recordPlayback(track) }
    }

    // 只在真实 App 入口注册生命周期通知，预览和单测无需连接系统行为。
    func start() {
        guard terminationObserver == nil else { return }
        playback.connectSystemMedia()
        library?.start()
        settingsTask = Task { [settings] in await settings.load() }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }
    }

    func openAudioFile() {
        guard openPanel == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "打开音频文件"
        panel.prompt = "打开"
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        openPanel = panel
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self else { return }
            let selectedURL = panel?.url
            self.openPanel = nil
            guard response == .OK, let url = selectedURL else { return }
            self.importFile(url)
        }
        if let window = NSApplication.shared.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    @discardableResult
    func importFile(_ url: URL) -> Task<Void, Never> {
        importTask?.cancel()
        let generation = UUID()
        importGeneration = generation
        isImporting = true
        importError = nil
        importWarnings = []
        importTask = Task { [weak self, fileReader] in
            // 校验期间持有授权；播放器接管后建立自己的访问，再释放临时授权。
            let access = AudioFileAccess(url)
            defer { withExtendedLifetime(access) {} }
            do {
                let result = try await fileReader.readResult(url)
                let track = result.track
                try Task.checkCancellation()
                guard let self, self.importGeneration == generation else { return }
                self.temporaryTracks = [track]
                let indexed = self.library?.tracks.first { $0.path == track.path }
                let selected = indexed ?? track
                self.importWarnings = result.warnings
                if indexed != nil, selected.artworkPath == nil, track.artworkPath != nil {
                    self.importWarnings.append("这首歌曲已在资料库中，当前索引没有封面。请在“音乐文件夹”重新扫描，并审阅应用索引变更。")
                }
                self.playback.play(selected, in: self.tracks)
            } catch is CancellationError {
                // 新选择或显式取消不覆盖当前曲目，也不显示失败提示。
            } catch {
                guard let self, self.importGeneration == generation, !Task.isCancelled else { return }
                self.importError = "无法打开「\(url.lastPathComponent)」：\(error.localizedDescription)"
            }
            guard let self, self.importGeneration == generation else { return }
            self.isImporting = false
            self.importTask = nil
        }
        return importTask!
    }

    func cancelImport() {
        importGeneration = UUID()
        importTask?.cancel()
        importTask = nil
        isImporting = false
        importWarnings = []
    }

    func dismissImportWarnings() { importWarnings = [] }

    func shutdown() {
        settingsTask?.cancel()
        settingsTask = nil
        cancelImport()
        openPanel?.cancel(nil)
        openPanel = nil
        playback.shutdown()
        library?.shutdown()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
    }

    isolated deinit {
        settingsTask?.cancel()
        importTask?.cancel()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }
}
