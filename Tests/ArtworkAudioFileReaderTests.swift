import AVFoundation
import AppKit
import MediaPlayer
import XCTest
@testable import Liquidmusic

@MainActor
final class ArtworkAudioFileReaderTests: XCTestCase {
    func testTemporaryMP3AndM4AEmbeddedCoversProduceCacheWithoutDatabase() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let mp3 = fixture.directory.appendingPathComponent("tagged.mp3")
        try FileManager.default.copyItem(at: resource("tagged", ext: "mp3"), to: mp3)
        let m4a = fixture.directory.appendingPathComponent("artwork.m4a")
        try await exportM4AWithCover(to: m4a)
        let cache = fixture.directory.appendingPathComponent("Artwork")
        let reader = ArtworkAudioFileReader(cacheDirectory: { cache })
        for url in [mp3, m4a] {
            let result = try await reader.readResult(url)
            XCTAssertTrue(result.warnings.isEmpty)
            XCTAssertGreaterThan(result.track.duration, 0)
            let path = try XCTUnwrap(result.track.artworkPath)
            XCTAssertTrue(path.hasPrefix(cache.path + "/"))
            XCTAssertNotNil(NSImage(contentsOfFile: path))
            let repeated = try await reader.read(url)
            XCTAssertEqual(repeated.artworkPath, path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Library.sqlite").path))
    }

    func testNoCoverDoesNotResolveOrCreateCacheDirectory() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let reader = ArtworkAudioFileReader(cacheDirectory: { throw CocoaError(.fileWriteNoPermission) })
        let result = try await reader.readResult(fixture.url)
        XCTAssertNil(result.track.artworkPath)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testBrokenCoverAndMetadataWarningsDoNotPreventPlaybackAndCanBeDismissed() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let cache = fixture.directory.appendingPathComponent("Artwork")
        let metadata = AudioMetadata(track: fixture.track, artworkData: Data("坏图片".utf8), warnings: ["部分标签缺失"])
        let reader = ArtworkAudioFileReader(reader: FixedAWMetadataReader(metadata: metadata), cacheDirectory: { cache })
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        let model = AppModel(playback: playback, fileReader: reader)
        defer { model.shutdown() }
        await model.importFile(fixture.url).value
        XCTAssertNil(model.importError)
        XCTAssertNil(playback.currentTrack?.artworkPath)
        XCTAssertEqual(model.importWarnings.count, 2)
        XCTAssertEqual(model.importWarnings.first, "部分标签缺失")
        try await eventually { playback.isPlaying }
        model.dismissImportWarnings()
        XCTAssertTrue(model.importWarnings.isEmpty)
    }

    func testCacheWriteAndDirectoryResolutionFailuresAreNonblocking() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let metadata = AudioMetadata(track: fixture.track, artworkData: try coverData())
        let blocked = fixture.directory.appendingPathComponent("not-a-directory")
        try Data("占用缓存目录".utf8).write(to: blocked, options: .withoutOverwriting)
        let readers = [
            ArtworkAudioFileReader(reader: FixedAWMetadataReader(metadata: metadata), cacheDirectory: { blocked }),
            ArtworkAudioFileReader(reader: FixedAWMetadataReader(metadata: metadata), cacheDirectory: { throw CocoaError(.fileWriteNoPermission) })
        ]
        for reader in readers {
            let result = try await reader.readResult(fixture.url)
            XCTAssertEqual(result.track.id, fixture.track.id)
            XCTAssertNil(result.track.artworkPath)
            XCTAssertEqual(result.warnings.count, 1)
        }
    }

    func testCancellationFromCacheResolutionIsNotConvertedToWarning() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let metadata = AudioMetadata(track: fixture.track, artworkData: try coverData())
        let reader = ArtworkAudioFileReader(reader: FixedAWMetadataReader(metadata: metadata), cacheDirectory: { throw CancellationError() })
        do { _ = try await reader.readResult(fixture.url); XCTFail("取消必须传播") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCancelledImportRejectsLateMetadataWithoutWritingCacheOrWarnings() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let cache = fixture.directory.appendingPathComponent("Artwork")
        let controlled = ControlledAWMetadataReader()
        let reader = ArtworkAudioFileReader(reader: controlled, cacheDirectory: { cache })
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        let model = AppModel(playback: playback, fileReader: reader)
        defer { model.shutdown() }
        let task = model.importFile(fixture.url)
        try await eventually { await controlled.contains(fixture.url) }
        model.cancelImport()
        await controlled.complete(fixture.url, metadata: AudioMetadata(track: fixture.track, artworkData: try coverData(), warnings: ["旧提示"]))
        await task.value
        XCTAssertNil(playback.currentTrack)
        XCTAssertTrue(model.tracks.isEmpty)
        XCTAssertTrue(model.importWarnings.isEmpty)
        XCTAssertNil(model.importError)
        XCTAssertFalse(model.isImporting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    func testRapidSelectionsKeepLatestCoverAndWarningsEvenWhenOldReadReturnsLast() async throws {
        let first = try AudioFixture(duration: 3), second = try AudioFixture(duration: 5)
        defer { first.remove(); second.remove() }
        let cache = second.directory.appendingPathComponent("Artwork")
        let controlled = ControlledAWMetadataReader()
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        let model = AppModel(playback: playback, fileReader: ArtworkAudioFileReader(reader: controlled, cacheDirectory: { cache }))
        defer { model.shutdown() }
        let old = model.importFile(first.url)
        try await eventually { await controlled.contains(first.url) }
        let latest = model.importFile(second.url)
        try await eventually { await controlled.contains(second.url) }
        await controlled.complete(second.url, metadata: AudioMetadata(track: second.track, artworkData: try coverData()))
        await latest.value
        let selected = try XCTUnwrap(playback.currentTrack)
        XCTAssertNotNil(selected.artworkPath)
        let entryID = playback.queue.currentEntryID
        await controlled.complete(first.url, metadata: AudioMetadata(track: first.track, artworkData: Data("坏图".utf8), warnings: ["过时提示"]))
        await old.value
        XCTAssertEqual(playback.currentTrack, selected)
        XCTAssertEqual(playback.queue.currentEntryID, entryID)
        XCTAssertEqual(model.tracks, [selected])
        XCTAssertTrue(model.importWarnings.isEmpty)
        XCTAssertNil(model.importError)
        try await eventually { playback.isPlaying }
    }

    func testAudioFailurePreservesOldTrackAndNewSelectionClearsWarnings() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let cache = fixture.directory.appendingPathComponent("Artwork")
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        let model = AppModel(playback: playback, fileReader: ArtworkAudioFileReader(reader: WarningAWMetadataReader(), cacheDirectory: { cache }))
        defer { model.shutdown() }
        await model.importFile(fixture.url).value
        let selected = playback.currentTrack
        XCTAssertEqual(model.importWarnings, ["模拟标签提示"])
        await model.importFile(fixture.directory.appendingPathComponent("missing.mp3")).value
        XCTAssertEqual(playback.currentTrack, selected)
        XCTAssertNotNil(model.importError)
        XCTAssertTrue(model.importWarnings.isEmpty)
        await model.importFile(fixture.url).value
        XCTAssertNil(model.importError)
        XCTAssertTrue(model.importWarnings.isEmpty)
    }

    func testIndexedPathKeepsStableTrackAndSuggestsReviewedRescanForMissingCover() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let store = LibraryStore(location: .memory)
        let folder = try await store.saveFolder(LibraryFolder(path: fixture.directory.path, displayName: "测试目录", bookmarkData: Data()))
        var indexed = fixture.track
        indexed.folderID = folder.id
        indexed.title = "持久化标题"
        _ = try await store.upsertTracks([indexed])
        // 使用数据库读回的基线，避免把 SQLite 毫秒日期精度误判为索引修改。
        let before = try await store.tracks()
        let library = LibraryController(store: store)
        await library.load()
        let cache = fixture.directory.appendingPathComponent("Artwork")
        let metadata = AudioMetadata(track: fixture.track, artworkData: try coverData())
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        let model = AppModel(playback: playback,
                             fileReader: ArtworkAudioFileReader(reader: FixedAWMetadataReader(metadata: metadata), cacheDirectory: { cache }),
                             library: library)
        await model.importFile(fixture.url).value
        XCTAssertEqual(playback.currentTrack, before.first)
        XCTAssertEqual(model.tracks, before)
        XCTAssertTrue(model.importWarnings.contains { $0.contains("重新扫描") })
        let after = try await store.tracks()
        XCTAssertEqual(after, before)
        XCTAssertNil(library.pendingReview)
        model.shutdown()
        await library.shutdown().value
        try await store.close()
    }

    func testImportedCoverReachesMediaSnapshotThenClearsForTrackWithoutCover() async throws {
        let fixture = try AudioFixture(duration: 5)
        defer { fixture.remove() }
        let cache = fixture.directory.appendingPathComponent("Artwork")
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        let model = AppModel(playback: playback, fileReader: ArtworkAudioFileReader(cacheDirectory: { cache }))
        let transport = AWMediaTransport()
        let media = SystemMediaController(playback: playback, transport: transport)
        defer { media.shutdown(); model.shutdown() }
        let mp3 = fixture.directory.appendingPathComponent("tagged.mp3")
        try FileManager.default.copyItem(at: resource("tagged", ext: "mp3"), to: mp3)
        await model.importFile(mp3).value
        let selected = try XCTUnwrap(playback.currentTrack)
        media.update(playback)
        try await eventually { transport.hasArtwork }
        XCTAssertEqual(transport.snapshot.metadata?.artworkPath, selected.artworkPath)
        XCTAssertEqual(transport.snapshot.metadata?.title, selected.title)
        let entry = playback.queue.currentEntryID
        media.update(playback)
        XCTAssertEqual(playback.queue.currentEntryID, entry)
        await model.importFile(fixture.url).value
        media.update(playback)
        XCTAssertFalse(transport.hasArtwork)
        XCTAssertNil(transport.snapshot.metadata?.artworkPath)
        XCTAssertTrue(model.importWarnings.isEmpty)
    }

    private func resource(_ name: String, ext: String) throws -> URL {
        let bundle = Bundle(for: ArtworkAudioFileReaderTests.self)
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
                             ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }
    private func coverData() throws -> Data { try Data(contentsOf: resource("cover", ext: "jpg")) }

    private func exportM4AWithCover(to url: URL) async throws {
        let asset = AVURLAsset(url: try resource("tagged", ext: "m4a"))
        let session = try XCTUnwrap(AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough))
        let artwork = AVMutableMetadataItem()
        artwork.identifier = .iTunesMetadataCoverArt
        artwork.dataType = "public.jpeg"
        artwork.value = try coverData() as NSData
        session.metadata = [artwork]
        try await session.export(to: url, as: .m4a)
    }

    private func eventually(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            if ContinuousClock.now >= deadline { XCTFail("等待封面导入状态超时"); throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct FixedAWMetadataReader: AudioMetadataReading {
    let metadata: AudioMetadata
    func readMetadata(_ url: URL) async throws -> AudioMetadata { metadata }
}

private actor WarningAWMetadataReader: AudioMetadataReading {
    private var successfulReads = 0
    func readMetadata(_ url: URL) async throws -> AudioMetadata {
        var metadata = try await AudioFileReader().readMetadata(url)
        if successfulReads == 0 { metadata.warnings = ["模拟标签提示"] }
        successfulReads += 1
        return metadata
    }
}

private actor ControlledAWMetadataReader: AudioMetadataReading {
    private var pending: [URL: CheckedContinuation<AudioMetadata, Never>] = [:]
    func readMetadata(_ url: URL) async throws -> AudioMetadata {
        await withCheckedContinuation { pending[url] = $0 }
    }
    func contains(_ url: URL) -> Bool { pending[url] != nil }
    func complete(_ url: URL, metadata: AudioMetadata) { pending.removeValue(forKey: url)?.resume(returning: metadata) }
}

@MainActor
private final class AWMediaTransport: SystemMediaTransport {
    var snapshot = NowPlayingSnapshot()
    var hasArtwork = false
    func register(_ handler: @escaping @Sendable (MediaCommand) -> MPRemoteCommandHandlerStatus) {}
    func unregister() {}
    func setEnabled(_ availability: MediaCommandAvailability) {}
    func publish(_ snapshot: NowPlayingSnapshot, artwork: NSImage?) {
        self.snapshot = snapshot
        hasArtwork = artwork != nil
    }
}
