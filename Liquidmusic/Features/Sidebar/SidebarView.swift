import SwiftUI

struct SidebarView: View {
    @Binding var selection: LibrarySection?
    @Binding var searchText: String
    var trackCount: Int
    var searchRequest = 0
    @FocusState private var isSearchFocused: Bool
    @State private var libraryExpanded = true
    @State private var playlistsExpanded = true
    @State private var smartExpanded = true

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
                Section("资料库", isExpanded: $libraryExpanded) {
                    ForEach(LibrarySection.librarySections) { section in
                        SidebarRow(section: section, isSelected: selection == section).tag(section)
                    }
                }
                Section("播放列表", isExpanded: $playlistsExpanded) {
                    SidebarRow(section: .allMusic, isSelected: selection == .allMusic).tag(LibrarySection.allMusic)
                }
                Section("智能列表", isExpanded: $smartExpanded) {
                    ForEach(LibrarySection.smartSections) { section in
                        SidebarRow(section: section, isSelected: selection == section).tag(section)
                    }
                }
            }.listStyle(.sidebar)
            Text("\(trackCount) 首歌曲 · 本地资料库")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
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

private struct SidebarRow: View {
    let section: LibrarySection
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        Label {
            Text(section.rawValue).fontWeight(isSelected ? .semibold : .regular)
        } icon: {
            Image(systemName: section.symbol).foregroundStyle(.tint)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isHovering && !isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .onHover { isHovering = $0 }
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

#Preview { SidebarView(selection: .constant(.songs), searchText: .constant(""), trackCount: 128).frame(width: 220, height: 600) }
