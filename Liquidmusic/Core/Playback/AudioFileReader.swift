import AVFoundation

protocol AudioFileReading: Sendable {
    func read(_ url: URL) async throws -> Track
}

enum AudioFileError: LocalizedError {
    case inaccessible
    case unsupported
    case invalidDuration

    var errorDescription: String? {
        switch self {
        case .inaccessible: "无法读取音频文件。文件可能已移动，请重新选择。"
        case .unsupported: "这个文件无法播放，格式可能不受支持，或文件已经损坏。"
        case .invalidDuration: "无法读取有效的音频时长，请选择完整的本地音频文件。"
        }
    }
}

// 单文件与批量索引共用异步校验和标签规则，图片由独立缓存服务下采样。
actor AudioFileReader: AudioFileReading, AudioMetadataReading {
    func read(_ url: URL) async throws -> Track {
        try await load(url, includingArtwork: false).track
    }

    func readMetadata(_ url: URL) async throws -> AudioMetadata {
        try await load(url, includingArtwork: true)
    }

    private func load(_ url: URL, includingArtwork: Bool) async throws -> AudioMetadata {
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            throw AudioFileError.inaccessible
        }
        let asset = AVURLAsset(url: url)
        let fingerprint = try FileFingerprint.read(url)
        guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw AudioFileError.unsupported
        }
        let seconds = try await asset.load(.duration).seconds
        guard seconds.isFinite, seconds > 0 else { throw AudioFileError.invalidDuration }
        try Task.checkCancellation()
        var warnings: [String] = []
        var common: [AVMetadataItem] = []
        var metadata: [AVMetadataItem] = []
        do {
            common = try await asset.load(.commonMetadata)
            metadata = try await asset.load(.metadata)
        } catch {
            warnings.append("部分标签无法读取，已使用可用标签或文件名。")
        }
        let title = await text(.commonIdentifierTitle, in: common)
        let artist = await text(.commonIdentifierArtist, in: common) ?? "未知艺术家"
        let album = await text(.commonIdentifierAlbumName, in: common) ?? "未知专辑"
        let taggedAlbumArtist = await text(.iTunesMetadataAlbumArtist, in: metadata)
        let band = await text(.id3MetadataBand, in: metadata)
        let albumArtist = taggedAlbumArtist ?? band
        let trackNumber = await number([.iTunesMetadataTrackNumber, .id3MetadataTrackNumber], in: metadata)
        let discNumber = await number([.iTunesMetadataDiscNumber, .id3MetadataPartOfASet], in: metadata)
        var artwork: Data?
        if includingArtwork {
            for item in AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork) {
                if let data = try? await item.load(.dataValue) {
                    if data.count <= 20 * 1024 * 1024 { artwork = data }
                    else { warnings.append("封面数据超过 20 MB，已跳过封面。") }
                    break
                }
            }
        }
        try Task.checkCancellation()
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let track = Track(id: path, folderID: "", path: path,
                          title: title ?? url.deletingPathExtension().lastPathComponent,
                          artist: artist, album: album, albumArtist: albumArtist ?? artist, duration: seconds,
                          discNumber: discNumber, trackNumber: trackNumber,
                          modifiedAt: fingerprint.modifiedAt, fileSize: fingerprint.size)
        return AudioMetadata(track: track, artworkData: artwork, warnings: warnings)
    }

    private func text(_ identifier: AVMetadataIdentifier, in items: [AVMetadataItem]) async -> String? {
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
            if let value = try? await item.load(.stringValue) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func number(_ identifiers: [AVMetadataIdentifier], in items: [AVMetadataItem]) async -> Int {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let text = try? await item.load(.stringValue),
                   let value = text.split(separator: "/").first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), value > 0 {
                    return value
                }
                if let value = try? await item.load(.numberValue), value.intValue > 0 { return value.intValue }
                if let data = try? await item.load(.dataValue), data.count >= 4 {
                    return Int(data[data.startIndex + 2]) << 8 | Int(data[data.startIndex + 3])
                }
            }
        }
        return 0
    }
}

// 只对成功启动的 security scope 配对停止；普通可读路径的 start 返回 false 也可继续读取。
@MainActor
final class AudioFileAccess {
    private let url: URL
    private let started: Bool

    init(_ url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }

    isolated deinit {
        if started { url.stopAccessingSecurityScopedResource() }
    }
}
