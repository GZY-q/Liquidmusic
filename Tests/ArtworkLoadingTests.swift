import AppKit
import XCTest
@testable import Liquidmusic

@MainActor
final class ArtworkLoadingTests: XCTestCase {
    func testThumbnailsSharePixelsAndKeepLargeArtworkSeparate() async throws {
        let bytes = try coverData()
        let cache = ArtworkThumbnailCache()
        let smallResult = await cache.image(data: bytes, maximumPixelSize: 64)
        let small = try XCTUnwrap(smallResult)
        let repeated = await cache.image(data: bytes, maximumPixelSize: 64)
        let largeResult = await cache.image(data: bytes, maximumPixelSize: 512)
        let large = try XCTUnwrap(largeResult)
        XCTAssertTrue(small === repeated)
        XCTAssertEqual(small.width, 64)
        XCTAssertEqual(large.width, 512)
        XCTAssertLessThan(small.bytesPerRow * small.height, large.bytesPerRow * large.height / 32)
        let invalid = await cache.image(data: Data("broken".utf8), maximumPixelSize: 64)
        XCTAssertNil(invalid)
    }

    func testRepeatedArtworkDecodeCostAndPixelStorage() async throws {
        let bytes = try coverData()
        // 使用已有 512 像素缓存格式比较，避免拿原始大图夸大产品收益。
        let sourceCache = ArtworkThumbnailCache()
        let sourceResult = await sourceCache.image(data: bytes, maximumPixelSize: 512)
        let source = try XCTUnwrap(sourceResult)
        let jpeg = try XCTUnwrap(NSBitmapImageRep(cgImage: source).representation(using: .jpeg, properties: [:]))
        var original: [CGImage] = []
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 {
            let image = try XCTUnwrap(NSImage(data: jpeg))
            XCTAssertTrue(image.isValid)
            original.append(try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        }
        let originalTime = ProcessInfo.processInfo.systemUptime - start
        let cache = ArtworkThumbnailCache()
        var thumbnails: [CGImage] = []
        let cachedStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 {
            let result = await cache.image(data: jpeg, maximumPixelSize: 64)
            thumbnails.append(try XCTUnwrap(result))
        }
        let cachedTime = ProcessInfo.processInfo.systemUptime - cachedStart
        XCTAssertTrue(thumbnails.allSatisfy { $0 === thumbnails[0] })
        let oldPixels = original.reduce(0) { $0 + $1.bytesPerRow * $1.height }
        let newPixels = thumbnails[0].bytesPerRow * thumbnails[0].height
        print("ARTWORK_PERF repeated100 originalSeconds=\(originalTime) cachedSeconds=\(cachedTime) originalPixelBytes=\(oldPixels) sharedPixelBytes=\(newPixels)")
        // 时间仅作观测，像素上界和共享身份才是稳定断言；不把像素字节当成整个 App 的 RSS。
        XCTAssertLessThan(newPixels, oldPixels / 100)
    }

    func testMissingAndBrokenImagesFallBackInOrderAndStopAfterSuccess() async throws {
        let loader = RecordingArtworkLoader(data: ["broken": Data("坏图片".utf8), "valid": try coverData()])
        let state = ArtworkLoadingState()
        await state.load(paths: ["missing", "broken", "valid", "unused"], using: { await loader.read($0) })
        XCTAssertEqual(state.resolvedPath, "valid")
        XCTAssertNotNil(state.image)
        let reads = await loader.reads
        XCTAssertEqual(reads, ["missing", "broken", "valid"])
    }

    func testAllFailedAndEmptyRequestsClearPreviousImage() async throws {
        let bytes = try coverData()
        let state = ArtworkLoadingState()
        await state.load(paths: ["valid"], using: { _ in bytes })
        XCTAssertNotNil(state.image)
        await state.load(paths: ["missing", "broken"], using: { $0 == "broken" ? Data("坏图片".utf8) : nil })
        XCTAssertNil(state.image)
        XCTAssertNil(state.resolvedPath)
        XCTAssertEqual(state.paths, ["missing", "broken"])
        await state.load(paths: ["valid"], using: { _ in bytes })
        await state.load(paths: [], using: { _ in XCTFail("空请求不能加载图片"); return nil })
        XCTAssertTrue(state.paths.isEmpty)
        XCTAssertNil(state.image)
        XCTAssertNil(state.resolvedPath)
    }

    func testChangedSecondCandidateWithSameFirstPathLoadsNewCover() async throws {
        let bytes = try coverData()
        let state = ArtworkLoadingState()
        let loader = RecordingArtworkLoader(data: ["old": bytes, "new": bytes])
        await state.load(paths: ["missing", "old"], using: { await loader.read($0) })
        XCTAssertEqual(state.resolvedPath, "old")
        await state.load(paths: ["missing", "new"], using: { await loader.read($0) })
        XCTAssertEqual(state.paths, ["missing", "new"])
        XCTAssertEqual(state.resolvedPath, "new")
    }

    func testLateSuccessfulRequestCannotReplaceNewerCoverWithoutTaskCancellation() async throws {
        let loader = ControlledArtworkLoader()
        let state = ArtworkLoadingState()
        let old = Task { await state.load(paths: ["old"], using: { await loader.read($0) }) }
        try await waitFor("old", in: loader)
        let bytes = try coverData()
        await state.load(paths: ["new"], using: { _ in bytes })
        let currentImage = state.image
        await loader.complete("old", data: bytes)
        await old.value
        XCTAssertEqual(state.resolvedPath, "new")
        XCTAssertTrue(state.image === currentImage)
    }

    func testOldImageClearsWhileNewRequestWaitsAndCancellationRejectsLateBytes() async throws {
        let bytes = try coverData()
        let loader = ControlledArtworkLoader()
        let state = ArtworkLoadingState()
        await state.load(paths: ["original"], using: { _ in bytes })
        let waiting = Task { await state.load(paths: ["slow", "unused"], using: { await loader.read($0) }) }
        try await waitFor("slow", in: loader)
        XCTAssertNil(state.image)
        waiting.cancel()
        await loader.complete("slow", data: bytes)
        await waiting.value
        XCTAssertNil(state.image)
        XCTAssertNil(state.resolvedPath)
        let reads = await loader.reads
        XCTAssertEqual(reads, ["slow"])
    }

    func testDisappearanceInvalidatesPendingLoadAndPreventsFallback() async throws {
        let loader = ControlledArtworkLoader()
        let state = ArtworkLoadingState()
        let waiting = Task { await state.load(paths: ["slow", "unused"], using: { await loader.read($0) }) }
        try await waitFor("slow", in: loader)
        state.cancel()
        await loader.complete("slow", data: nil)
        await waiting.value
        XCTAssertNil(state.image)
        XCTAssertTrue(state.paths.isEmpty)
        let reads = await loader.reads
        XCTAssertEqual(reads, ["slow"])
    }

    func testCancelledOldTaskCannotClearNewerImageWhenItFinallyStarts() async throws {
        let bytes = try coverData()
        let state = ArtworkLoadingState()
        await state.load(paths: ["new"], using: { _ in bytes })
        let old = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await state.load(paths: ["old"], using: { _ in XCTFail("取消任务不能读取图片"); return nil })
        }
        await old.value
        XCTAssertEqual(state.resolvedPath, "new")
        XCTAssertEqual(state.paths, ["new"])
        XCTAssertNotNil(state.image)
    }

    private func waitFor(_ path: String, in loader: ControlledArtworkLoader) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await loader.contains(path)) {
            if ContinuousClock.now >= deadline { throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func coverData() throws -> Data {
        let bundle = Bundle(for: ArtworkLoadingTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "cover", withExtension: "jpg")
                                ?? bundle.url(forResource: "cover", withExtension: "jpg", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

private actor RecordingArtworkLoader {
    let data: [String: Data]
    private(set) var reads: [String] = []
    init(data: [String: Data]) { self.data = data }
    func read(_ path: String) -> Data? { reads.append(path); return data[path] }
}

// 刻意忽略 Task 取消，让测试验证 generation 与取消双重防护。
private actor ControlledArtworkLoader {
    private var pending: [String: CheckedContinuation<Data?, Never>] = [:]
    private(set) var reads: [String] = []
    func read(_ path: String) async -> Data? {
        reads.append(path)
        return await withCheckedContinuation { pending[path] = $0 }
    }
    func contains(_ path: String) -> Bool { pending[path] != nil }
    func complete(_ path: String, data: Data?) { pending.removeValue(forKey: path)?.resume(returning: data) }
}
