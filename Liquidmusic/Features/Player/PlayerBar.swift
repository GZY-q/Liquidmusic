import SwiftUI

struct PlayerBar: View {
    @Bindable var playback: PlaybackController
    @Binding var showsQueue: Bool
    var usesQueuePopover = false
    @State private var showsLyrics = false
    @State private var showsNowPlaying = false
    @State private var showsVolume = false
    @State private var hoversArtwork = false
    @FocusState private var isVolumeFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                controls.background(.background, in: .capsule)
                    .overlay { Capsule().stroke(.primary, lineWidth: 1) }
            } else {
                controls.glassEffect(.regular, in: .capsule)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            TransportControls(playback: playback, spacing: 12)
                .fixedSize()
            VStack(spacing: 0) {
                currentTrack
                PlaybackProgressView(playback: playback)
            }
            .frame(minWidth: 60, maxWidth: .infinity)
            HStack(spacing: 12) {
                modeMenu
                lyricsButton
                queueButton
                volumeButton
            }.fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .sheet(isPresented: $showsNowPlaying) { NowPlayingView(playback: playback) }
        .sheet(isPresented: $showsLyrics) { LyricsView(playback: playback) }
    }

    private var volumeButton: some View {
        Button("音量", systemImage: "speaker.wave.2.fill") { showsVolume.toggle() }
            .labelStyle(.iconOnly).buttonStyle(.borderless).help("调整音量")
            .popover(isPresented: $showsVolume) {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                        volumeSlider
                    }
                    Button("完成") { showsVolume = false }.keyboardShortcut(.cancelAction)
                }
                .padding().frame(width: 220)
                .focusable().focused($isVolumeFocused)
                .onExitCommand { showsVolume = false }
                .task {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    isVolumeFocused = true
                }
            }
    }

    private var currentTrack: some View {
        Button { showsNowPlaying = true } label: {
            HStack(spacing: 10) {
                ArtworkView(track: playback.currentTrack, size: 32)
                Text(playback.currentTrack?.title ?? "未在播放")
                    .font(.headline).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .background(hoversArtwork ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(playback.currentTrack.map { "\($0.title) · \($0.artist)\n展开正在播放" } ?? "展开正在播放")
        .onHover { hoversArtwork = $0 }
        .accessibilityLabel("展开正在播放")
        .accessibilityValue(playback.currentTrack.map { "\($0.title)，\($0.artist)" } ?? "未在播放")
        .disabled(playback.currentTrack == nil)
        .accessibilityIdentifier("player.nowPlaying")
    }

    private var lyricsButton: some View {
        Button("显示歌词", systemImage: "quote.bubble") { showsLyrics = true }
            .labelStyle(.iconOnly).buttonStyle(.borderless).help("显示本地歌词")
            .disabled(playback.currentTrack == nil)
            .accessibilityIdentifier("player.lyrics")
    }

    private var volumeSlider: some View {
        Slider(value: $playback.volume, in: 0...1)
            .accessibilityLabel("音量")
            .accessibilityValue("\(Int(playback.volume * 100))%")
    }

    private var modeMenu: some View {
        Menu {
            Picker("播放模式", selection: $playback.mode) {
                ForEach(PlaybackMode.allCases) { mode in Label(mode.rawValue, systemImage: mode.symbol).tag(mode) }
            }
        } label: {
            Label("播放模式", systemImage: "ellipsis").labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(playback.mode.rawValue)
        .accessibilityLabel("播放模式").accessibilityValue(playback.mode.rawValue)
        .accessibilityIdentifier("player.mode")
    }

    private var queueButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) { showsQueue.toggle() }
        } label: {
            Image(systemName: "list.bullet").foregroundStyle(showsQueue ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless).help("正在播放队列")
        .accessibilityLabel("正在播放队列").accessibilityValue(showsQueue ? "已展开" : "已收起")
        .accessibilityIdentifier("player.queue")
        .popover(isPresented: Binding(
            get: { usesQueuePopover && showsQueue },
            set: { if usesQueuePopover { showsQueue = $0 } }
        )) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("完成") { showsQueue = false }.keyboardShortcut(.cancelAction)
                }.padding(12)
                QueueView(playback: playback)
            }.frame(width: 320, height: 440)
        }
    }
}

struct TransportControls: View {
    let playback: PlaybackController
    var spacing: CGFloat = 22
    var body: some View {
        HStack(spacing: spacing) {
            Button("上一首", systemImage: "backward.end.fill", action: playback.previous)
                .disabled(!playback.canSkipPrevious).help("上一首")
            Button(playback.wantsToPlay ? "暂停" : "播放", systemImage: playback.wantsToPlay ? "pause.fill" : "play.fill", action: playback.toggle)
                .font(.title2).frame(width: 28).disabled(!playback.canToggle)
                .help(playback.wantsToPlay ? "暂停" : "播放")
            Button("下一首", systemImage: "forward.end.fill", action: playback.next)
                .disabled(!playback.canSkipNext).help("下一首")
        }
        .labelStyle(.iconOnly).buttonStyle(.borderless)
        .disabled(playback.currentTrack == nil)
    }
}

#Preview { PlayerBar(playback: PlaybackController(connectSystemMedia: false), showsQueue: .constant(false)).frame(width: 1000) }

#Preview("紧凑播放条") {
    PlayerBar(playback: PlaybackController(connectSystemMedia: false), showsQueue: .constant(true)).frame(width: 640)
}

#Preview("参考图·非空播放条") {
    PlayerBar(playback: .preview(track: SPXData.tracks[0]), showsQueue: .constant(false)).frame(width: 800)
}
