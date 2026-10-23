import Foundation
import CryptoKit
import ImageIO

// 解码在独立 actor 上串行完成，同一内容和尺寸共享像素，避免列表行重复解码。
actor ArtworkThumbnailCache {
    static let shared = ArtworkThumbnailCache()
    private let images = NSCache<NSString, CGImage>()

    init() {
        images.countLimit = 160
        images.totalCostLimit = 16 * 1024 * 1024
    }

    func image(data: Data, maximumPixelSize: Int) -> CGImage? {
        guard !Task.isCancelled, data.count <= 20 * 1024 * 1024 else { return nil }
        let size = min(512, max(1, maximumPixelSize))
        // 以内容为键，注入加载器或同路径文件更新也不会误用旧图。
        let hash = Data(SHA256.hash(data: data)).base64EncodedString()
        let key = "\(hash)-\(size)" as NSString
        if let image = images.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithData(data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              !Task.isCancelled else { return nil }
        images.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}
