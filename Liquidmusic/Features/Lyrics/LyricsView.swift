import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    let playback: PlaybackController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let track = playback.currentTrack {
                LyricsTrackView(track: track, playback: playback, close: { dismiss() })
                    .id(track.path)
            } else {
                ContentUnavailableView("未在播放", systemImage: "music.note", description: Text("选择一首歌曲查看歌词。"))
                    .overlay(alignment: .topTrailing) {
                        Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction).padding()
                    }
            }
        }
        .frame(width: 600, height: 460)
        .accessibilityIdentifier("lyrics.screen")
    }
}

private struct LyricsTrackView: View {
    let track: Track
    let playback: PlaybackController
    let close: () -> Void
    var automaticallyLoad = true
    @State var model = LyricsModel()
    @State private var showsImporter = false
    @State private var showsArtwork = false
    @State private var selectedFile: URL?
    @State private var revision = 0
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { showsArtwork = true } label: { ArtworkView(track: track, size: 52) }
                    .buttonStyle(.plain).accessibilityLabel("显示专辑封面").help("显示专辑封面")
                    .popover(isPresented: $showsArtwork) {
                        ArtworkView(track: track, size: 280).padding(20)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.headline).lineLimit(1).help(track.title)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("关闭", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly).keyboardShortcut(.cancelAction).help("关闭歌词")
            }.padding(20)
            Divider()
            lyricsContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text(model.document?.source ?? "本地歌词")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if selectedFile != nil {
                    Button("自动查找") { selectedFile = nil; revision += 1 }
                }
                Button("重新读取") { revision += 1 }.disabled(model.isLoading)
                Button("选择歌词…") { showsImporter = true }
                    .help("为本次查看选择 LRC 或纯文本歌词，不修改音频文件")
            }.padding(.horizontal, 20).padding(.top, 12)
            HStack(spacing: 20) {
                TransportControls(playback: playback, spacing: 12)
                PlaybackProgressView(playback: playback)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .task(id: revision) {
            if automaticallyLoad { await model.load(track: track, file: selectedFile) }
        }
        .onDisappear { model.cancel() }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]) { result in
            // 文件面板打开期间切歌时，不把选择结果应用到下一首。
            guard playback.currentTrack?.path == track.path else { return }
            switch result {
            case .success(let url): selectedFile = url; revision += 1
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .alert("无法打开歌词", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("好", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
    }

    @ViewBuilder private var lyricsContent: some View {
        if model.isLoading {
            ProgressView("正在读取歌词…")
        } else if let document = model.document {
            if document.lines.isEmpty {
                ScrollView {
                    Text(document.plainText).font(.title3).lineSpacing(10)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }
            } else {
                LyricsTimeline(document: document, playback: playback, trackPath: track.path)
            }
        } else {
            ContentUnavailableView(model.error == nil ? "暂无歌词" : "歌词无法读取",
                                   systemImage: "text.quote",
                                   description: Text(model.error ?? "读取同名 LRC 文件或音频内嵌歌词。也可以点击“选择歌词…”打开本地歌词文件。"))
        }
    }
}

private struct LyricsTimeline: View {
    let document: LyricsDocument
    let playback: PlaybackController
    let trackPath: String

    var body: some View {
        SyncedLyricsView(document: document, activeID: document.activeLine(at: playback.elapsed),
                         duration: playback.duration, canSeek: playback.canSeek) { time in
            guard playback.currentTrack?.path == trackPath else { return }
            playback.seek(to: time)
        }
    }
}

private struct SyncedLyricsView: View {
    let document: LyricsDocument
    let activeID: Int?
    let duration: Double
    let canSeek: Bool
    let seek: (Double) -> Void
    @State private var followsPlayback = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(document.lines) { line in
                        Button { seek(line.time) } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.title2).fontWeight(line.id == activeID ? .bold : .regular)
                                .foregroundStyle(line.id == activeID ? .primary : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSeek || line.time > duration)
                        .accessibilityLabel(line.text.isEmpty ? "间奏" : line.text)
                        .accessibilityValue(line.id == activeID ? "当前歌词" : "")
                        .help("播放到这一句")
                        .id(line.id)
                    }
                }.padding(24)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { followsPlayback = false }
            }
            .onChange(of: activeID, initial: true) { _, id in
                if followsPlayback, let id {
                    withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .onChange(of: followsPlayback) { _, follows in
                if follows, let activeID { proxy.scrollTo(activeID, anchor: .center) }
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                Toggle("跟随播放", isOn: $followsPlayback).toggleStyle(.checkbox)
                    .font(.caption).padding(10).background(.regularMaterial, in: .capsule).padding(8)
            }
        }
    }
}

private let previewLyrics = LyricsDocument(lines: [
    LyricLine(id: 0, time: 0, text: "夜色落在窗前"),
    LyricLine(id: 1, time: 8, text: "沿着微光，慢慢向前"),
    LyricLine(id: 2, time: 16, text: "让这一刻停在耳边"),
    LyricLine(id: 3, time: 24, text: "远方的风，带来新的明天")
], source: "示例歌词.lrc")

#Preview("同步歌词") {
    LyricsTrackView(track: SPXData.tracks[0], playback: PlaybackController(connectSystemMedia: false),
                    close: {}, automaticallyLoad: false, model: LyricsModel(document: previewLyrics))
        .frame(width: 600, height: 460)
}

#Preview("暂无歌词") {
    LyricsTrackView(track: SPXData.tracks[0], playback: PlaybackController(connectSystemMedia: false),
                    close: {}, automaticallyLoad: false).frame(width: 600, height: 460)
}
