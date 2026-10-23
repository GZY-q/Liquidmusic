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
    let artworkCandidates: [AlbumArtworkCandidate]

    init(id: AlbumIdentity, representative: Track, count: Int, artworkCandidates: [AlbumArtworkCandidate] = []) {
        self.id = id
        self.representative = representative
        self.count = count
        self.artworkCandidates = artworkCandidates
    }
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
    var section: LibrarySection? = .songs
    var activity: [String: ListeningActivity] = [:]
}

struct LibraryQueryResult: Sendable {
    var tracks: [Track] = []
    var albums: [LibraryAlbum] = []
    var artists: [LibraryArtist] = []
    var scopeCount = 0
    // 仅非空的专辑详情结果提供候选；始终来自过滤前的完整专辑。
    var albumArtworkCandidates: [AlbumArtworkCandidate] = []
}

// 纯值查询索引：一次规范化标签，重复搜索复用；不接触 SQL、文件或 UI。
struct LibraryQueryIndex: Sendable {
    private struct Entry: Sendable {
        let track: Track
        let fields: [String]
    }
    private let entries: [Entry]
    private let albumArtwork: [AlbumIdentity: [AlbumArtworkCandidate]]

    init(tracks: [Track]) throws {
        try Task.checkCancellation()
        var entries: [Entry] = []
        var groups: [AlbumIdentity: [Track]] = [:]
        for (index, track) in tracks.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            entries.append(Entry(track: track, fields: [track.title, track.artist, track.album].map(Self.fold)))
            groups[AlbumIdentity(track), default: []].append(track)
        }
        let selector = AlbumArtworkSelector()
        var artwork: [AlbumIdentity: [AlbumArtworkCandidate]] = [:]
        for (album, members) in groups {
            artwork[album] = try selector.candidates(for: album, tracks: members)
        }
        try Task.checkCancellation()
        self.entries = entries
        self.albumArtwork = artwork
    }

    func result(for request: LibraryQueryRequest) throws -> LibraryQueryResult {
        let query = Self.fold(request.query.trimmingCharacters(in: .whitespacesAndNewlines))
        var result = LibraryQueryResult()
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard request.scope?.contains(entry.track) ?? true else { continue }
            if request.section?.isSmart == true, (request.activity[entry.track.path]?.playCount ?? 0) == 0 { continue }
            result.scopeCount += 1
            if query.isEmpty || entry.fields.contains(where: { $0.contains(query) }) {
                result.tracks.append(entry.track)
            }
        }
        result.tracks.sort { lhs, rhs in
            let left = request.activity[lhs.path]
            let right = request.activity[rhs.path]
            if request.section == .recentlyAdded {
                let a = left?.addedAt ?? .distantPast, b = right?.addedAt ?? .distantPast
                if a != b { return a > b }
            }
            if request.section == .mostPlayed {
                let a = left?.playCount ?? 0, b = right?.playCount ?? 0
                if a != b { return a > b }
            }
            if request.section?.isSmart == true {
                let a = left?.lastPlayedAt ?? .distantPast, b = right?.lastPlayedAt ?? .distantPast
                if a != b { return a > b }
            }
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
        // 只保留每组首项和计数，避免每次搜索为专辑、艺术家各复制一遍歌曲数组。
        var albums: [AlbumIdentity: (representative: Track, count: Int)] = [:]
        var artists: [String: (representative: Track, count: Int)] = [:]
        for (index, track) in result.tracks.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            albums[AlbumIdentity(track), default: (track, 0)].count += 1
            artists[track.artist, default: (track, 0)].count += 1
        }
        result.albums = albums.map {
            LibraryAlbum(id: $0.key, representative: $0.value.representative, count: $0.value.count,
                         artworkCandidates: albumArtwork[$0.key] ?? [])
        }
            .sorted {
                let title = TrackSort.textCompare($0.id.title, $1.id.title)
                if title != .orderedSame { return title == .orderedAscending }
                let artist = TrackSort.textCompare($0.id.artist, $1.id.artist)
                if artist != .orderedSame { return artist == .orderedAscending }
                if $0.id.title != $1.id.title { return $0.id.title < $1.id.title }
                return $0.id.artist < $1.id.artist
            }
        result.artists = artists.map { LibraryArtist(id: $0.key, representative: $0.value.representative, count: $0.value.count) }
            .sorted {
                let comparison = TrackSort.textCompare($0.id, $1.id)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
        if request.section == .recentlyAdded || request.section?.isSmart == true {
            // 网格沿用首首可见歌曲的排名，与切换到列表时的顺序一致。
            var ranks: [AlbumIdentity: Int] = [:]
            for (rank, track) in result.tracks.enumerated() where ranks[AlbumIdentity(track)] == nil {
                ranks[AlbumIdentity(track)] = rank
            }
            result.albums.sort { (ranks[$0.id] ?? .max) < (ranks[$1.id] ?? .max) }
        }
        try Task.checkCancellation()
        if case .album(let album) = request.scope, !result.tracks.isEmpty {
            result.albumArtworkCandidates = albumArtwork[album] ?? []
        }
        return result
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
