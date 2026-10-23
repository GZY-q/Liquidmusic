import Foundation

// 与扫描索引分开保存；旧资料库的添加时间从首次记录开始计算。
struct ListeningActivity: Codable, Equatable, Sendable {
    var path: String
    var addedAt: Date
    var lastPlayedAt: Date?
    var playCount = 0
}

enum LibraryDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case list = "歌曲列表", grid = "专辑网格"
    var id: Self { self }
    var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }
}
