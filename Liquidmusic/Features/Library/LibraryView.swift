import SwiftUI

struct LibraryView: View {
    @Bindable var model: LibraryViewModel
    let playback: PlaybackController
    var connection: LibraryConnectionState?
    var isImporting = false
    var hasFolders = false
    var addFolder: (() -> Void)?
    var manageFolders: (() -> Void)?
    var retry: (() -> Void)?
    var openAudioFile: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            if model.trackCount > 0 {
                HStack(spacing: 12) {
                    if model.scope != nil {
                        Button("返回", systemImage: "chevron.left", action: model.goBack)
                            .buttonStyle(.borderless)
                    }
                    if let scope = model.scope {
                        Text(scope.subtitle).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text("\(model.result.tracks.count) 首歌曲").foregroundStyle(.secondary)
                    Spacer()
                    if model.isQuerying {
                        ProgressView().controlSize(.small).accessibilityLabel("正在更新资料库视图")
                    }
                }.font(.callout).padding(.horizontal, 20).padding(.vertical, 10)
                Divider()
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(model.title)
        .toolbar {
            if model.showsSongs && model.trackCount > 0 {
                Menu("排序", systemImage: "arrow.up.arrow.down") {
                    Picker("排序依据", selection: Binding(
                        get: { model.sortOrder.first?.field ?? .title },
                        set: { model.sortOrder = [TrackSort(field: $0, order: model.sortOrder.first?.order ?? .forward)] }
                    )) {
                        ForEach(TrackSortField.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("降序", isOn: Binding(
                        get: { model.sortOrder.first?.order == .reverse },
                        set: { model.sortOrder = [TrackSort(field: model.sortOrder.first?.field ?? .title, order: $0 ? .reverse : .forward)] }
                    ))
                }.help("对当前歌曲列表排序")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.trackCount == 0 {
            emptyLibrary
        } else if model.result.tracks.isEmpty && model.isQuerying {
            ProgressView("正在更新资料库视图…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.result.scopeCount == 0 && model.scope != nil {
            ContentUnavailableView {
                Label("这个分类已没有歌曲", systemImage: "music.note")
            } description: {
                Text("资料库可能已更新，返回后可选择其他专辑或艺术家。")
            } actions: { Button("返回", action: model.goBack) }
        } else if model.result.tracks.isEmpty && !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView {
                Label("没有搜索结果", systemImage: "magnifyingglass")
            } description: {
                Text("没有与「\(model.query)」匹配的歌曲、艺术家或专辑。")
            } actions: { Button("清除搜索") { model.query = "" } }
        } else if model.showsSongs {
            SongsTable(model: model, playback: playback)
        } else {
            switch model.section {
            case .albums:
                AlbumsView(albums: model.result.albums, onOpen: model.openAlbum)
            case .artists:
                ArtistsView(artists: model.result.artists, onOpen: model.openArtist)
            case .playlists:
                List {
                    HStack {
                        Button { model.section = .allMusic } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note.list").font(.title2).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("所有音乐").font(.headline)
                                    Text("\(model.result.tracks.count) 首歌曲").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            default: EmptyView()
            }
        }
    }

    @ViewBuilder private var emptyLibrary: some View {
        if case .failed(let message) = connection {
            ContentUnavailableView {
                Label("无法读取资料库", systemImage: "exclamationmark.triangle")
            } description: { Text(message) } actions: {
                if let retry { Button("重试", action: retry) }
            }
        } else if isImporting || connection == .loading || connection == .idle {
            ProgressView(isImporting ? "正在导入音乐…" : "正在读取资料库…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(hasFolders ? "音乐文件夹中还没有可播放歌曲" : "从一首歌开始", systemImage: "music.note")
            } description: {
                Text(hasFolders ? "可在音乐文件夹中重新扫描、查看导入报告或检查授权，也可以打开一个音频文件。" : "添加音乐文件夹，或打开一个音频文件，开始聆听你的音乐。")
            } actions: {
                if hasFolders, let manageFolders { Button("管理音乐文件夹…", action: manageFolders) }
                if let addFolder { Button("添加音乐文件夹…", action: addFolder) }
                Button("打开音频文件…", action: openAudioFile)
            }
        }
    }
}

#Preview("歌曲") {
    NavigationStack {
        LibraryView(model: .preview(), playback: PlaybackController(connectSystemMedia: false))
    }.frame(width: 850, height: 450)
}

#Preview("专辑详情") {
    NavigationStack {
        LibraryView(model: .preview(section: .albums, scope: .album(AlbumIdentity(SPXData.tracks[0]))),
                    playback: PlaybackController(connectSystemMedia: false))
    }.frame(width: 850, height: 450)
}

#Preview("搜索无结果") {
    LibraryView(model: .preview(query: "不存在的曲目"), playback: PlaybackController(connectSystemMedia: false))
        .frame(width: 700, height: 400)
}

#Preview("播放列表") {
    LibraryView(model: .preview(section: .playlists), playback: PlaybackController(connectSystemMedia: false))
        .frame(width: 700, height: 400)
}

#Preview("首次导入") {
    LibraryView(model: LibraryViewModel(), playback: PlaybackController(connectSystemMedia: false), connection: .ready, addFolder: {})
        .frame(width: 700, height: 400)
}

#Preview("正在导入") {
    LibraryView(model: LibraryViewModel(), playback: PlaybackController(connectSystemMedia: false), connection: .ready, isImporting: true)
        .frame(width: 700, height: 400)
}

#Preview("资料库失败") {
    LibraryView(model: LibraryViewModel(), playback: PlaybackController(connectSystemMedia: false), connection: .failed("无法打开资料库，请检查磁盘空间后重试。"), retry: {})
        .frame(width: 700, height: 400)
}
