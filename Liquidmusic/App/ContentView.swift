import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.artworkDataLoader) private var loadArtwork
    @State private var browser: LibraryViewModel
    @State private var showsQueue = false
    @State private var showsFolders = false
    @State private var showsReport = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchRequest = 0
    @State private var windowWidth: CGFloat = 640
    private var usesQueuePopover: Bool { windowWidth < 900 }

    init(model: AppModel, browser: LibraryViewModel = LibraryViewModel()) {
        self.model = model
        _browser = State(initialValue: browser)
    }

    var body: some View {
        libraryBrowser
            .safeAreaInset(edge: .top, spacing: 0) {
                WindowDragArea().frame(height: 24)
            }
        .frame(minWidth: 640, minHeight: 520)
        .navigationTitle(browser.title)
        .toolbarColorScheme(colorScheme, for: .windowToolbar)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            // 跨展示方式时收起面板，避免右侧面板与 popover 同时争用呈现状态。
            if (width < 900) != usesQueuePopover { showsQueue = false }
            windowWidth = width
        }
        .focusedSceneValue(\.focusLibrarySearch) {
            columnVisibility = .all
            searchRequest += 1
        }
        .onChange(of: model.tracks, initial: true) { _, tracks in
            browser.replaceTracks(tracks)
            if !tracks.isEmpty { model.activity.synchronize(tracks) }
        }
        .onChange(of: model.activity.records, initial: true) { _, records in browser.replaceActivity(records) }
        .sheet(isPresented: $showsFolders) {
            if let library = model.library { LibraryFoldersView(controller: library) }
        }
        .sheet(isPresented: $showsReport) {
            if let library = model.library { ImportReportView(reports: library.scanReports) }
        }
        .onChange(of: model.library?.pendingReview?.id) { _, id in
            if id != nil { showsFolders = true }
        }
        .onChange(of: model.library?.operationError) { _, message in
            if message != nil { showsFolders = true }
        }
        .alert("无法打开音频文件", isPresented: Binding(get: { model.importError != nil }, set: { if !$0 { model.importError = nil } })) {
            Button("重新选择…") { model.importError = nil; model.openAudioFile() }
            Button("好", role: .cancel) { model.importError = nil }
        } message: { Text(model.importError ?? "") }
        .alert("播放失败", isPresented: Binding(get: { model.playback.errorMessage != nil }, set: { if !$0 { model.playback.errorMessage = nil } })) {
            Button("重新选择…") { model.playback.errorMessage = nil; model.openAudioFile() }
            Button("好", role: .cancel) { model.playback.errorMessage = nil }
        } message: { Text(model.playback.errorMessage ?? "") }
    }

    private var libraryBrowser: some View {
        HStack(spacing: 0) {
            splitView
            if showsQueue && !usesQueuePopover {
                Divider()
                QueueView(playback: model.playback).frame(width: 280)
            }
        }
    }

    private var splitView: some View {
        @Bindable var browser = browser
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $browser.section, searchText: $browser.query, trackCount: browser.trackCount,
                        searchRequest: searchRequest)
        } detail: {
            LibraryView(model: browser, playback: model.playback,
                        connection: model.library?.state,
                        isImporting: model.isImporting || model.library?.isScanning == true,
                        hasFolders: model.library?.folders.isEmpty == false,
                        addFolder: addFolderAction,
                        manageFolders: model.library == nil ? nil : { showsFolders = true },
                        retry: model.library?.start,
                        openAudioFile: model.openAudioFile, loadArtwork: loadArtwork)
            .toolbar {
                Menu("添加音乐", systemImage: "plus") {
                    Button("打开音频文件…", systemImage: "music.note", action: model.openAudioFile)
                    if model.library != nil {
                        Button("音乐文件夹", systemImage: "folder") { showsFolders = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // 原生安全区为最后一行留出空间，侧边栏仍延伸到窗口底部。
                PlayerBar(playback: model.playback, showsQueue: $showsQueue, usesQueuePopover: usesQueuePopover)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let error = model.activity.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading).background(.bar)
                }
                if !model.importWarnings.isEmpty {
                    AudioImportNotice(warnings: model.importWarnings, onDismiss: model.dismissImportWarnings)
                }
                if let library = model.library {
                    if let progress = library.scanProgress {
                        ImportProgressView(progress: progress, reports: library.scanReports,
                                           onCancel: library.cancelScan, onReview: { showsFolders = true }, onReport: { showsReport = true })
                    }
                    if case .failed(let message) = library.state, browser.trackCount > 0 {
                        HStack {
                            Label(message, systemImage: "exclamationmark.triangle")
                            Spacer()
                            Button("重试", action: library.start)
                        }.font(.callout).padding().background(.bar)
                    } else if library.folders.contains(where: { !$0.status.isAvailable }) {
                        HStack {
                            Label("部分音乐文件夹需要重新授权", systemImage: "folder.badge.questionmark")
                            Spacer()
                            Button("管理文件夹") { showsFolders = true }
                        }.font(.callout).padding().background(.bar)
                    }
                }
                if model.isImporting {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在读取音频文件…").font(.callout)
                        Spacer()
                        Button("取消", action: model.cancelImport)
                    }.padding().background(.bar)
                }
            }
        }
    }

    private var addFolderAction: (() -> Void)? {
        guard let library = model.library, library.state == .ready, !library.isBusy else { return nil }
        return { library.chooseFolder() }
    }
}

#Preview("歌曲") {
    ContentView(model: AppModel(playback: .preview(track: SPXData.tracks[0]), tracks: SPXData.tracks), browser: .preview())
        .frame(width: 1100, height: 680)
}

#Preview("窄窗口") {
    ContentView(model: AppModel(playback: .preview(track: SPXData.tracks[0]), tracks: SPXData.tracks), browser: .preview())
        .frame(width: 640, height: 520)
}

#Preview("最近添加·专辑网格") {
    ContentView(model: AppModel(playback: .preview(track: SPXArtwork.tracks[1]), tracks: SPXArtwork.tracks),
                browser: .preview(section: .recentlyAdded, tracks: SPXArtwork.tracks))
        .environment(\.artworkDataLoader, SPXArtwork.loader)
        .frame(width: 1100, height: 700)
}

#Preview("空库") {
    ContentView(model: AppModel(playback: PlaybackController(connectSystemMedia: false)))
        .frame(width: 800, height: 560)
}
