import SwiftUI

@main
struct LiquidmusicApp: App {
    @NSApplicationDelegateAdaptor(LiquidmusicAppDelegate.self) private var appDelegate
    @State private var windows = WindowLifecycleController()
    @FocusedValue(\.focusLibrarySearch) private var focusLibrarySearch
    // 测试宿主不打开用户的真实资料库；测试由用例显式注入临时/内存存储。
    @State private var model = AppModel(
        playback: PlaybackController(connectSystemMedia: false),
        fileReader: AppRuntime.isIsolated ? AudioFileReader() : ArtworkAudioFileReader(cacheDirectory: {
            try LibraryPaths.applicationSupportDirectory().appendingPathComponent("Artwork", isDirectory: true)
        }),
        library: AppRuntime.isIsolated
            ? nil : LibraryController(store: LibraryStore(location: .applicationSupport), automaticallyScanNewFolders: true)
    )

    var body: some Scene {
        Window("Liquidmusic", id: AppRuntime.mainWindowID) {
            ContentView(model: model)
                .preferredColorScheme(model.settings.value.appearance.colorScheme)
                .background {
                    if !AppRuntime.isIsolated { WindowLifecycleBridge(controller: windows) }
                }
                .onAppear {
                    guard !AppRuntime.isIsolated else { return }
                    appDelegate.windows = windows
                    model.start()
                }
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开音频文件…", systemImage: "music.note") { windows.restore(); model.openAudioFile() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .textEditing) {
                Button("搜索资料库", systemImage: "magnifyingglass") { focusLibrarySearch?() }
                    .keyboardShortcut("f").disabled(focusLibrarySearch == nil)
            }
        }
        Settings {
            SettingsView(controller: model.settings, library: model.library)
        }
        .windowResizability(.contentSize)
        MenuBarExtra("Liquidmusic", systemImage: "music.note",
                     isInserted: .constant(!AppRuntime.isIsolated && model.settings.value.showsMenuBarPlayer)) {
            MenuBarPlayerView(playback: model.playback, windows: windows)
                .preferredColorScheme(model.settings.value.appearance.colorScheme)
        }
        .menuBarExtraStyle(.window)
    }
}
