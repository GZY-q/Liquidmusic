import AppKit

// 专辑预览专用：内存绘图，不读写封面缓存、数据库或虚拟音频路径。
@MainActor
enum SPXArtwork {
    static let tracks: [Track] = {
        var tracks = SPXData.tracks
        tracks[1].artworkPath = "/preview/valid"
        tracks[2].artworkPath = "/preview/broken"
        tracks[4].artworkPath = "/preview/valid-other"
        var alternate = tracks[0]
        alternate.id = "preview-alternate"
        alternate.albumArtist = "另一位专辑艺术家"
        alternate.artworkPath = "/preview/missing"
        tracks.append(alternate)
        return tracks
    }()

    private static let imageData: Data? = {
        let image = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            NSColor.controlAccentColor.setFill()
            NSBezierPath(rect: rect).fill()
            NSColor.textBackgroundColor.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 20, dy: 20)).fill()
            NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
                .draw(in: rect.insetBy(dx: 44, dy: 36))
            return true
        }
        return image.tiffRepresentation
    }()

    static var loader: ArtworkDataLoader {
        let bytes = imageData
        return { path in
            switch path {
            case "/preview/valid", "/preview/valid-other": bytes
            case "/preview/broken": Data("损坏封面".utf8)
            default: nil
            }
        }
    }
}
