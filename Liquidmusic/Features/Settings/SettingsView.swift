import SwiftUI

extension SettingsTab {
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .playback: "play.circle"
        case .files: "folder"
        case .advanced: "gearshape.2"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .general: "1"
        case .playback: "2"
        case .files: "3"
        case .advanced: "4"
        }
    }
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @Bindable var controller: SettingsController
    let library: LibraryController?
    private let initialTab: SettingsTab?
    @Environment(\.dismiss) private var dismiss
    @State private var tab: SettingsTab
    @State private var draft = AppPreferences()
    @State private var showsFolders = false

    init(controller: SettingsController, library: LibraryController?, initialTab: SettingsTab? = nil) {
        self.controller = controller
        self.library = library
        self.initialTab = initialTab
        _tab = State(initialValue: initialTab ?? controller.selectedTab)
        _draft = State(initialValue: controller.value)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(SettingsTab.allCases, id: \.self) { item in
                    Button {
                        tab = item
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.symbol).font(.largeTitle)
                            Text(item.rawValue).font(.body)
                        }
                        .foregroundStyle(tab == item ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 76, height: 66)
                        .background(tab == item ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(item.shortcut, modifiers: .command)
                    .help("\(item.rawValue)（⌘\(String(item.shortcut.character))）")
                    .accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                    .accessibilityIdentifier("settings.tab.\(item)")
                }
            }
            .padding(.vertical, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if controller.isLoaded {
                        switch tab {
                        case .general: general
                        case .playback: playback
                        case .files: files
                        case .advanced: advanced
                        }
                    } else if let error = controller.errorMessage {
                        ContentUnavailableView {
                            Label("无法读取设置", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("重新读取") {
                                Task {
                                    await controller.load()
                                    draft = controller.value
                                }
                            }
                        }
                    } else {
                        ProgressView("正在读取设置…")
                    }
                    if controller.isLoaded, let error = controller.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if controller.isSaving { ProgressView().controlSize(.small) }
                    Text(controller.isSaving ? "正在保存设置…" :
                         (draft.normalized != controller.value ? "有尚未保存的更改。" : "更改后点按“好”以保存。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if tab != .files {
                        Button("恢复本页默认值", action: restoreDefaults)
                            .disabled(!controller.isLoaded)
                            .help("仅更改当前页的草稿，点按“好”后保存。")
                    }
                    Spacer()
                    Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("好") {
                        if draft.normalized == controller.value { dismiss() }
                        else {
                            Task {
                                if await controller.save(draft) { dismiss() }
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!controller.isLoaded || controller.isSaving)
                }
            }
            .padding(16)
        }
        .disabled(controller.isSaving)
        .frame(width: 620, height: 440)
        .navigationTitle(tab.rawValue)
        .tint(.red)
        // 外观草稿只预览当前设置窗口；主窗口仍使用已保存的偏好。
        .preferredColorScheme((controller.isLoaded ? draft.appearance : controller.value.appearance).colorScheme)
        .task {
            await controller.load()
            draft = controller.value
        }
        .onAppear {
            tab = initialTab ?? controller.selectedTab
            draft = controller.value
            if controller.isLoaded { controller.errorMessage = nil }
        }
        .onChange(of: tab) { _, selected in controller.selectedTab = selected }
        .onChange(of: controller.isLoaded) { _, loaded in
            if loaded { draft = controller.value }
        }
        .sheet(isPresented: $showsFolders) {
            if let library { LibraryFoldersView(controller: library) }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("外观：", selection: $draft.appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
            }.frame(maxWidth: 320)
            Text("在此窗口预览外观，点按“好”后应用到所有窗口。")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("在菜单栏显示迷你播放器", isOn: $draft.showsMenuBarPlayer)
            Text("关闭主窗口时，音乐仍会继续播放；可从 Dock 恢复窗口。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var playback: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("交叉渐入渐出歌曲", isOn: $draft.crossfadeEnabled)
                .accessibilityIdentifier("settings.crossfade")
            VStack(spacing: 6) {
                Slider(value: $draft.crossfadeDuration, in: 1...12, step: 1) {
                    Text("交叉渐入渐出时长")
                }
                .labelsHidden()
                .accessibilityValue("\(Int(draft.crossfadeDuration)) 秒")
                .accessibilityIdentifier("settings.crossfadeDuration")
                HStack {
                    Text("1")
                    Spacer()
                    Text("\(Int(draft.crossfadeDuration)) 秒").monospacedDigit()
                    Spacer()
                    Text("12")
                }.font(.callout)
            }
            .padding(.leading, 22)
            .disabled(!draft.crossfadeEnabled)
            Text("自动切换歌曲时，让上一首渐弱、下一首渐强。短曲会缩短重叠时间；手动切歌和单曲循环保持直接切换。")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Picker("默认播放模式：", selection: $draft.defaultPlaybackMode) {
                ForEach(PlaybackMode.allCases) { Text($0.rawValue).tag($0) }
            }.frame(maxWidth: 320)
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("音乐文件夹", systemImage: "folder").font(.headline)
            Text("保留音频的原始位置，通过文件夹授权建立资料库。")
                .foregroundStyle(.secondary)
            Button("管理音乐文件夹…") { showsFolders = true }
                .disabled(library == nil)
            Text("在管理窗口中添加文件夹、重新授权或扫描。已有索引的更新和失踪条目清理仍会先显示审阅清单。文件夹操作立即生效。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("启动音量").font(.headline)
            Slider(value: $draft.startupVolume, in: 0...1, step: 0.05) { Text("启动音量") }
                .labelsHidden()
                .accessibilityValue("\(Int((draft.startupVolume * 100).rounded()))%")
            Text(draft.startupVolume, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            Text("下次启动时使用此音量。应用启动后不会自动播放歌曲。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func restoreDefaults() {
        let defaults = AppPreferences()
        switch tab {
        case .general:
            draft.appearance = defaults.appearance
            draft.showsMenuBarPlayer = defaults.showsMenuBarPlayer
        case .playback:
            draft.crossfadeEnabled = defaults.crossfadeEnabled
            draft.crossfadeDuration = defaults.crossfadeDuration
            draft.defaultPlaybackMode = defaults.defaultPlaybackMode
        case .advanced:
            draft.startupVolume = defaults.startupVolume
        case .files:
            break
        }
    }
}

#Preview("设置 · 浅色") {
    SettingsView(controller: .preview(), library: nil)
        .preferredColorScheme(.light)
}

#Preview("设置 · 深色") {
    SettingsView(controller: .preview(), library: nil)
        .preferredColorScheme(.dark)
}

#Preview("设置 · 通用") {
    SettingsView(controller: .preview(), library: nil, initialTab: .general)
}

#Preview("设置 · 文件") {
    SettingsView(controller: .preview(), library: .preview(), initialTab: .files)
}

#Preview("设置 · 高级") {
    SettingsView(controller: .preview(), library: nil, initialTab: .advanced)
}
