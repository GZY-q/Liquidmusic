import SwiftUI

@main
struct LiquidmusicApp: App {
    @NSApplicationDelegateAdaptor(LiquidmusicAppDelegate.self) private var appDelegate
    @State private var windows = WindowLifecycleController()
    @FocusedValue(\.focusLibrarySearch) private var focusLibrarySearch
    // 测试宿主不打开用户的真实资料库；测试由用例显式注入临时/内存存储。
    @State private var model = AppModel(
        playback: PlaybackController(connectSystemMedia: false),
        library: AppRuntime.isIsolated
            ? nil : LibraryController(store: LibraryStore(location: .applicationSupport), automaticallyScanNewFolders: true)
    )

    var body: some Scene {
        Window("Liquidmusic", id: AppRuntime.mainWindowID) {
            ContentView(model: model)
                .background {
                    if !AppRuntime.isIsolated { WindowLifecycleBridge(controller: windows) }
                }
                .onAppear {
                    guard !AppRuntime.isIsolated else { return }
                    appDelegate.windows = windows
                    model.start()
                }
        }
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
        MenuBarExtra("Liquidmusic", systemImage: "music.note", isInserted: .constant(!AppRuntime.isIsolated)) {
            MenuBarPlayerView(playback: model.playback, windows: windows)
        }
        .menuBarExtraStyle(.window)
    }
}
