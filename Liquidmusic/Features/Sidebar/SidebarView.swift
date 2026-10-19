import SwiftUI

struct SidebarView: View {
    @Binding var selection: LibrarySection?
    @Binding var searchText: String
    var trackCount: Int
    var openAudioFile: () -> Void
    var searchRequest = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索资料库", text: $searchText).textFieldStyle(.plain)
                    .accessibilityLabel("搜索歌曲、艺术家或专辑")
                    .accessibilityIdentifier("library.search")
                    .focused($isSearchFocused)
                    .onExitCommand {
                        if searchText.isEmpty { isSearchFocused = false }
                        else { searchText = "" }
                    }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除搜索")
                }
            }
            .padding(8).background(.quaternary, in: .rect(cornerRadius: 8)).padding(12)
            List(selection: $selection) {
                Section("资料库") {
                    ForEach(LibrarySection.librarySections) { section in
                        Label(section.rawValue, systemImage: section.symbol).tag(section)
                    }
                }
                Section("播放列表") {
                    Label("所有音乐", systemImage: "music.note.list").tag(LibrarySection.allMusic)
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 10) {
                Text("\(trackCount) 首歌曲 · 本地资料库").font(.caption).foregroundStyle(.secondary)
                Button("打开音频文件…", systemImage: "folder.badge.plus", action: openAudioFile)
                    .buttonStyle(.borderless)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        .task(id: searchRequest) {
            guard searchRequest > 0 else { return }
            // 等侧边栏重新进入视图树后再聚焦；折叠期间设置 FocusState 会被系统丢弃。
            await Task.yield()
            guard !Task.isCancelled else { return }
            isSearchFocused = true
        }
    }
}

struct LibrarySearchActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

extension FocusedValues {
    var focusLibrarySearch: LibrarySearchActionKey.Value? {
        get { self[LibrarySearchActionKey.self] }
        set { self[LibrarySearchActionKey.self] = newValue }
    }
}

#Preview { SidebarView(selection: .constant(.songs), searchText: .constant(""), trackCount: 128, openAudioFile: {}).frame(width: 220, height: 600) }
