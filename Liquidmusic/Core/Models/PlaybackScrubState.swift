import Foundation

// 拖动位置独立于播放器时间 tick；没有编辑手势的写入代表键盘或辅助功能 seek。
struct PlaybackScrubState: Sendable {
    private var editingEntryID: UUID?
    private var position: Double?

    func displayedPosition(elapsed: Double, duration: Double) -> Double {
        Self.clamp(position ?? elapsed, duration: duration)
    }

    mutating func begin(entryID: UUID?, elapsed: Double, duration: Double) {
        editingEntryID = entryID
        position = entryID == nil ? nil : Self.clamp(elapsed, duration: duration)
    }

    @discardableResult
    mutating func update(_ value: Double, entryID: UUID?, duration: Double) -> Double? {
        guard value.isFinite, let entryID else { return nil }
        let value = Self.clamp(value, duration: duration)
        if let editingEntryID {
            guard editingEntryID == entryID else { return nil }
            position = value
            return nil
        }
        return value
    }

    mutating func finish(entryID: UUID?, duration: Double) -> Double? {
        defer { cancel() }
        guard let editingEntryID, editingEntryID == entryID, let position else { return nil }
        return Self.clamp(position, duration: duration)
    }

    mutating func cancel() { editingEntryID = nil; position = nil }

    private static func clamp(_ value: Double, duration: Double) -> Double {
        guard value.isFinite, duration.isFinite else { return 0 }
        return min(max(0, value), max(0, duration))
    }
}
