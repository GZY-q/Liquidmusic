import Foundation

// 图片或部分标签的非阻断提示随本次读取返回，避免共享可变的“最后一次警告”。
struct AudioFileReadResult: Sendable {
    var track: Track
    var warnings: [String] = []
}
