import SwiftUI

struct ArtworkView: View {
    let track: Track?
    var size: CGFloat = 44
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(size > 100 ? .largeTitle : .title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: track?.artworkPath) {
            image = nil
            guard let path = track?.artworkPath else { return }
            let data = await ArtworkCache.loader.data(at: path)
            guard !Task.isCancelled, let data else { return }
            image = NSImage(data: data)
        }
    }
}

struct SoundWaveView: View {
    var isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: !isPlaying || reduceMotion)) { context in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    let phase = context.date.timeIntervalSinceReferenceDate * 5 + Double(index) * 1.7
                    Capsule().fill(.tint)
                        .frame(width: 3, height: isPlaying && !reduceMotion ? 5 + 13 * abs(sin(phase)) : 5)
                }
            }
        }
        .frame(width: 20, height: 22)
        .accessibilityLabel(isPlaying ? "正在播放" : "已暂停")
    }
}

#Preview { HStack { ArtworkView(track: SPXData.tracks[0]); SoundWaveView(isPlaying: true) }.padding() }
