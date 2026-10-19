import Foundation
import Observation

// 每个窗口拥有独立的浏览位置，播放和持久化状态仍由 AppModel 共享。
@MainActor @Observable
final class LibraryViewModel {
    var section: LibrarySection? = .songs {
        didSet {
            guard isConfigured, section != oldValue else { return }
            scope = nil
            result = LibraryQueryResult()
            refresh()
        }
    }
    var query = "" {
        didSet { if isConfigured && query != oldValue { refresh(debounce: true) } }
    }
    var sortOrder = [TrackSort()] {
        didSet { if isConfigured && sortOrder != oldValue { refresh() } }
    }
    private(set) var scope: LibraryScope?
    private(set) var result = LibraryQueryResult()
    private(set) var trackCount = 0
    private(set) var isQuerying = false
    @ObservationIgnored private var tracks: [Track] = []
    @ObservationIgnored private let worker = LibraryQueryWorker()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var isConfigured = false

    var title: String { scope?.title ?? section?.rawValue ?? "歌曲" }
    var showsSongs: Bool { scope != nil || section == .songs || section == .allMusic || section == nil }

    init(section: LibrarySection? = .songs, query: String = "", scope: LibraryScope? = nil) {
        self.section = section
        self.query = query
        self.scope = scope
        // Observation 的访问器可能在初始化赋值时执行 didSet，配置完成前不调度查询。
        isConfigured = true
    }

    func replaceTracks(_ tracks: [Track]) {
        guard self.tracks != tracks else { return }
        self.tracks = tracks
        trackCount = tracks.count
        refresh()
    }

    func openAlbum(_ album: LibraryAlbum) { open(.album(album.id)) }
    func openArtist(_ artist: LibraryArtist) { open(.artist(artist.id)) }
    func goBack() {
        scope = nil
        result = LibraryQueryResult()
        refresh()
    }

    // 所有歌曲入口统一使用这个快照，确保右键、行内和双击播放的队列与屏幕一致。
    func play(_ ids: Set<Track.ID>, using playback: PlaybackController) {
        guard let track = result.tracks.first(where: { ids.contains($0.id) }) else { return }
        playback.play(track, in: result.tracks)
    }

    func playNext(_ ids: Set<Track.ID>, using playback: PlaybackController) {
        let selected = result.tracks.filter { ids.contains($0.id) }
        guard let first = selected.first else { return }
        // 空队列直接从选中列表首项开始；已有队列倒序插入以保持可见顺序。
        if playback.currentTrack == nil { playback.play(first, in: selected); return }
        for track in selected.reversed() { playback.playNext(track) }
    }

    private func open(_ scope: LibraryScope) {
        self.scope = scope
        result = LibraryQueryResult()
        refresh()
    }

    private func refresh(debounce: Bool = false) {
        task?.cancel()
        let generation = UUID()
        self.generation = generation
        let request = LibraryQueryRequest(query: query, scope: scope, sortOrder: sortOrder)
        let tracks = tracks
        isQuerying = true
        task = Task { [weak self, worker] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(120)) }
                let result = try await worker.query(tracks: tracks, request: request)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                self.result = result
                self.isQuerying = false
                self.task = nil
            } catch {
                // 查询只会抛出取消；迟到结果不能覆盖较新的搜索或导航。
                guard let self, self.generation == generation else { return }
                self.isQuerying = false
                self.task = nil
            }
        }
    }

    isolated deinit { task?.cancel() }

    // 预览同步计算模拟数据，不启动数据库、媒体键或异步查询。
    static func preview(section: LibrarySection = .songs, query: String = "", scope: LibraryScope? = nil,
                        tracks: [Track] = SPXData.tracks) -> LibraryViewModel {
        let model = LibraryViewModel(section: section, query: query, scope: scope)
        model.tracks = tracks
        model.trackCount = tracks.count
        model.result = (try? LibraryQueryIndex(tracks: tracks).result(for: LibraryQueryRequest(query: query, scope: scope))) ?? LibraryQueryResult()
        model.isQuerying = false
        return model
    }
}

// 独立 actor 缓存规范化后的标签，输入期间不会在主线程过滤或排序全库。
private actor LibraryQueryWorker {
    private var tracks: [Track] = []
    private var index: LibraryQueryIndex?

    func query(tracks: [Track], request: LibraryQueryRequest) throws -> LibraryQueryResult {
        try Task.checkCancellation()
        if index == nil || self.tracks != tracks {
            let index = try LibraryQueryIndex(tracks: tracks)
            self.tracks = tracks
            self.index = index
        }
        return try index!.result(for: request)
    }
}
