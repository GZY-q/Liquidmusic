import AppKit
import Observation

typealias ArtworkDataLoader = @Sendable (String) async -> Data?

// 只持有当前图片；压缩数据与解码像素分别由独立 actor 的共享缓存负责。
@MainActor @Observable
final class ArtworkLoadingState {
    private(set) var paths: [String] = []
    private(set) var image: NSImage?
    private(set) var resolvedPath: String?
    @ObservationIgnored private var generation = UUID()

    nonisolated static func cachedData(_ path: String) async -> Data? {
        await ArtworkCache.loader.data(at: path)
    }

    func load(paths: [String], maximumPixelSize: Int = 512, using loader: ArtworkDataLoader) async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        generation = request
        self.paths = paths
        image = nil
        resolvedPath = nil
        for path in paths {
            guard !Task.isCancelled, generation == request else { return }
            let data = await loader(path)
            guard !Task.isCancelled, generation == request else { return }
            if let data, let decoded = await ArtworkThumbnailCache.shared.image(data: data, maximumPixelSize: maximumPixelSize) {
                guard !Task.isCancelled, generation == request else { return }
                image = NSImage(cgImage: decoded, size: .zero)
                resolvedPath = path
                return
            }
        }
    }

    func cancel() {
        generation = UUID()
        paths = []
        image = nil
        resolvedPath = nil
    }
}
