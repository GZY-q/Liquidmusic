import Foundation
import Observation

@MainActor @Observable
final class ListeningActivityController {
    private(set) var records: [String: ListeningActivity] = [:]
    private(set) var error: String?
    @ObservationIgnored private let store: LibraryStore?
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(store: LibraryStore? = nil) { self.store = store }

    @discardableResult
    func synchronize(_ tracks: [Track]) -> Task<Void, Never> {
        enqueue(paths: tracks.map(\.path))
    }

    @discardableResult
    func recordPlayback(_ track: Track) -> Task<Void, Never> {
        enqueue(paths: [track.path], playedPath: track.path)
    }

    private func enqueue(paths: [String], playedPath: String? = nil) -> Task<Void, Never> {
        let previous = pending
        let date = Date.now
        let task = Task { [weak self, store] in
            // 串行处理首次载入与播放事件，防止迟到的读取覆盖新计数。
            await previous?.value
            guard let self else { return }
            do {
                if let store {
                    self.records = try await store.listeningActivity(paths: paths, playedPath: playedPath, at: date)
                } else {
                    for path in paths where self.records[path] == nil {
                        self.records[path] = ListeningActivity(path: path, addedAt: date)
                    }
                    if let playedPath {
                        self.records[playedPath]?.lastPlayedAt = date
                        self.records[playedPath]?.playCount += 1
                    }
                }
                self.error = nil
            } catch {
                self.error = "无法保存聆听记录：\(error.localizedDescription)"
            }
        }
        pending = task
        return task
    }
}
