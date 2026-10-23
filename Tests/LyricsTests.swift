import AVFoundation
import XCTest
@testable import Liquidmusic

@MainActor
final class LyricsTests: XCTestCase {
    func testMultipleTimestampsTranslationsOffsetsAndLookup() throws {
        let document = try XCTUnwrap(LyricsParser.parse("""
        [ti:示例]
        [00:20.125][00:04.50]重复的一句
        [00:04.50]同时间的译文
        [00:10.00]
        [offset:+500]
        """))
        XCTAssertEqual(document.lines.map(\.time), [4, 9.5, 19.625])
        XCTAssertEqual(document.lines[0].text, "重复的一句\n同时间的译文")
        XCTAssertEqual(document.lines[1].text, "")
        XCTAssertNil(document.activeLine(at: 3.99))
        XCTAssertEqual(document.activeLine(at: 4), 0)
        XCTAssertEqual(document.activeLine(at: 10), 1)
        XCTAssertEqual(document.activeLine(at: 90), 2)
        XCTAssertEqual(document.activeLine(at: 5), 0)
        XCTAssertNil(document.activeLine(at: .nan))
        let delayed = try XCTUnwrap(LyricsParser.parse("[offset:-1000]\n[00:00.25]延后"))
        XCTAssertEqual(delayed.lines.first?.time, 1.25)
    }

    func testPlainTextBOMMetadataEmptyAndMalformedTime() throws {
        let plain = try XCTUnwrap(LyricsParser.parse("\u{FEFF}[ti:标题]\r\n第一行\r\n第二行"))
        XCTAssertEqual(plain.plainText, "第一行\n第二行")
        XCTAssertTrue(plain.lines.isEmpty)
        XCTAssertNil(try LyricsParser.parse("[ti:标题]\n[00:70]无效时间\n[00:01.00]"))
        XCTAssertNil(try LyricsParser.parse(" \n"))
        let zero = try XCTUnwrap(LyricsParser.parse("[offset:2000]\n[00:01]开头"))
        XCTAssertEqual(zero.lines[0].time, 0)
        XCTAssertThrowsError(try LyricsParser.parse(String(repeating: "字", count: 400_000)))
        XCTAssertThrowsError(try LyricsParser.parse(String(repeating: "[00:01]一行\n", count: 10_001)))
        XCTAssertThrowsError(try LyricsParser.parse(String(repeating: "[00:01]", count: 1_000) + String(repeating: "字", count: 400)))
    }

    func testReaderUsesSidecarAndSupportsUTF16AndSizeLimit() async throws {
        let fixture = try AudioFixture(duration: 2)
        defer { fixture.remove() }
        let sidecar = fixture.track.url.deletingPathExtension().appendingPathExtension("lrc")
        try Data("[00:00.25]本地歌词".utf8).write(to: sidecar)
        let reader = LyricsReader()
        let result = try await reader.read(for: fixture.track)
        XCTAssertEqual(result?.lines.first?.text, "本地歌词")
        let utf16 = fixture.directory.appendingPathComponent("utf16.lrc")
        try XCTUnwrap("[00:01]中文歌词".data(using: .utf16)).write(to: utf16)
        let decoded = try await reader.readFile(utf16)
        XCTAssertEqual(decoded?.lines.first?.text, "中文歌词")
        let oversized = fixture.directory.appendingPathComponent("large.lrc")
        try Data(repeating: 65, count: 1_048_577).write(to: oversized)
        do { _ = try await reader.readFile(oversized); XCTFail("超限文件必须拒绝") }
        catch LyricsError.tooLarge { }
        let invalid = fixture.directory.appendingPathComponent("broken.lrc")
        try Data([0xFF, 0x00, 0xFE]).write(to: invalid)
        do { _ = try await reader.readFile(invalid); XCTFail("损坏编码必须拒绝") }
        catch LyricsError.encoding { }
    }

    func testEmbeddedLyricsAndMissingLyricsUsingTemporaryAudio() async throws {
        let fixture = try AudioFixture(duration: 1)
        defer { fixture.remove() }
        let reader = LyricsReader()
        let missing = try await reader.read(for: fixture.track)
        XCTAssertNil(missing)
        let output = fixture.directory.appendingPathComponent("embedded.m4a")
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: fixture.track.url),
                                                       presetName: AVAssetExportPresetAppleM4A))
        let lyrics = AVMutableMetadataItem()
        lyrics.identifier = .iTunesMetadataLyrics
        lyrics.value = "第一行内嵌歌词\n第二行内嵌歌词" as NSString
        exporter.metadata = [lyrics]
        try await exporter.export(to: output, as: .m4a)
        var track = fixture.track
        track.path = output.path
        let document = try await reader.read(for: track)
        XCTAssertEqual(document?.plainText, "第一行内嵌歌词\n第二行内嵌歌词")
        XCTAssertEqual(document?.source, "内嵌歌词")
        let brokenSidecar = output.deletingPathExtension().appendingPathExtension("lrc")
        try Data([0xFF, 0x00, 0xFE]).write(to: brokenSidecar)
        let fallback = try await reader.read(for: track)
        XCTAssertEqual(fallback, document)
    }

    func testLateLoadsAndCancellationCannotReplaceNewSong() async throws {
        let reader = DelayedLyricsReader()
        let model = LyricsModel(reader: reader)
        let first = Task { await model.load(track: SPXData.tracks[0]) }
        try await waitFor(1, reader: reader)
        let second = Task { await model.load(track: SPXData.tracks[1]) }
        try await waitFor(2, reader: reader)
        await reader.finish(index: 1, text: "新曲")
        await second.value
        await reader.finish(index: 0, text: "旧曲")
        await first.value
        XCTAssertEqual(model.document?.plainText, "新曲")
        let pending = Task { await model.load(track: SPXData.tracks[2]) }
        try await waitFor(3, reader: reader)
        model.cancel()
        await reader.finish(index: 2, text: "关闭后到达")
        await pending.value
        XCTAssertNil(model.document)
        XCTAssertFalse(model.isLoading)
    }

    func testReaderErrorAndExplicitEmptySelectionAreVisible() async {
        let model = LyricsModel(reader: EmptyLyricsReader())
        await model.load(track: SPXData.tracks[0])
        XCTAssertNil(model.document)
        XCTAssertNil(model.error)
        await model.load(track: SPXData.tracks[0], file: URL(fileURLWithPath: "/unused"))
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.isLoading)
    }

    private func waitFor(_ count: Int, reader: DelayedLyricsReader) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while await reader.count < count {
            if ContinuousClock.now > deadline { throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor DelayedLyricsReader: LyricsReading {
    private var continuations: [Int: CheckedContinuation<LyricsDocument?, Never>] = [:]
    private(set) var count = 0
    func read(for track: Track) async throws -> LyricsDocument? {
        let index = count
        count += 1
        return await withCheckedContinuation { continuations[index] = $0 }
    }
    func readFile(_ url: URL) async throws -> LyricsDocument? { nil }
    func finish(index: Int, text: String) {
        continuations.removeValue(forKey: index)?.resume(returning: LyricsDocument(plainText: text))
    }
}

private struct EmptyLyricsReader: LyricsReading {
    func read(for track: Track) async throws -> LyricsDocument? { nil }
    func readFile(_ url: URL) async throws -> LyricsDocument? { nil }
}
