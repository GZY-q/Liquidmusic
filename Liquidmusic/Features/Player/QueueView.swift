import SwiftUI

struct QueueView: View {
    let playback: PlaybackController
    var body: some View {
        QueueContents(queue: playback.queue, isPlaying: playback.isPlaying, onSelect: playback.jump)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct QueueContents: View {
    let queue: PlaybackQueue
    var isPlaying = false
    var onSelect: (QueueEntry) -> Void = { _ in }

    var body: some View {
        let upcoming = queue.upcomingEntries
        let history = Array(queue.historyEntries.reversed())
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("正在播放").font(.title2).bold()
                Text("\(queue.entries.count) 首歌曲 · \(queue.mode.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
            if queue.entries.isEmpty {
                ContentUnavailableView("队列为空", systemImage: "text.line.first.and.arrowtriangle.forward", description: Text("播放歌曲，或从歌曲菜单中选择“下一首播放”。"))
            } else {
                List {
                    Section("当前歌曲") {
                        if let entry = queue.currentEntry {
                            ZStack {
                                QueueRow(entry: entry, isCurrent: true, isPlaying: isPlaying) { onSelect(entry) }
                            }
                        }
                    }
                    Section {
                        if upcoming.isEmpty {
                            Text(queue.mode == .shuffle || queue.mode == .repeatAll ? "本轮已到末尾" : "没有接下来的歌曲")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        // 同一条目在回退后的前进路径中也可能多次出现，用访问位置区分行。
                        ForEach(Array(upcoming.enumerated()), id: \.offset) { _, entry in
                            // 显式容器保持原生 List 行结构，规避本机 Preview 的不透明行崩溃。
                            ZStack { QueueRow(entry: entry) { onSelect(entry) } }
                        }
                    } header: { Text("接下来") } footer: {
                        switch queue.mode {
                        case .repeatOne: Text("自动重复当前歌曲；手动下一首按此列表切换。")
                        case .repeatAll: Text("本轮结束后从列表开头继续播放。")
                        case .shuffle: Text("显示本轮剩余顺序，播完后重新洗牌。")
                        case .sequential: EmptyView()
                        }
                    }
                    if !history.isEmpty {
                        Section("播放历史") {
                            ForEach(Array(history.enumerated()), id: \.offset) { _, entry in
                                ZStack { QueueRow(entry: entry) { onSelect(entry) } }
                            }
                        }
                    }
                }.listStyle(.inset)
            }
        }.frame(minWidth: 230, idealWidth: 280, maxWidth: 340)
    }
}

private struct QueueRow: View {
    let entry: QueueEntry
    var isCurrent = false
    var isPlaying = false
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 10) {
                    ArtworkView(track: entry.track, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.track.title).lineLimit(1)
                        Text(entry.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isCurrent { SoundWaveView(isPlaying: isPlaying) }
                }.padding(.vertical, 3).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .help("播放「\(entry.track.title)」")
        .accessibilityLabel("\(isCurrent ? "当前歌曲，" : "")\(entry.track.title)，\(entry.track.artist)")
    }
}

struct MiniPlayerView: View {
    let playback: PlaybackController
    var showWindow: () -> Void
    var quit: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ArtworkView(track: playback.currentTrack, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(playback.currentTrack?.title ?? "Liquidmusic").font(.headline).lineLimit(1)
                    Text(playback.currentTrack?.artist ?? "你的音乐，随时相伴").foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            TransportControls(playback: playback)
            Text(playback.statusText).font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("打开 Liquidmusic", action: showWindow)
            Button("退出 Liquidmusic", action: quit).font(.caption)
        }.padding(20).frame(width: 300)
    }
}

#Preview { QueueView(playback: PlaybackController(connectSystemMedia: false)).frame(height: 500) }
#Preview("菜单栏") { MiniPlayerView(playback: PlaybackController(connectSystemMedia: false), showWindow: {}, quit: {}) }
#Preview("队列与历史") { QueueContents(queue: SPXData.queue).frame(height: 620) }
#Preview("随机队列") { QueueContents(queue: SPXData.shuffledQueue).frame(height: 620) }

private extension SPXData {
    static var queue: PlaybackQueue {
        var queue = PlaybackQueue(shuffleSeed: 1)
        queue.replace(with: tracks, startingAt: tracks[0])
        queue.advance()
        queue.insertNext(tracks[0])
        return queue
    }
    static var shuffledQueue: PlaybackQueue {
        var queue = queue
        queue.mode = .shuffle
        return queue
    }
}
