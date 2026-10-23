import AVFoundation

protocol LyricsReading: Sendable {
    func read(for track: Track) async throws -> LyricsDocument?
    func readFile(_ url: URL) async throws -> LyricsDocument?
}

actor LyricsReader: LyricsReading {
    func read(for track: Track) async throws -> LyricsDocument? {
        let url = track.url
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        // 只尝试同名文件，不枚举音乐目录；单文件授权不足时可由用户手动选择歌词。
        var localError: (any Error)?
        for ext in ["lrc", "LRC"] {
            try Task.checkCancellation()
            let sidecar = url.deletingPathExtension().appendingPathExtension(ext)
            guard FileManager.default.fileExists(atPath: sidecar.path) else { continue }
            do {
                if let document = try await readFile(sidecar) { return document }
            } catch is CancellationError { throw CancellationError() }
            catch { localError = error }
        }
        let asset = AVURLAsset(url: url)
        do {
            let lyrics = try await asset.load(.lyrics)
            try Task.checkCancellation()
            if let lyrics, let document = try LyricsParser.parse(lyrics, source: "内嵌歌词") { return document }
        } catch is CancellationError { throw CancellationError() }
        catch { if localError == nil { localError = error } }
        if let localError { throw localError }
        return nil
    }

    func readFile(_ url: URL) async throws -> LyricsDocument? {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw LyricsError.tooLarge }
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16)
        } else { text = String(data: data, encoding: .utf8) }
        guard let text else { throw LyricsError.encoding }
        return try LyricsParser.parse(text, source: url.lastPathComponent)
    }
}
