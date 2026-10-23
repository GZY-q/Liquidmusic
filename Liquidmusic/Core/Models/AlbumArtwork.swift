import Foundation

// 专辑封面候选的纯值选择；图片读取和界面接入属于 AW2。
// 完整规则、实施顺序与验收用例见 docs/ALBUM_ARTWORK.md。

/// 指向已有缩略图的候选，不保存图像对象，也不表示文件已经验证可读。
struct AlbumArtworkCandidate: Hashable, Sendable {
    let trackID: Track.ID
    let cachePath: String
}

/// 纯值选择边界，供后台查询索引使用；禁止在实现中读文件、解码或写数据库。
protocol AlbumArtworkSelecting: Sendable {
    /// tracks 是查询过滤前、属于该专辑的完整分组；实现仍须校验 AlbumIdentity。
    /// 按碟号、曲号、稳定 ID 排序，未知编号置后；忽略空路径并按路径去重。
    /// 返回全部候选，以便展示层在缓存缺失或损坏时尝试下一项。
    /// 大组处理响应 Task 取消；无封面返回空数组，不能用错误表示正常缺图。
    func candidates(for album: AlbumIdentity, tracks: [Track]) throws -> [AlbumArtworkCandidate]
}

struct AlbumArtworkSelector: AlbumArtworkSelecting {
    func candidates(for album: AlbumIdentity, tracks: [Track]) throws -> [AlbumArtworkCandidate] {
        try Task.checkCancellation()
        var eligible: [Track] = []
        for (index, track) in tracks.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard AlbumIdentity(track) == album,
                  let path = track.artworkPath,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            eligible.append(track)
        }
        // 排序期间也检查取消，避免大专辑在筛选后长时间占用查询 actor。
        var comparisons = 0
        let ordered = try eligible.sorted { lhs, rhs in
            if comparisons.isMultiple(of: 256) { try Task.checkCancellation() }
            comparisons += 1
            if let before = Self.numberOrder(lhs.discNumber, rhs.discNumber) { return before }
            if let before = Self.numberOrder(lhs.trackNumber, rhs.trackNumber) { return before }
            return lhs.id < rhs.id
        }
        var seen = Set<String>()
        var result: [AlbumArtworkCandidate] = []
        for (index, track) in ordered.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            // 仅用修剪值判断空白；有效路径必须保留其原始空格。
            if let path = track.artworkPath, seen.insert(path).inserted {
                result.append(AlbumArtworkCandidate(trackID: track.id, cachePath: path))
            }
        }
        try Task.checkCancellation()
        return result
    }

    // nil 表示同值；所有非正编号视为相同的未知值，排在正编号之后。
    private static func numberOrder(_ lhs: Int, _ rhs: Int) -> Bool? {
        if (lhs > 0) != (rhs > 0) { return lhs > 0 }
        guard lhs > 0, lhs != rhs else { return nil }
        return lhs < rhs
    }
}
