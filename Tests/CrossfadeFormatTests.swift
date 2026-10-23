import AVFoundation
import XCTest
@testable import Liquidmusic

@MainActor
final class CrossfadeFormatTests: XCTestCase {
    func testWAVToM4AAndM4AToWAVOverlapWithDifferentDecoders() async throws {
        let fixture = try AudioFixture(duration: 8)
        defer { fixture.remove() }
        let output = fixture.directory.appendingPathComponent("converted.m4a")
        let session = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: fixture.url),
                                                       presetName: AVAssetExportPresetAppleM4A))
        try await session.export(to: output, as: .m4a)
        let reader = AudioFileReader()
        let compressed = try await reader.read(output)
        XCTAssertGreaterThan(compressed.duration, 7)
        try await verifyTransition(from: fixture.track, to: compressed)
        try await verifyTransition(from: compressed, to: fixture.track)
    }

    func testWAVToShortMP3ShortensOverlapWithoutSkippingEntry() async throws {
        let fixture = try AudioFixture(duration: 8)
        defer { fixture.remove() }
        let output = fixture.directory.appendingPathComponent("short.mp3")
        try FileManager.default.copyItem(at: resource("tagged", ext: "mp3"), to: output)
        let compressed = try await AudioFileReader().read(output)
        XCTAssertLessThan(compressed.duration, 1)
        try await verifyTransition(from: fixture.track, to: compressed)
    }

    func testWAVToFLACUsesActualPlatformDecodeCapability() async throws {
        let fixture = try AudioFixture(duration: 8)
        defer { fixture.remove() }
        let output = fixture.directory.appendingPathComponent("short.flac")
        try FileManager.default.copyItem(at: resource("tone", ext: "flac"), to: output)
        let compressed: Track
        do { compressed = try await AudioFileReader().read(output) }
        catch AudioFileError.unsupported { throw XCTSkip("本机 AVFoundation 不支持此 FLAC 素材。") }
        // 元数据可读不等于解码成功；先独立播放完整素材，区分平台拒绝与渐变回归。
        let probe = PlaybackController(connectSystemMedia: false)
        probe.volume = 0
        defer { probe.shutdown() }
        probe.play(compressed, in: [compressed])
        try await eventually { probe.status == .ended || probe.status == .failed }
        if probe.status == .ended {
            try await verifyTransition(from: fixture.track, to: compressed)
        } else {
            XCTAssertNotNil(probe.errorMessage)
            try await verifyFailedPreparation(from: fixture.track, to: compressed)
        }
    }

    func testCorruptPreparedAudioDoesNotInterruptOrSkipPastFailedEntry() async throws {
        let fixture = try AudioFixture(duration: 4)
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("corrupt.m4a")
        try Data("损坏的音频测试数据".utf8).write(to: url, options: .withoutOverwriting)
        var broken = fixture.track
        broken.id = "corrupt"
        broken.path = url.path
        try await verifyFailedPreparation(from: fixture.track, to: broken)
    }

    private func verifyFailedPreparation(from outgoing: Track, to broken: Track) async throws {
        var last = outgoing
        last.id = "last"
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        playback.configureCrossfade(enabled: true, duration: 2)
        playback.play(outgoing, in: [outgoing, broken, last])
        try await eventually { playback.isPlaying }
        playback.seek(to: outgoing.duration - 1.9)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.currentTrack?.id, outgoing.id)
        XCTAssertFalse(playback.isCrossfading)
        XCTAssertNil(playback.errorMessage)
        try await eventually { playback.status == .failed }
        XCTAssertEqual(playback.currentTrack?.id, broken.id)
        XCTAssertEqual(playback.queue.historyEntries.map(\.track.id), [outgoing.id])
        XCTAssertEqual(playback.queue.upcomingEntries.map(\.track.id), [last.id])
        XCTAssertNotNil(playback.errorMessage)
    }

    private func verifyTransition(from outgoing: Track, to incoming: Track) async throws {
        var players: [AVPlayer] = []
        let playback = PlaybackController(connectSystemMedia: false) {
            let player = AVPlayer()
            player.isMuted = true
            players.append(player)
            return player
        }
        defer { playback.shutdown() }
        playback.volume = 0.8
        playback.configureCrossfade(enabled: true, duration: 2)
        playback.play(outgoing, in: [outgoing, incoming])
        let entryID = playback.queue.entries[1].id
        let expectedOverlap = min(2, outgoing.duration / 2, incoming.duration / 2)
        XCTAssertGreaterThan(expectedOverlap, 0.1)
        try await eventually { playback.isPlaying }
        // 留出准备时间，再由音频时钟自然进入重叠区；不修改用户文件。
        playback.seek(to: outgoing.duration - expectedOverlap - 0.4)
        try await eventually { playback.isCrossfading && playback.isPlaying }
        XCTAssertEqual(playback.queue.currentEntryID, entryID)
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players[0].volume + players[1].volume, 0.8, accuracy: 0.02)
        try await eventually { !playback.isCrossfading }
        XCTAssertEqual(playback.queue.currentEntryID, entryID)
        XCTAssertNil(players[0].currentItem)
        XCTAssertEqual(players[1].volume, 0.8, accuracy: 0.001)
        XCTAssertEqual(playback.queue.historyEntries.count, 1)
        XCTAssertNil(playback.errorMessage)
    }

    private func resource(_ name: String, ext: String) throws -> URL {
        let bundle = Bundle(for: CrossfadeFormatTests.self)
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
                             ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    private func eventually(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(6)
        while !condition() {
            if ContinuousClock.now >= deadline { XCTFail("等待格式切换超时"); throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
