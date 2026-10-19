import XCTest

final class LiquidmusicUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        // 断言中止时也结束本轮启动的隔离 App，不遗留测试窗口。
        let url = appURL
        await MainActor.run { XCUIApplication(url: url).terminate() }
    }

    private var appURL: URL {
        // 指定同一构建目录的 App，避免启动其他 DerivedData 中同标识的 Preview/运行实例。
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Liquidmusic.app")
    }

    @MainActor func testCommandFFocusesSearchAndEscapeClearsQuery() {
        let app = launchIsolatedApp()
        defer { app.terminate() }
        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        // 不点击输入框，验证真实菜单快捷键能够把键盘焦点交给搜索。
        app.typeKey("f", modifierFlags: .command)
        app.typeText("Liquidmusic UI")
        XCTAssertEqual(search.value as? String, "Liquidmusic UI")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(search.value as? String, "")
        attach(app, name: "搜索快捷键与清除")
    }

    @MainActor func testQueuePanelAdaptsFromWideToNarrow() {
        let app = launchIsolatedApp()
        defer { app.terminate() }
        resize(app.windows["main"], width: 1_000)
        let queue = app.buttons["player.queue"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        queue.click()
        XCTAssertTrue(app.staticTexts["队列为空"].waitForExistence(timeout: 5))
        attach(app, name: "队列展开")
        queue.click()
        XCTAssertTrue(app.staticTexts["队列为空"].waitForNonExistence(timeout: 5))
        queue.click()
        XCTAssertTrue(app.staticTexts["队列为空"].waitForExistence(timeout: 5))
        resize(app.windows["main"], width: 640)
        XCTAssertTrue(app.staticTexts["队列为空"].waitForNonExistence(timeout: 5))
        queue.click()
        XCTAssertTrue(app.staticTexts["队列为空"].waitForExistence(timeout: 5))
        app.buttons["完成"].click()
        XCTAssertTrue(app.staticTexts["队列为空"].waitForNonExistence(timeout: 5))
    }

    @MainActor func testCommandFRestoresHiddenSidebarAndFocus() {
        let app = launchIsolatedApp()
        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        app.toolbars.buttons["Hide Sidebar"].click()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        app.typeText("restored")
        XCTAssertEqual(search.value as? String, "restored")
        attach(app, name: "隐藏边栏后搜索")
    }

    @MainActor func testNarrowWindowKeepsVolumeAndQueueReachable() {
        let app = launchIsolatedApp()
        let window = app.windows["main"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        resize(window, width: 640)
        XCTAssertEqual(window.frame.width, 640, accuracy: 4)
        let volume = app.buttons["音量"]
        XCTAssertTrue(volume.waitForExistence(timeout: 5))
        XCTAssertTrue(volume.isHittable)
        volume.click()
        XCTAssertTrue(app.sliders["音量"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sliders["音量"].waitForNonExistence(timeout: 5))
        // macOS 原生文字菜单通过 AXTitle 命名，避免系统把模式读作图标的英文名称。
        XCTAssertEqual(app.menuButtons["player.mode"].title, "播放模式")
        XCTAssertEqual(app.menuButtons["player.mode"].value as? String, "顺序播放")
        let queue = app.buttons["player.queue"]
        XCTAssertTrue(queue.isHittable)
        queue.click()
        XCTAssertTrue(app.staticTexts["队列为空"].waitForExistence(timeout: 5))
        attach(app, name: "窄窗口音量与队列")
        app.buttons["完成"].click()
        XCTAssertTrue(app.staticTexts["队列为空"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(queue.isHittable)
    }

    @MainActor private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication(url: appURL)
        // 显式传给被测 App，不能只依赖测试 runner 的环境继承。
        app.launchEnvironment["LIQUIDMUSIC_TESTING"] = "1"
        // 固定系统工具栏标签语言；应用自有中文文案保持原样。
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.activate()
        return app
    }

    @MainActor private func resize(_ window: XCUIElement, width: CGFloat) {
        // 坐标只由当前窗口边界计算，拖动右下角真实调整窗口宽度。
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -1, dy: -1))
        corner.click(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: width - window.frame.width, dy: 0)))
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }
}
