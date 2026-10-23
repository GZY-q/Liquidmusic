import AppKit
import Darwin
import SwiftUI
import XCTest
@testable import Liquidmusic

@MainActor
final class PlaybackRenderingPerformanceTests: XCTestCase {
    func testVisibleLibraryPlaybackCPU() async throws {
        let fixture = try AudioFixture(duration: 90)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        playback.connectSystemMedia(transport: RecordingMediaTransport())
        let tracks = (0..<1_000).map { index in
            var track = fixture.track
            track.id = "sample-\(index)"
            track.title = "采样歌曲 \(index)"
            // 其余索引只参与展示；不同路径避免所有行都被识别成当前歌曲。
            if index > 0 { track.path = fixture.directory.appendingPathComponent("mock-\(index).wav").path }
            return track
        }
        let model = AppModel(playback: playback, tracks: tracks)
        let view = ContentView(model: model, browser: .preview(tracks: tracks))
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1100, height: 680))
        window.title = "Liquidmusic 隔离性能采样"
        defer { window.close(); model.shutdown() }
        window.orderFront(nil)
        playback.play(tracks[0], in: tracks)
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(playback.isPlaying)
        let content = try XCTUnwrap(window.contentView)
        func dragArea(in view: NSView) -> WindowDragArea.DragView? {
            if let drag = view as? WindowDragArea.DragView { return drag }
            return view.subviews.lazy.compactMap { dragArea(in: $0) }.first
        }
        let drag = try XCTUnwrap(dragArea(in: content))
        XCTAssertEqual(drag.bounds.height, 24, accuracy: 0.5)
        XCTAssertEqual(drag.bounds.width, content.bounds.width, accuracy: 0.5)
        XCTAssertTrue(drag.mouseDownCanMoveWindow)
        print("WINDOW_DRAG frame=\(drag.convert(drag.bounds, to: content)) content=\(content.bounds)")

        // 曲尾距离足够远，不准备第二路播放器；比较开启/关闭渐变的检测开销。
        // ABBA 顺序降低预热偏差；不将机器负载相关的 CPU 百分比作为通过阈值。
        for precise in [true, false, false, true] {
            playback.configureCrossfade(enabled: precise, duration: 1)
            try await Task.sleep(for: .milliseconds(500))
            let cpuStart = cpuSeconds()
            let wallStart = ProcessInfo.processInfo.systemUptime
            try await Task.sleep(for: .seconds(4))
            let wall = ProcessInfo.processInfo.systemUptime - wallStart
            let percent = (cpuSeconds() - cpuStart) / wall * 100
            print("PLAYBACK_CPU crossfade=\(precise) percent=\(percent) wall=\(wall)")
            XCTAssertTrue(playback.isPlaying)
            XCTAssertFalse(playback.isCrossfading)
        }
        playback.pause()
        try await Task.sleep(for: .milliseconds(500))
        let cpuStart = cpuSeconds()
        let wallStart = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(for: .seconds(4))
        let percent = (cpuSeconds() - cpuStart) / (ProcessInfo.processInfo.systemUptime - wallStart) * 100
        print("PLAYBACK_CPU paused percent=\(percent)")
        XCTAssertEqual(playback.status, .paused)
    }

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}
