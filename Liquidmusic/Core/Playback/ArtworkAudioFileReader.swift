import Foundation

// 单文件适配器复用扫描标签与缓存规则；授权由 AppModel 持有，不另开数据库。
actor ArtworkAudioFileReader: AudioFileReading {
    private let reader: any AudioMetadataReading
    private let cacheDirectory: @Sendable () throws -> URL
    private var cache: ArtworkCache?

    init(reader: any AudioMetadataReading = AudioFileReader(),
         cacheDirectory: @escaping @Sendable () throws -> URL) {
        self.reader = reader
        self.cacheDirectory = cacheDirectory
    }

    func read(_ url: URL) async throws -> Track {
        try await readResult(url).track
    }

    func readResult(_ url: URL) async throws -> AudioFileReadResult {
        try Task.checkCancellation()
        let metadata = try await reader.readMetadata(url)
        try Task.checkCancellation()
        var result = AudioFileReadResult(track: metadata.track, warnings: metadata.warnings)
        if let data = metadata.artworkData {
            do {
                if cache == nil { cache = ArtworkCache(directory: try cacheDirectory()) }
                result.track.artworkPath = try await cache?.store(data)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                result.track.artworkPath = nil
                result.warnings.append("封面未能缓存，已使用默认封面：\(error.localizedDescription)")
            }
        }
        try Task.checkCancellation()
        return result
    }
}
