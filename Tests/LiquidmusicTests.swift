import XCTest
@testable import Liquidmusic

@MainActor
final class LiquidmusicTests: XCTestCase {
    func testProgressCadenceChangesWithoutLosingPlaybackOrPausedSeek() async throws {
        let fixture = try AudioFixture(duration: 12)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        playback.play(fixture.track, in: [fixture.track])
        try await eventually { playback.isPlaying }

        // 观察真实音频时钟发布次数，防止普通播放恢复为高频 UI 更新。
        func changes() async throws -> Int {
            var previous = playback.elapsed
            var count = 0
            let deadline = ContinuousClock.now.advanced(by: .seconds(1.2))
            while ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
                if playback.elapsed != previous {
                    count += 1
                    previous = playback.elapsed
                }
            }
            return count
        }
        let ordinary = try await changes()
        XCTAssertTrue((2...7).contains(ordinary), "普通播放发布次数：\(ordinary)")
        playback.configureCrossfade(enabled: true, duration: 1)
        let precise = try await changes()
        XCTAssertTrue((2...7).contains(precise), "开启渐变也应限制 UI 发布次数：\(precise)")
        playback.configureCrossfade(enabled: false, duration: 1)
        let restored = try await changes()
        XCTAssertTrue((2...7).contains(restored), "关闭渐变后发布次数：\(restored)")
        playback.pause()
        playback.seek(to: 7)
        XCTAssertEqual(playback.elapsed, 7, accuracy: 0.01)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(playback.elapsed, 7, accuracy: 0.05)
        XCTAssertEqual(playback.status, .paused)
    }

    func testFileReaderLoadsWAVAndRejectsCorruptAndMissingFiles() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let reader = AudioFileReader()
        let track = try await reader.read(fixture.url)
        XCTAssertEqual(track.duration, 3, accuracy: 0.01)
        XCTAssertEqual(track.title, "fixture")
        XCTAssertEqual(track.artist, "未知艺术家")
        let corrupt = fixture.directory.appendingPathComponent("broken.mp3")
        try Data("损坏的音频".utf8).write(to: corrupt)
        for url in [corrupt, fixture.directory.appendingPathComponent("missing.wav"), fixture.directory] {
            do {
                _ = try await reader.read(url)
                XCTFail("无效文件不应通过音频校验：\(url.lastPathComponent)")
            } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }

    func testLatestSelectionWinsEvenIfOlderReadFinishesLast() async throws {
        let first = try AudioFixture(duration: 2)
        let second = try AudioFixture(duration: 5)
        defer { first.remove(); second.remove() }
        let reader = ControlledReader()
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        let model = AppModel(playback: playback, fileReader: reader)
        defer { model.shutdown() }
        let oldTask = model.importFile(first.url)
        try await eventually { await reader.hasRequest(first.url) }
        let newTask = model.importFile(second.url)
        try await eventually { await reader.hasRequest(second.url) }
        let latestTrack = second.track
        await reader.succeed(second.url, with: latestTrack)
        await newTask.value
        XCTAssertEqual(model.tracks, [latestTrack])
        XCTAssertFalse(model.isImporting)
        await reader.succeed(first.url, with: first.track)
        await oldTask.value
        XCTAssertEqual(model.tracks, [latestTrack])
        XCTAssertEqual(playback.currentTrack?.id, latestTrack.id)
        XCTAssertNil(model.importError)
        try await eventually { playback.status == .playing }
        XCTAssertEqual(playback.duration, 5, accuracy: 0.05)
    }

    func testCancelReadDoesNotChangeCurrentTrackOrDisplayError() async throws {
        let fixture = try AudioFixture(duration: 2)
        defer { fixture.remove() }
        let reader = ControlledReader()
        let playback = PlaybackController(connectSystemMedia: false)
        let model = AppModel(playback: playback, fileReader: reader)
        defer { model.shutdown() }
        let task = model.importFile(fixture.url)
        try await eventually { await reader.hasRequest(fixture.url) }
        model.cancelImport()
        await reader.succeed(fixture.url, with: fixture.track)
        await task.value
        XCTAssertFalse(model.isImporting)
        XCTAssertTrue(model.tracks.isEmpty)
        XCTAssertNil(model.importError)
        XCTAssertNil(playback.currentTrack)
    }

    func testReadFailurePreservesPreviouslySelectedTrack() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        let model = AppModel(playback: playback)
        defer { model.shutdown() }
        await model.importFile(fixture.url).value
        let original = model.tracks
        await model.importFile(fixture.directory.appendingPathComponent("missing.wav")).value
        XCTAssertEqual(model.tracks, original)
        XCTAssertEqual(playback.currentTrack, original.first)
        XCTAssertNotNil(model.importError)
        XCTAssertFalse(model.isImporting)
    }

    func testPlaybackPauseSeekResumeNaturalEndAndReplay() async throws {
        let fixture = try AudioFixture(duration: 3)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        defer { playback.shutdown() }
        playback.volume = 0
        let track = try await AudioFileReader().read(fixture.url)
        playback.play(track, in: [track])
        try await eventually { playback.status == .playing && playback.elapsed > 0 }
        playback.pause()
        XCTAssertEqual(playback.status, .paused)
        XCTAssertFalse(playback.wantsToPlay)
        playback.seek(to: 1.5)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(playback.elapsed, 1.5, accuracy: 0.08)
        XCTAssertEqual(playback.status, .paused)
        playback.seek(to: 2.8)
        playback.resume()
        try await eventually { playback.status == .ended }
        XCTAssertEqual(playback.elapsed, 3, accuracy: 0.05)
        XCTAssertFalse(playback.wantsToPlay)
        playback.resume()
        try await eventually { playback.status == .playing && playback.elapsed < 1 }
        XCTAssertTrue(playback.wantsToPlay)
    }

    func testRapidTrackChangesIgnoreOldStatusAndSeekCallbacks() async throws {
        let first = try AudioFixture(duration: 2)
        let second = try AudioFixture(duration: 5)
        defer { first.remove(); second.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        defer { playback.shutdown() }
        playback.volume = 0
        playback.play(first.track, in: [first.track])
        try await eventually { playback.canSeek }
        playback.seek(to: 1.8)
        playback.play(second.track, in: [second.track])
        try await eventually { playback.status == .playing }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(playback.currentTrack?.id, second.track.id)
        XCTAssertEqual(playback.duration, 5, accuracy: 0.05)
        XCTAssertLessThan(playback.elapsed, 1)
        XCTAssertNil(playback.errorMessage)
    }

    func testMissingFileReportsFailureAndShutdownIsIdempotent() async throws {
        let fixture = try AudioFixture(duration: 2)
        let track = fixture.track
        fixture.remove()
        let playback = PlaybackController(connectSystemMedia: false)
        playback.play(track, in: [track])
        XCTAssertEqual(playback.status, .failed)
        XCTAssertNotNil(playback.errorMessage)
        XCTAssertFalse(playback.canToggle)
        playback.shutdown()
        playback.shutdown()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(playback.status, .idle)
        XCTAssertNil(playback.currentTrack)
        XCTAssertEqual(playback.elapsed, 0)
    }

    func testControllerDeinitializesAndVolumeStaysInRange() {
        weak var released: PlaybackController?
        do {
            let playback = PlaybackController(connectSystemMedia: false)
            released = playback
            playback.volume = 2
            XCTAssertEqual(playback.volume, 1)
            playback.volume = -1
            XCTAssertEqual(playback.volume, 0)
            playback.volume = .nan
            XCTAssertTrue(playback.volume.isFinite)
        }
        XCTAssertNil(released)
    }

    private func eventually(timeout: Duration = .seconds(5), _ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !(await condition()) {
            if ContinuousClock.now >= deadline {
                XCTFail("等待状态更新超时")
                throw WaitError.timeout
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private enum WaitError: Error { case timeout }

// 可控读取器刻意忽略取消，验证过时结果即使返回也不能覆盖新选择。
private actor ControlledReader: AudioFileReading {
    private var requests: [URL: CheckedContinuation<Track, any Error>] = [:]
    func read(_ url: URL) async throws -> Track {
        try await withCheckedThrowingContinuation { requests[url] = $0 }
    }
    func hasRequest(_ url: URL) -> Bool { requests[url] != nil }
    func succeed(_ url: URL, with track: Track) { requests.removeValue(forKey: url)?.resume(returning: track) }
}

// 在临时目录生成无版权依赖的 PCM WAV。播放器验证时音量设为零，不打扰用户。
struct AudioFixture {
    let directory: URL
    let url: URL
    let duration: Double
    var track: Track {
        Track(id: url.path, folderID: "", path: url.path, title: "fixture", artist: "未知艺术家",
              album: "未知专辑", albumArtist: "未知艺术家", duration: duration)
    }

    init(duration: Double) throws {
        self.duration = duration
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("fixture.wav")
        let sampleRate = 8000
        let sampleCount = Int(duration * Double(sampleRate))
        let dataSize = UInt32(sampleCount * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(dataSize + 36)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(dataSize)
        for index in 0..<sampleCount {
            append(Int16(sin(Double(index) * 2 * .pi * 440 / Double(sampleRate)) * 1000))
        }
        try data.write(to: url)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
