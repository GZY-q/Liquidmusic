import AppKit
import SwiftUI

enum AppRuntime {
    static var isIsolated: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["LIQUIDMUSIC_TESTING"] == "1" || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }
    static let mainWindowID = "main"
}

@MainActor
final class WindowLifecycleController {
    private struct Registration {
        weak var window: NSWindow?
        let proxy: MainWindowDelegateProxy
    }
    private var registrations: [ObjectIdentifier: Registration] = [:]
    private let activateApp: @MainActor () -> Void
    var isTerminating = false

    init(activateApp: @escaping @MainActor () -> Void = { NSApplication.shared.activate() }) {
        self.activateApp = activateApp
    }

    func attach(_ window: NSWindow) {
        registrations = registrations.filter { $0.value.window != nil }
        let key = ObjectIdentifier(window)
        let proxy = registrations[key]?.proxy ?? MainWindowDelegateProxy(controller: self)
        if window.delegate !== proxy {
            proxy.original = window.delegate
            window.delegate = proxy
        }
        registrations[key] = Registration(window: window, proxy: proxy)
    }

    func detach(_ window: NSWindow) {
        guard let registration = registrations.removeValue(forKey: ObjectIdentifier(window)) else { return }
        if window.delegate === registration.proxy { window.delegate = registration.proxy.original }
    }

    @discardableResult
    func restore(activate: Bool = true) -> Bool {
        guard !isTerminating, let registration = registrations.values.first(where: { $0.window != nil }),
              let window = registration.window else { return false }
        registration.proxy.cancelPendingMinimize()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        if activate { activateApp() }
        return true
    }
}

// 只拦截关窗与全屏后最小化，其余可选委托方法继续交给 SwiftUI 原有委托。
nonisolated final class MainWindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var original: (any NSWindowDelegate)?
    @MainActor private weak var controller: WindowLifecycleController?
    @MainActor private var minimizeAfterFullScreen = false

    @MainActor init(controller: WindowLifecycleController) { self.controller = controller }

    @MainActor func cancelPendingMinimize() { minimizeAfterFullScreen = false }

    @MainActor func windowShouldClose(_ sender: NSWindow) -> Bool {
        let originalAllowsClose = original?.windowShouldClose?(sender) ?? true
        guard originalAllowsClose else { return false }
        guard let controller, !controller.isTerminating else { return true }
        if sender.styleMask.contains(.fullScreen) {
            if !minimizeAfterFullScreen { minimizeAfterFullScreen = true; sender.toggleFullScreen(nil) }
        } else if !sender.isMiniaturized {
            sender.miniaturize(nil)
        }
        return false
    }

    @MainActor func windowDidExitFullScreen(_ notification: Notification) {
        original?.windowDidExitFullScreen?(notification)
        if minimizeAfterFullScreen, controller?.isTerminating == false, let window = notification.object as? NSWindow {
            minimizeAfterFullScreen = false
            window.miniaturize(nil)
        }
    }

    // NSObject 的转发查询非隔离，只查询原委托身份，不执行窗口 UI 操作。
    nonisolated override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        return original?.responds(to: selector) ?? false
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        if let original, original.responds(to: selector) { return original }
        return super.forwardingTarget(for: selector)
    }
}

struct WindowLifecycleBridge: NSViewRepresentable {
    let controller: WindowLifecycleController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }
    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.windowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(window)
            // 等 SwiftUI 完成初始窗口配置后再核对一次，保留它最后安装的原委托。
            DispatchQueue.main.async { [weak coordinator] in coordinator?.refreshAttachment() }
        }
        return view
    }
    func updateNSView(_ view: WindowProbe, context: Context) { context.coordinator.attach(view.window) }
    static func dismantleNSView(_ view: WindowProbe, coordinator: Coordinator) {
        view.windowChanged = nil
        coordinator.attach(nil)
    }

    final class WindowProbe: NSView {
        var windowChanged: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); windowChanged?(window) }
    }

    @MainActor final class Coordinator {
        let controller: WindowLifecycleController
        private weak var window: NSWindow?
        init(controller: WindowLifecycleController) { self.controller = controller }
        func attach(_ newWindow: NSWindow?) {
            if window !== newWindow, let window { controller.detach(window) }
            window = newWindow
            if let window { controller.attach(window) }
        }
        func refreshAttachment() { if let window { controller.attach(window) } }
    }
}

@MainActor
final class LiquidmusicAppDelegate: NSObject, NSApplicationDelegate {
    var windows: WindowLifecycleController?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 返回 false 表示已经处理；找不到窗口时让 SwiftUI 执行默认重新打开。
        !(windows?.restore() ?? false)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windows?.isTerminating = true
        return .terminateNow
    }
}

struct MenuBarPlayerView: View {
    let playback: PlaybackController
    let windows: WindowLifecycleController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        MiniPlayerView(playback: playback, showWindow: {
            if !windows.restore() { openWindow(id: AppRuntime.mainWindowID); NSApplication.shared.activate() }
        }, quit: { NSApplication.shared.terminate(nil) })
    }
}
