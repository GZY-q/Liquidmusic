import Foundation

// 调用方为 I/O actor；这里只定位 Application Support，不打开或迁移数据库。
enum LibraryPaths {
    static func applicationSupportDirectory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        return support.appendingPathComponent("Liquidmusic", isDirectory: true)
    }
}
