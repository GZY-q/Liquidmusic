import Foundation

struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let time: Double
    let text: String
}

struct LyricsDocument: Equatable, Sendable {
    var lines: [LyricLine] = []
    var plainText = ""
    var source = ""

    // 播放时只做二分查找；同一时间的原文和译文已合并成一行。
    func activeLine(at time: Double) -> Int? {
        guard time.isFinite else { return nil }
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lines[middle].time <= time { lower = middle + 1 }
            else { upper = middle }
        }
        return lower > 0 ? lines[lower - 1].id : nil
    }
}

enum LyricsError: LocalizedError {
    case tooLarge, encoding, empty
    var errorDescription: String? {
        switch self {
        case .tooLarge: "歌词文件过大，请选择不超过 1 MB、10,000 行的歌词。"
        case .encoding: "无法识别歌词编码，请将文件保存为 UTF-8 或 UTF-16。"
        case .empty: "文件中没有可显示的歌词。"
        }
    }
}

enum LyricsParser {
    static func parse(_ text: String, source: String = "") throws -> LyricsDocument? {
        guard text.utf8.count <= 1_048_576 else { throw LyricsError.tooLarge }
        var timed: [(time: Double, text: String)] = []
        var plain: [String] = []
        var offset = 0.0
        var expandedBytes = 0
        var tagCount = 0
        let rows = text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines)
        guard rows.count <= 10_000 else { throw LyricsError.tooLarge }
        let metadata = ["ti", "ar", "al", "by", "re", "ve", "length", "au", "offset"]
        for row in rows {
            try Task.checkCancellation()
            var content = row.trimmingCharacters(in: .whitespaces)
            var times: [Double] = []
            var isTag = false
            while content.hasPrefix("["), let end = content.firstIndex(of: "]") {
                tagCount += 1
                guard tagCount <= 10_000 else { throw LyricsError.tooLarge }
                let tag = String(content[content.index(after: content.startIndex)..<end])
                if let time = timestamp(tag) { times.append(time) }
                else if tag.lowercased().hasPrefix("offset:"), let value = Double(tag.dropFirst(7)), value.isFinite {
                    offset = value / 1_000
                } else if metadata.contains(String(tag.split(separator: ":").first ?? "").lowercased()) {
                    // LRC 标签只描述歌曲，不当作歌词显示。
                } else if tag.first?.isNumber != true { break }
                isTag = true
                content = String(content[content.index(after: end)...]).trimmingCharacters(in: .whitespaces)
            }
            if !times.isEmpty {
                expandedBytes += content.utf8.count * times.count
                guard expandedBytes <= 1_048_576 else { throw LyricsError.tooLarge }
                for time in times { timed.append((time, content)) }
                guard timed.count <= 10_000 else { throw LyricsError.tooLarge }
            } else if !isTag, !content.isEmpty { plain.append(content) }
        }
        if timed.contains(where: { !$0.text.isEmpty }) {
            // LRC 正 offset 表示提前显示；负值表示延后。
            var sorted: [(order: Int, time: Double, text: String)] = []
            for (index, item) in timed.enumerated() {
                let adjusted = max(0, item.time - offset)
                guard adjusted.isFinite else { continue }
                sorted.append((index, adjusted, item.text))
            }
            sorted.sort { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }
            var lines: [LyricLine] = []
            var groupTime: Double?
            var groupText: [String] = []
            for item in sorted {
                if let time = groupTime, time != item.time {
                    lines.append(LyricLine(id: lines.count, time: time, text: groupText.joined(separator: "\n")))
                    groupText.removeAll(keepingCapacity: true)
                }
                groupTime = item.time
                if !item.text.isEmpty { groupText.append(item.text) }
            }
            if let time = groupTime { lines.append(LyricLine(id: lines.count, time: time, text: groupText.joined(separator: "\n"))) }
            return LyricsDocument(lines: lines, source: source)
        }
        guard !plain.isEmpty else { return nil }
        return LyricsDocument(plainText: plain.joined(separator: "\n"), source: source)
    }

    private static func timestamp(_ tag: String) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].allSatisfy(\.isNumber), let minutes = Double(parts[0]),
              parts[1].allSatisfy({ $0.isNumber || $0 == "." }), let seconds = Double(parts[1]),
              seconds >= 0, seconds < 60 else { return nil }
        let time = minutes * 60 + seconds
        return time.isFinite ? time : nil
    }
}
