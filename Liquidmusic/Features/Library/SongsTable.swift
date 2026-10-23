import SwiftUI

struct SongsTable: View {
    @Bindable var model: LibraryViewModel
    let playback: PlaybackController
    @State private var selection = Set<Track.ID>()
    @State private var hoveredTrackID: Track.ID?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width >= 560 {
                    if model.usesRankedOrder { rankedTable }
                    else { table }
                } else { compactList }
            }
            .contextMenu(forSelectionType: Track.ID.self) { ids in
                Button("播放", systemImage: "play.fill") { model.play(ids, using: playback) }
                    .disabled(ids.isEmpty)
                Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    model.playNext(ids, using: playback)
                }.disabled(ids.isEmpty)
            } primaryAction: { ids in
                model.play(ids, using: playback)
            }
        }
        .onChange(of: model.result.tracks.map(\.id)) { _, ids in
            selection.formIntersection(ids)
            hoveredTrackID = nil
        }
        .accessibilityLabel("\(model.title)歌曲列表")
    }

    private var table: some View {
        Table(model.result.tracks, selection: $selection, sortOrder: $model.sortOrder) {
            TableColumn("标题", sortUsing: TrackSort(field: .title)) { track in
                titleCell(track)
            }.width(min: 180, ideal: 280)
            TableColumn("艺术家", sortUsing: TrackSort(field: .artist)) { track in
                Text(track.artist).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle()).onHover { hover($0, track: track) }
            }.width(min: 100, ideal: 160)
            TableColumn("专辑", sortUsing: TrackSort(field: .album)) { track in
                Text(track.album).lineLimit(1).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle()).onHover { hover($0, track: track) }
            }.width(min: 110, ideal: 180)
            TableColumn("时长", sortUsing: TrackSort(field: .duration)) { track in
                Text(track.durationText).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle()).onHover { hover($0, track: track) }
            }.width(65)
        }
        .tableStyle(.bordered)
        .alternatingRowBackgrounds(.enabled)
    }

    private var rankedTable: some View {
        // 智能列表采用固定排名，避免列标题显示与实际排名不一致的排序箭头。
        Table(model.result.tracks, selection: $selection) {
            TableColumn("标题") { titleCell($0) }.width(min: 180, ideal: 280)
            TableColumn("艺术家") { Text($0.artist).lineLimit(1) }.width(min: 100, ideal: 160)
            TableColumn("专辑") { Text($0.album).lineLimit(1).foregroundStyle(.secondary) }.width(min: 110, ideal: 180)
            TableColumn("时长") { track in
                Text(track.durationText).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }.width(65)
        }
        .tableStyle(.bordered).alternatingRowBackgrounds(.enabled)
    }

    private func titleCell(_ track: Track) -> some View {
        HStack(spacing: 10) {
            ArtworkView(track: track, size: 20)
                .overlay {
                    if hoveredTrackID == track.id {
                        Button { model.play([track.id], using: playback) } label: {
                            Image(systemName: "play.fill").frame(width: 20, height: 20)
                        }
                        .buttonStyle(.borderless)
                        .background(.regularMaterial, in: .rect(cornerRadius: 6))
                        .help("播放「\(track.title)」").accessibilityLabel("播放「\(track.title)」")
                    }
                }
            Text(track.title).lineLimit(1).help(track.title)
            Spacer(minLength: 0)
            if playback.currentTrack?.path == track.path { SoundWaveView(isPlaying: playback.isPlaying) }
        }
        .contentShape(Rectangle()).onHover { hover($0, track: track) }
    }

    private var compactList: some View {
        List(selection: $selection) {
            ForEach(model.result.tracks) { track in
                // 显式容器保持原生 List 的行标识，避免自定义不透明行的预览兼容问题。
                HStack(spacing: 10) {
                    Button { model.play([track.id], using: playback) } label: {
                        ArtworkView(track: track, size: 32)
                            .overlay {
                                if hoveredTrackID == track.id {
                                    Image(systemName: "play.fill").padding(8)
                                        .background(.regularMaterial, in: .rect(cornerRadius: 6))
                                }
                            }
                    }
                    .buttonStyle(.borderless).accessibilityLabel("播放「\(track.title)」")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).lineLimit(1)
                        Text("\(track.artist) · \(track.album)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if playback.currentTrack?.path == track.path { SoundWaveView(isPlaying: playback.isPlaying) }
                    Text(track.durationText).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.vertical, 4).contentShape(Rectangle())
                .onHover { hover($0, track: track) }
                .help("\(track.title)，\(track.artist)，\(track.album)，\(track.durationText)")
                .tag(track.id)
            }
        }
    }

    private func hover(_ isHovering: Bool, track: Track) {
        if isHovering { hoveredTrackID = track.id }
        else if hoveredTrackID == track.id { hoveredTrackID = nil }
    }
}

#Preview {
    SongsTable(model: .preview(), playback: PlaybackController(connectSystemMedia: false))
        .frame(width: 850, height: 420)
}

#Preview("紧凑列表") {
    SongsTable(model: .preview(), playback: PlaybackController(connectSystemMedia: false))
        .frame(width: 400, height: 420)
}

#Preview("一千首模拟歌曲") {
    SongsTable(model: .preview(tracks: SPXData.largeLibrary), playback: PlaybackController(connectSystemMedia: false))
        .frame(width: 850, height: 500)
}
