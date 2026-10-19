import SwiftUI

struct PlayerBar: View {
    @Bindable var playback: PlaybackController
    @Binding var showsQueue: Bool
    var usesQueuePopover = false
    @State private var showsArtwork = false
    @State private var showsVolume = false
    @State private var hoversArtwork = false
    @FocusState private var isVolumeFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                controls.background(.background, in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(.primary, lineWidth: 1) }
            } else {
                controls.glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
        .padding(10)
        .background(.background)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            wideControls
            compactControls
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var wideControls: some View {
        HStack(spacing: 24) {
            currentTrack
                .frame(minWidth: 160, idealWidth: 230, maxWidth: 290)
            VStack(spacing: 4) {
                TransportControls(playback: playback)
                PlaybackProgressView(playback: playback)
            }
            .frame(minWidth: 210, maxWidth: .infinity)
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                volumeSlider.frame(width: 78)
                modeMenu
                queueButton
            }.fixedSize(horizontal: true, vertical: false)
        }
    }

    private var compactControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                currentTrack.frame(maxWidth: .infinity, alignment: .leading)
                TransportControls(playback: playback)
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
                modeMenu
                queueButton
            }
            PlaybackProgressView(playback: playback)
        }
    }

    private var currentTrack: some View {
        Button { showsArtwork.toggle() } label: {
            HStack(spacing: 10) {
                ArtworkView(track: playback.currentTrack)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playback.currentTrack?.title ?? "未在播放").font(.headline).lineLimit(1)
                    Text(playback.status == .playing ? (playback.currentTrack?.artist ?? "") : playback.statusText)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .background(hoversArtwork ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("显示专辑封面")
        .onHover { hoversArtwork = $0 }
        .accessibilityLabel("显示专辑封面")
        .accessibilityValue(playback.currentTrack.map { "\($0.title)，\($0.artist)" } ?? "未在播放")
        .disabled(playback.currentTrack == nil)
        .popover(isPresented: $showsArtwork) { NowPlayingView(playback: playback) }
    }

    private var volumeSlider: some View {
        Slider(value: $playback.volume, in: 0...1)
            .accessibilityLabel("音量")
            .accessibilityValue("\(Int(playback.volume * 100))%")
    }

    private var modeMenu: some View {
        Menu("播放模式") {
            Picker("播放模式", selection: $playback.mode) {
                ForEach(PlaybackMode.allCases) { mode in Label(mode.rawValue, systemImage: mode.symbol).tag(mode) }
            }
        }
        .menuStyle(.borderlessButton).fixedSize().help(playback.mode.rawValue)
        .accessibilityLabel("播放模式").accessibilityValue(playback.mode.rawValue)
        .accessibilityIdentifier("player.mode")
    }

    private var queueButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) { showsQueue.toggle() }
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
    var body: some View {
        HStack(spacing: 22) {
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

struct NowPlayingView: View {
    let playback: PlaybackController
    var body: some View {
        VStack(spacing: 18) {
            ArtworkView(track: playback.currentTrack, size: 280)
            VStack(spacing: 5) {
                Text(playback.currentTrack?.title ?? "未在播放").font(.title2).bold()
                Text(playback.currentTrack?.artist ?? "").foregroundStyle(.secondary)
                Text(playback.currentTrack?.album ?? "").font(.caption).foregroundStyle(.tertiary)
            }
            TransportControls(playback: playback)
        }.padding(24).frame(width: 340)
    }
}

#Preview { PlayerBar(playback: PlaybackController(connectSystemMedia: false), showsQueue: .constant(false)).frame(width: 1000) }

#Preview("紧凑播放条") {
    PlayerBar(playback: PlaybackController(connectSystemMedia: false), showsQueue: .constant(true)).frame(width: 640)
}
