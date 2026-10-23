import Foundation

struct Track: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var folderID: String
    var path: String
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var duration: Double
    var discNumber: Int = 0
    var trackNumber: Int = 0
    var artworkPath: String?
    var modifiedAt: Date = .now
    var fileSize: Int64?

    var url: URL { URL(fileURLWithPath: path) }
    var albumKey: String { "\(albumArtist)\u{1F}\(album)" }
    var durationText: String { Self.timeText(duration) }

    static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds)
        return value >= 3600
            ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
}

enum LibrarySection: String, CaseIterable, Identifiable, Sendable {
    case recentlyAdded = "最近添加", recentlyPlayed = "最近播放", mostPlayed = "最常播放"
    case songs = "歌曲", albums = "专辑", artists = "艺术家", playlists = "播放列表"
    case allMusic = "所有音乐"
    static let librarySections: [Self] = [.recentlyAdded, .artists, .albums, .songs]
    static let smartSections: [Self] = [.recentlyPlayed, .mostPlayed]
    var isSmart: Bool { Self.smartSections.contains(self) }
    var id: Self { self }
    var symbol: String {
        switch self {
        case .recentlyAdded: "clock"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .mostPlayed: "chart.bar"
        case .songs: "music.note"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .playlists, .allMusic: "music.note.list"
        }
    }
}

enum PlaybackMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case sequential = "顺序播放", repeatAll = "列表循环", repeatOne = "单曲循环", shuffle = "随机播放"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .sequential: "arrow.right"
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        case .shuffle: "shuffle"
        }
    }
}

// 预览数据不会写入真实资料库，也不会在首次启动时冒充用户歌曲。
enum SPXData {
    // 合成索引仅用于预览和规模检查；不访问这些虚拟路径。
    static let largeLibrary: [Track] = (0..<1_000).map { index in
        Track(id: "scale-\(index)", folderID: "preview", path: "/preview/scale-\(index).m4a",
              title: "模拟歌曲 \(index + 1)", artist: "艺术家 \(index / 100 + 1)",
              album: "专辑 \(index / 10 + 1)", albumArtist: "艺术家 \(index / 100 + 1)",
              duration: Double(120 + index % 240), trackNumber: index % 10 + 1, modifiedAt: .distantPast)
    }

    static let tracks: [Track] = [
        ("夜航", "林间来信", "蓝色时刻", 238.0),
        ("慢慢走", "林间来信", "蓝色时刻", 194.0),
        ("A Quiet Morning", "North Coast", "Somewhere Still", 265.0),
        ("潮汐", "白日梦", "海的另一边", 213.0),
        ("Sunday", "North Coast", "Somewhere Still", 182.0)
    ].enumerated().map { index, value in
        Track(id: "preview-\(index)", folderID: "preview", path: "/preview/\(index).m4a",
              title: value.0, artist: value.1, album: value.2, albumArtist: value.1,
              duration: value.3, trackNumber: index + 1)
    }
}
