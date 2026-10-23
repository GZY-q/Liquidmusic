import SwiftUI

struct ArtworkView: View {
    private let paths: [String]
    private let size: CGFloat
    private let loadArtwork: ArtworkDataLoader?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.artworkDataLoader) private var inheritedLoader
    @State private var loading = ArtworkLoadingState()

    init(track: Track?, size: CGFloat = 44, loadArtwork: ArtworkDataLoader? = nil) {
        self.init(paths: track?.artworkPath.map { [$0] } ?? [], size: size, loadArtwork: loadArtwork)
    }

    init(paths: [String], size: CGFloat = 44, loadArtwork: ArtworkDataLoader? = nil) {
        self.paths = paths
        self.size = size
        self.loadArtwork = loadArtwork
    }

    private var pixelSize: Int { min(512, max(1, Int(ceil(size * displayScale)))) }

    private struct ArtworkRequest: Equatable {
        let paths: [String]
        let pixels: Int
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            // 新任务尚未调度时也不显示上一组候选的旧图。
            if loading.paths == paths, let image = loading.image {
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
        .task(id: ArtworkRequest(paths: paths, pixels: pixelSize)) {
            await loading.load(paths: paths, maximumPixelSize: pixelSize, using: loadArtwork ?? inheritedLoader)
        }
        .onDisappear { loading.cancel() }
    }
}

private struct ArtworkDataLoaderKey: EnvironmentKey {
    static let defaultValue: ArtworkDataLoader = ArtworkLoadingState.cachedData
}

extension EnvironmentValues {
    // 预览注入同时覆盖详情歌曲行，避免模拟封面路径触发真实磁盘读取。
    var artworkDataLoader: ArtworkDataLoader {
        get { self[ArtworkDataLoaderKey.self] }
        set { self[ArtworkDataLoaderKey.self] = newValue }
    }
}

struct SoundWaveView: View {
    var isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if isPlaying && !reduceMotion {
                // 装饰声波不需要显示刷新率驱动；暂停时彻底移除时间线。
                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                    bars(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                bars(at: nil)
            }
        }
        .frame(width: 20, height: 22)
        .accessibilityLabel(isPlaying ? "正在播放" : "已暂停")
    }

    private func bars(at time: TimeInterval?) -> some View {
        // 在固定画布内绘制，波形变化不再修改子视图高度或触发表格行布局。
        Canvas { context, size in
            for index in 0..<4 {
                let height = time.map { 5 + 13 * abs(sin($0 * 5 + Double(index) * 1.7)) } ?? 5
                let rect = CGRect(x: Double(index) * 5, y: (size.height - height) / 2, width: 3, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.accentColor))
            }
        }
        .frame(width: 20, height: 22)
    }
}

#Preview { HStack { ArtworkView(track: SPXData.tracks[0]); SoundWaveView(isPlaying: true) }.padding() }

#Preview("封面候选回退") {
    HStack {
        ArtworkView(paths: ["/preview/missing", "/preview/broken", "/preview/valid"], size: 144,
                    loadArtwork: SPXArtwork.loader)
        ArtworkView(paths: [], size: 144, loadArtwork: SPXArtwork.loader)
    }.padding()
}
