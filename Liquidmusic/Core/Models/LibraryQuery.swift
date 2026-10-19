import Foundation

// 用结构化标识区分同名专辑，也避免标签中的分隔符造成碰撞。
struct AlbumIdentity: Hashable, Sendable {
    let title: String
    let artist: String
    init(_ track: Track) { title = track.album; artist = track.albumArtist }
}

enum LibraryScope: Equatable, Sendable {
    case album(AlbumIdentity)
    case artist(String)
    var title: String {
        switch self {
        case .album(let album): album.title
        case .artist(let name): name
        }
    }
    var subtitle: String {
        switch self {
        case .album(let album): album.artist
        case .artist: "艺术家"
        }
    }
    func contains(_ track: Track) -> Bool {
        switch self {
        case .album(let album): AlbumIdentity(track) == album
        case .artist(let name): track.artist == name
        }
    }
}

enum TrackSortField: String, CaseIterable, Identifiable, Sendable {
    case title = "标题", artist = "艺术家", album = "专辑", duration = "时长"
    var id: Self { self }
}

// 与原生 Table 共享比较器；时长按秒比较，而非格式化后的字符串。
struct TrackSort: SortComparator, Sendable {
    var field: TrackSortField = .title
    var order: SortOrder = .forward

    func compare(_ lhs: Track, _ rhs: Track) -> ComparisonResult {
        let result: ComparisonResult
        switch field {
        case .title: result = Self.textCompare(lhs.title, rhs.title)
        case .artist: result = Self.textCompare(lhs.artist, rhs.artist)
        case .album: result = Self.textCompare(lhs.album, rhs.album)
        case .duration:
            result = lhs.duration == rhs.duration ? .orderedSame : (lhs.duration < rhs.duration ? .orderedAscending : .orderedDescending)
        }
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    static func textCompare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: .current)
    }
}

struct LibraryAlbum: Identifiable, Sendable {
    let id: AlbumIdentity
    let representative: Track
    let count: Int
}

struct LibraryArtist: Identifiable, Sendable {
    let id: String
    let representative: Track
    let count: Int
}

struct LibraryQueryRequest: Sendable {
    var query = ""
    var scope: LibraryScope?
    var sortOrder: [TrackSort] = [TrackSort()]
}

struct LibraryQueryResult: Sendable {
    var tracks: [Track] = []
    var albums: [LibraryAlbum] = []
    var artists: [LibraryArtist] = []
    var scopeCount = 0
}

// 纯值查询索引：一次规范化标签，重复搜索复用；不接触 SQL、文件或 UI。
struct LibraryQueryIndex: Sendable {
    private struct Entry: Sendable {
        let track: Track
        let fields: [String]
    }
    private let entries: [Entry]

    init(tracks: [Track]) throws {
        entries = try tracks.enumerated().map { index, track in
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            return Entry(track: track, fields: [track.title, track.artist, track.album].map(Self.fold))
        }
    }

    func result(for request: LibraryQueryRequest) throws -> LibraryQueryResult {
        let query = Self.fold(request.query.trimmingCharacters(in: .whitespacesAndNewlines))
        var result = LibraryQueryResult()
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard request.scope?.contains(entry.track) ?? true else { continue }
            result.scopeCount += 1
            if query.isEmpty || entry.fields.contains(where: { $0.contains(query) }) {
                result.tracks.append(entry.track)
            }
        }
        result.tracks.sort { lhs, rhs in
            for sort in request.sortOrder {
                let comparison = sort.compare(lhs, rhs)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            // 相等值始终使用相同次级键，重扫或输入顺序改变不会让行跳动。
            let title = TrackSort.textCompare(lhs.title, rhs.title)
            if title != .orderedSame { return title == .orderedAscending }
            return lhs.id < rhs.id
        }
        try Task.checkCancellation()
        let albums = Dictionary(grouping: result.tracks, by: AlbumIdentity.init)
        result.albums = albums.map { LibraryAlbum(id: $0.key, representative: $0.value[0], count: $0.value.count) }
            .sorted {
                let title = TrackSort.textCompare($0.id.title, $1.id.title)
                if title != .orderedSame { return title == .orderedAscending }
                let artist = TrackSort.textCompare($0.id.artist, $1.id.artist)
                if artist != .orderedSame { return artist == .orderedAscending }
                if $0.id.title != $1.id.title { return $0.id.title < $1.id.title }
                return $0.id.artist < $1.id.artist
            }
        let artists = Dictionary(grouping: result.tracks, by: \.artist)
        result.artists = artists.map { LibraryArtist(id: $0.key, representative: $0.value[0], count: $0.value.count) }
            .sorted {
                let comparison = TrackSort.textCompare($0.id, $1.id)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
        try Task.checkCancellation()
        return result
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
