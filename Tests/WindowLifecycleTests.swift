import AppKit
import SwiftUI
import XCTest
@testable import Liquidmusic

@MainActor
final class WindowLifecycleTests: XCTestCase {
    func testRealAppKitWindowPerformCloseMiniaturizesAndRestores() async throws {
        let controller = WindowLifecycleController(activateApp: {})
        let content = Text("Liquidmusic 临时窗口验证").padding().background(WindowLifecycleBridge(controller: controller))
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "Liquidmusic 临时窗口验证"
        window.isReleasedWhenClosed = false
        defer { controller.detach(window); window.close() }
        window.orderFront(nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(window.delegate is MainWindowDelegateProxy) {
            if ContinuousClock.now >= deadline { XCTFail("真实 SwiftUI 窗口未连接委托桥"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
        window.performClose(nil)
        while !window.isMiniaturized {
            if ContinuousClock.now >= deadline { XCTFail("真实 AppKit 关窗未最小化"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(controller.restore(activate: false))
        while window.isMiniaturized || !window.isVisible {
            if ContinuousClock.now >= deadline { XCTFail("真实 AppKit 窗口未恢复"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testCloseMiniaturizesAndAttachDetachPreservesOriginalDelegate() throws {
        let controller = WindowLifecycleController(activateApp: {})
        let window = ProbeWindow()
        let original = ProbeWindowDelegate()
        window.delegate = original
        controller.attach(window)
        let proxy = try XCTUnwrap(window.delegate as? MainWindowDelegateProxy)
        controller.attach(window)
        XCTAssertTrue(window.delegate === proxy)
        XCTAssertTrue(proxy.original === original)
        XCTAssertFalse(proxy.windowShouldClose(window))
        XCTAssertEqual(window.minimizeCount, 1)
        XCTAssertEqual(original.closeCount, 1)
        XCTAssertFalse(proxy.windowShouldClose(window))
        XCTAssertEqual(window.minimizeCount, 1)
        // 调用代理未实现的可选 Objective-C 委托方法，确认转发保留 SwiftUI 的行为。
        window.delegate?.windowDidBecomeKey?(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        XCTAssertEqual(original.becameKeyCount, 1)
        controller.detach(window)
        XCTAssertTrue(window.delegate === original)
    }

    func testOriginalVetoAndAnotherDelegateAreRespected() {
        let controller = WindowLifecycleController(activateApp: {})
        let window = ProbeWindow(), original = ProbeWindowDelegate(), replacement = ProbeWindowDelegate()
        original.allowsClose = false
        window.delegate = original
        controller.attach(window)
        XCTAssertFalse(window.delegate?.windowShouldClose?(window) ?? true)
        XCTAssertEqual(window.minimizeCount, 0)
        window.delegate = replacement
        controller.detach(window)
        XCTAssertTrue(window.delegate === replacement)
    }

    func testDockAndMenuRestoreSameWindowAndTerminationAllowsRealClose() throws {
        var activations = 0
        let controller = WindowLifecycleController(activateApp: { activations += 1 })
        let window = ProbeWindow()
        controller.attach(window)
        let delegate = LiquidmusicAppDelegate()
        delegate.windows = controller
        XCTAssertFalse(window.delegate?.windowShouldClose?(window) ?? true)
        XCTAssertTrue(controller.restore())
        XCTAssertEqual(window.restoreCount, 1)
        XCTAssertEqual(window.frontCount, 1)
        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true))
        XCTAssertEqual(window.frontCount, 2)
        XCTAssertEqual(activations, 2)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
        XCTAssertTrue(window.delegate?.windowShouldClose?(window) ?? false)
        XCTAssertFalse(controller.restore())
        controller.detach(window)
    }

    func testFullScreenCloseWaitsForExitAndRestoreCancelsPendingMinimize() {
        let controller = WindowLifecycleController(activateApp: {})
        let window = ProbeWindow()
        controller.attach(window)
        let proxy = window.delegate as! MainWindowDelegateProxy
        window.simulatesFullScreen = true
        XCTAssertFalse(proxy.windowShouldClose(window))
        XCTAssertEqual(window.fullScreenToggleCount, 1)
        XCTAssertEqual(window.minimizeCount, 0)
        proxy.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
        XCTAssertEqual(window.minimizeCount, 1)
        _ = proxy.windowShouldClose(window)
        controller.restore()
        proxy.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
        XCTAssertEqual(window.minimizeCount, 1)
        controller.detach(window)
    }

    func testClosingAndRestoringWindowDoesNotInterruptSharedPlayer() async throws {
        let fixture = try AudioFixture(duration: 6)
        defer { fixture.remove() }
        let playback = PlaybackController(connectSystemMedia: false)
        playback.volume = 0
        defer { playback.shutdown() }
        playback.play(fixture.track, in: [fixture.track])
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !playback.isPlaying {
            if ContinuousClock.now >= deadline { XCTFail("等待播放器超时"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let controller = WindowLifecycleController(activateApp: {})
        let window = ProbeWindow()
        controller.attach(window)
        let current = playback.queue.currentEntryID
        XCTAssertFalse(window.delegate?.windowShouldClose?(window) ?? true)
        while playback.elapsed == 0 {
            if ContinuousClock.now >= deadline { XCTFail("最小化后播放进度未继续"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(playback.isPlaying)
        XCTAssertGreaterThan(playback.elapsed, 0)
        XCTAssertTrue(controller.restore())
        XCTAssertEqual(playback.queue.currentEntryID, current)
        XCTAssertTrue(playback.wantsToPlay)
        controller.detach(window)
    }

    func testRegistryDoesNotRetainClosedWindowAndReopenFallsBackToSwiftUI() {
        let controller = WindowLifecycleController(activateApp: {})
        weak var released: ProbeWindow?
        autoreleasepool {
            let window = ProbeWindow()
            released = window
            controller.attach(window)
        }
        XCTAssertNil(released)
        XCTAssertFalse(controller.restore())
        let delegate = LiquidmusicAppDelegate()
        delegate.windows = controller
        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        XCTAssertTrue(AppRuntime.isIsolated)
    }
}

@MainActor
private final class ProbeWindow: NSWindow {
    var minimizeCount = 0, restoreCount = 0, frontCount = 0, fullScreenToggleCount = 0
    var simulatesFullScreen = false
    private var minimized = false
    init() {
        super.init(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
    }
    override var isMiniaturized: Bool { minimized }
    override var styleMask: NSWindow.StyleMask {
        get { simulatesFullScreen ? super.styleMask.union(.fullScreen) : super.styleMask }
        set { super.styleMask = newValue }
    }
    override func miniaturize(_ sender: Any?) { minimizeCount += 1; minimized = true }
    override func deminiaturize(_ sender: Any?) { restoreCount += 1; minimized = false }
    override func makeKeyAndOrderFront(_ sender: Any?) { frontCount += 1 }
    override func toggleFullScreen(_ sender: Any?) { fullScreenToggleCount += 1 }
}

@MainActor
private final class ProbeWindowDelegate: NSObject, NSWindowDelegate {
    var allowsClose = true
    var closeCount = 0, becameKeyCount = 0
    func windowShouldClose(_ sender: NSWindow) -> Bool { closeCount += 1; return allowsClose }
    func windowDidBecomeKey(_ notification: Notification) { becameKeyCount += 1 }
}
