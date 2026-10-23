import SwiftUI

struct NowPlayingView: View {
    @Bindable var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var showsLyrics = false

    var body: some View {
        GeometryReader { geometry in
            let artworkSize = max(120, min(320, geometry.size.width - 96, geometry.size.height - 360))
            VStack(spacing: 14) {
                HStack {
                    Text("正在播放").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction).help("关闭正在播放（Esc）")
                }
                ArtworkView(track: playback.currentTrack, size: artworkSize)
                    .shadow(color: Color.primary.opacity(0.15), radius: 20, y: 12)
                VStack(spacing: 6) {
                    Text(playback.currentTrack?.title ?? "未在播放")
                        .font(.title).bold().lineLimit(2).textSelection(.enabled)
                    Text(playback.currentTrack?.artist ?? "选择一首歌曲开始聆听")
                        .font(.title3).foregroundStyle(.secondary).lineLimit(1)
                    Text(playback.currentTrack?.album ?? "")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }.multilineTextAlignment(.center)
                VStack(spacing: 2) {
                    PlaybackProgressView(playback: playback, showsTimeLabels: true, controlSize: .regular)
                    HStack(spacing: 24) {
                        Button("上一首", systemImage: "backward.end.fill", action: playback.previous)
                            .disabled(!playback.canSkipPrevious)
                        Button(playback.wantsToPlay ? "暂停" : "播放",
                               systemImage: playback.wantsToPlay ? "pause.fill" : "play.fill", action: playback.toggle)
                            .disabled(!playback.canToggle).controlSize(.extraLarge)
                        Button("下一首", systemImage: "forward.end.fill", action: playback.next)
                            .disabled(!playback.canSkipNext)
                    }
                    .font(.title2).labelStyle(.iconOnly).buttonStyle(.glass).controlSize(.large)
                    .padding(.top, 12)
                }.frame(maxWidth: 400)
                HStack(spacing: 18) {
                    Menu("播放模式", systemImage: playback.mode.symbol) {
                        Picker("播放模式", selection: $playback.mode) {
                            ForEach(PlaybackMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }.labelStyle(.iconOnly).menuIndicator(.hidden).fixedSize().help(playback.mode.rawValue)
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $playback.volume, in: 0...1).accessibilityLabel("音量")
                        .accessibilityValue("\(Int(playback.volume * 100))%")
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    Button("显示歌词", systemImage: "quote.bubble") { showsLyrics = true }
                        .labelStyle(.iconOnly).buttonStyle(.glass).disabled(playback.currentTrack == nil)
                }.frame(maxWidth: 320)
            }
            .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backdrop(size: max(geometry.size.width, geometry.size.height)) }
        }
        .clipped()
        .frame(minWidth: 460, idealWidth: 600, maxWidth: 760, minHeight: 520, idealHeight: 660, maxHeight: 900)
        .accessibilityIdentifier("player.nowPlayingPanel")
        .sheet(isPresented: $showsLyrics) { LyricsView(playback: playback) }
    }

    private func backdrop(size: CGFloat) -> some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency && contrast != .increased {
                // 模糊当前封面自然保留主色，不另行提色、不引入动画计时器。
                ArtworkView(track: playback.currentTrack, size: size)
                    .blur(radius: 60).opacity(0.35)
                LinearGradient(colors: [Color(nsColor: .windowBackgroundColor).opacity(0.15),
                                        Color(nsColor: .windowBackgroundColor).opacity(0.9)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

#Preview("正在播放·浅色") {
    NowPlayingView(playback: .preview(track: SPXArtwork.tracks[1]))
        .environment(\.artworkDataLoader, SPXArtwork.loader)
        .frame(width: 600, height: 660).preferredColorScheme(.light)
}

#Preview("正在播放·深色紧凑") {
    NowPlayingView(playback: .preview(track: SPXArtwork.tracks[1]))
        .environment(\.artworkDataLoader, SPXArtwork.loader)
        .frame(width: 460, height: 520).preferredColorScheme(.dark)
}
