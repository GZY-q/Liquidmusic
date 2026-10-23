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
    var loadArtwork: ArtworkDataLoader = ArtworkLoadingState.cachedData

    var body: some View {
        VStack(spacing: 0) {
            if model.trackCount > 0 {
                HStack(spacing: 12) {
                    if let scope = model.scope {
                        Text(scope.subtitle).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text("\(model.result.tracks.count) 首歌曲").foregroundStyle(.secondary)
                    if model.usesRankedOrder {
                        Text(model.section == .recentlyAdded ? "按添加时间" : model.section == .mostPlayed ? "按播放次数" : "按最近播放时间")
                            .foregroundStyle(.tertiary)
                    }
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
            ToolbarItemGroup(placement: .navigation) {
                Button("返回", systemImage: "chevron.left", action: model.goBack)
                    .disabled(!model.canGoBack).help("返回上一个视图")
                    .keyboardShortcut("[", modifiers: .command)
                Button("前进", systemImage: "chevron.right", action: model.goForward)
                    .disabled(!model.canGoForward).help("前进到下一个视图")
                    .keyboardShortcut("]", modifiers: .command)
            }
            if model.canChangeDisplayMode {
                ToolbarItem(placement: .primaryAction) {
                    Picker("视图", selection: $model.displayMode) {
                        ForEach(LibraryDisplayMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                        }
                    }.pickerStyle(.segmented).labelStyle(.iconOnly).frame(width: 76)
                        .help("切换歌曲列表或专辑网格")
                        .accessibilityIdentifier("library.displayMode")
                }
            }
            if model.showsSongs && model.trackCount > 0 && !model.usesRankedOrder {
                ToolbarItem(placement: .primaryAction) {
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
        .environment(\.artworkDataLoader, loadArtwork)
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
        } else if model.result.tracks.isEmpty && model.section?.isSmart == true {
            ContentUnavailableView("还没有播放记录", systemImage: model.section?.symbol ?? "clock",
                                   description: Text("播放资料库中的歌曲后，会自动显示在这里。"))
        } else if model.showsSongs {
            VStack(spacing: 0) {
                if case .album(let album) = model.scope {
                    AlbumHeaderView(album: album, paths: model.result.albumArtworkCandidates.map(\.cachePath),
                                    loadArtwork: loadArtwork)
                    Divider()
                }
                SongsTable(model: model, playback: playback)
            }
        } else {
            switch model.section {
            case .albums, .songs, .allMusic, .recentlyAdded, .recentlyPlayed, .mostPlayed, nil:
                AlbumsView(albums: model.result.albums, onOpen: model.openAlbum, loadArtwork: loadArtwork)
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

#Preview("封面详情·窄窗") {
    NavigationStack {
        LibraryView(model: .preview(section: .albums, scope: .album(AlbumIdentity(SPXArtwork.tracks[0])),
                                    tracks: SPXArtwork.tracks),
                    playback: PlaybackController(connectSystemMedia: false), loadArtwork: SPXArtwork.loader)
    }.frame(width: 400, height: 520)
}
