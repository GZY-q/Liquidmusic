import Foundation

// 纯值类型的队列状态机；重复歌曲使用独立条目 ID，方便插队与精确跳转。
struct QueueEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let track: Track
    init(track: Track) { self.id = UUID(); self.track = track }
}

struct PlaybackQueue: Sendable {
    private(set) var entries: [QueueEntry] = []
    private(set) var index: Int?
    private var indicesByID: [UUID: Int] = [:]
    private var history: [UUID] = []
    private var forwardHistory: [UUID] = []
    private var shuffledRemaining: [UUID] = []
    private var priorityEntries: [UUID] = []
    private var consumedPriorityEntries: Set<UUID> = []
    private var random: QueueRandomGenerator
    var mode: PlaybackMode = .sequential {
        didSet {
            guard mode != oldValue else { return }
            // 切换模式保留真实播放历史和待插队项，下一步按新模式安排。
            forwardHistory = []
            resetShuffleCycle()
        }
    }
    var currentEntry: QueueEntry? {
        guard let index, entries.indices.contains(index) else { return nil }
        return entries[index]
    }
    var current: Track? { currentEntry?.track }
    var currentEntryID: UUID? { currentEntry?.id }
    var canAdvance: Bool {
        guard let index else { return false }
        return !forwardHistory.isEmpty || !priorityEntries.isEmpty || mode == .shuffle || mode == .repeatAll || nextLinearIndex(after: index) != nil
    }
    var canGoBack: Bool {
        guard let index else { return false }
        return !history.isEmpty || (mode != .shuffle && (index > 0 || (mode == .repeatAll && entries.count > 1)))
    }
    var historyEntries: [QueueEntry] { history.compactMap(entry(for:)) }

    // 在副本上推演本轮剩余项，不推进真实随机源，也不把下一轮无限展开。
    var upcomingEntries: [QueueEntry] {
        var copy = self
        var result: [QueueEntry] = []
        let limit = entries.count + forwardHistory.count
        while result.count < limit, copy.moveForward(automatically: false, allowsNewCycle: false, recordsHistory: false) {
            if let entry = copy.currentEntry { result.append(entry) }
        }
        return result
    }

    init(shuffleSeed: UInt64 = .random(in: .min ... .max)) {
        random = QueueRandomGenerator(seed: shuffleSeed)
    }

    mutating func replace(with tracks: [Track], startingAt track: Track) {
        entries = tracks.map(QueueEntry.init)
        rebuildIndices()
        index = entries.firstIndex { $0.track.id == track.id } ?? (entries.isEmpty ? nil : 0)
        history = []; forwardHistory = []; priorityEntries = []; consumedPriorityEntries = []
        resetShuffleCycle()
    }

    mutating func insertNext(_ track: Track) {
        let entry = QueueEntry(track: track)
        let wasEmpty = currentEntry == nil
        let position = index.map { $0 + 1 } ?? 0
        entries.insert(entry, at: position)
        rebuildIndices()
        forwardHistory = []
        if wasEmpty {
            index = position
            resetShuffleCycle()
        } else {
            priorityEntries.insert(entry.id, at: 0)
            // 插队单独优先处理，不清空或重洗本轮随机候选。
        }
    }

    @discardableResult
    mutating func jump(to id: UUID) -> Bool {
        guard let target = indicesByID[id] else { return false }
        if id != currentEntryID {
            recordCurrentInHistory()
            index = target
        }
        forwardHistory = []
        consume(id)
        return true
    }

    @discardableResult
    mutating func advance(automatically: Bool = false) -> Bool {
        moveForward(automatically: automatically, allowsNewCycle: true, recordsHistory: true)
    }

    @discardableResult
    mutating func previous() -> Bool {
        guard let index, let currentID = currentEntryID else { return false }
        if let last = history.popLast(), let target = indicesByID[last] {
            forwardHistory.append(currentID)
            self.index = target
            consume(last)
            return true
        }
        // 随机没有历史时不能假装按物理下标回退。
        guard mode != .shuffle else { return false }
        let target = index > 0 ? index - 1 : (mode == .repeatAll ? entries.count - 1 : nil)
        guard let target, target != index else { return false }
        forwardHistory.append(currentID)
        self.index = target
        consume(entries[target].id)
        return true
    }

    private mutating func moveForward(automatically: Bool, allowsNewCycle: Bool, recordsHistory: Bool) -> Bool {
        guard let currentIndex = index else { return false }
        if automatically, mode == .repeatOne { return true }
        let nextID: UUID?
        var removesShuffleCandidate = true
        if let forward = forwardHistory.popLast() {
            nextID = forward
        } else if !priorityEntries.isEmpty {
            let id = priorityEntries.removeFirst()
            consumedPriorityEntries.insert(id)
            nextID = id
        } else {
            switch mode {
            case .shuffle:
                if shuffledRemaining.isEmpty {
                    guard allowsNewCycle else { return false }
                    consumedPriorityEntries = []
                    resetShuffleCycle(includingCurrent: true)
                }
                nextID = shuffledRemaining.popLast() ?? currentEntryID
                removesShuffleCandidate = false
            case .repeatAll:
                if let target = nextLinearIndex(after: currentIndex) { nextID = entries[target].id }
                else {
                    guard allowsNewCycle else { return false }
                    consumedPriorityEntries = []
                    nextID = entries.first?.id
                }
            case .sequential, .repeatOne:
                nextID = nextLinearIndex(after: currentIndex).map { entries[$0].id }
            }
        }
        guard let nextID, let target = indicesByID[nextID] else { return false }
        if nextID != currentEntryID, recordsHistory { recordCurrentInHistory() }
        index = target
        consume(nextID, removesShuffleCandidate: removesShuffleCandidate)
        return true
    }

    private func nextLinearIndex(after index: Int) -> Int? {
        ((index + 1)..<entries.count).first { !consumedPriorityEntries.contains(entries[$0].id) }
    }

    private func entry(for id: UUID) -> QueueEntry? { indicesByID[id].map { entries[$0] } }

    private mutating func consume(_ id: UUID, removesShuffleCandidate: Bool = true) {
        if priorityEntries.contains(id) { consumedPriorityEntries.insert(id) }
        priorityEntries.removeAll { $0 == id }
        if removesShuffleCandidate { shuffledRemaining.removeAll { $0 == id } }
    }

    private mutating func recordCurrentInHistory() {
        if let id = currentEntryID { history.append(id) }
        // 只保存最近 200 次访问，不让长期开着的播放器无限积累历史。
        if history.count > 200 { history.removeFirst(history.count - 200) }
    }

    private mutating func rebuildIndices() {
        indicesByID = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
    }

    private mutating func resetShuffleCycle(includingCurrent: Bool = false) {
        shuffledRemaining = mode == .shuffle
            ? entries.map(\.id).filter { (includingCurrent || $0 != currentEntryID) && !priorityEntries.contains($0) }.shuffled(using: &random)
            : []
        // 初始轮将当前项算作已播；后续完整轮仍包含它，只避免轮次交界立即重复。
        if includingCurrent, shuffledRemaining.count > 1, shuffledRemaining.last == currentEntryID {
            let replacement = Int.random(in: 0..<(shuffledRemaining.count - 1), using: &random)
            shuffledRemaining.swapAt(shuffledRemaining.count - 1, replacement)
        }
    }
}

// 值类型随机源允许注入种子；队列副本及测试可以确定地重现同一轮顺序。
private struct QueueRandomGenerator: RandomNumberGenerator, Sendable {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
