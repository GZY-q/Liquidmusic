import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum ArtworkCacheError: LocalizedError {
    case invalidImage
    case imageTooLarge
    case encodingFailed
    var errorDescription: String? {
        switch self {
        case .invalidImage: "封面图片损坏，已使用默认封面。"
        case .imageTooLarge: "封面尺寸过大，已使用默认封面。"
        case .encodingFailed: "封面缩略图保存失败，已使用默认封面。"
        }
    }
}

// 文件以内容哈希命名，只添加缓存文件，不覆盖已有文件。
actor ArtworkCache {
    static let loader = ArtworkCache(directory: nil)
    private let directory: URL?
    private let memory = NSCache<NSString, NSData>()

    init(directory: URL?) {
        self.directory = directory
        memory.countLimit = 160
        // 展示端另有解码缩略图缓存，压缩数据只保留较小的热缓存。
        memory.totalCostLimit = 8 * 1024 * 1024
    }

    func store(_ data: Data) throws -> String? {
        guard let directory else { return nil }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent("\(hash)-512-v1.jpg")
        if FileManager.default.fileExists(atPath: file.path) { return file.path }
        guard data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ArtworkCacheError.invalidImage
        }
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
           width.doubleValue * height.doubleValue > 200_000_000 {
            throw ArtworkCacheError.imageTooLarge
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ArtworkCacheError.invalidImage
        }
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ArtworkCacheError.encodingFailed
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ArtworkCacheError.encodingFailed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path) {
            do { try (buffer as Data).write(to: file, options: .withoutOverwriting) }
            catch let error as CocoaError where error.code == .fileWriteFileExists { }
        }
        return file.path
    }

    func data(at path: String) -> Data? {
        if let cached = memory.object(forKey: path as NSString) { return cached as Data }
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        memory.setObject(bytes as NSData, forKey: path as NSString, cost: bytes.count)
        return bytes
    }
}
