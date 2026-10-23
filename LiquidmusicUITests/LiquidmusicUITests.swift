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

    @MainActor func testNativeSettingsShortcutSaveCancelAndTabs() {
        let app = launchIsolatedApp()
        app.typeKey(",", modifierFlags: .command)
        let toggle = app.checkBoxes["settings.crossfade"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0)
        let duration = app.sliders["settings.crossfadeDuration"]
        XCTAssertFalse(duration.isEnabled)
        toggle.click()
        XCTAssertTrue(duration.isEnabled)
        duration.adjust(toNormalizedSliderPosition: 1)
        attach(app, name: "设置播放页")
        app.buttons["取消"].click()
        XCTAssertTrue(toggle.waitForNonExistence(timeout: 5))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0)
        toggle.click()
        duration.adjust(toNormalizedSliderPosition: 1)
        app.buttons["好"].click()
        XCTAssertTrue(toggle.waitForNonExistence(timeout: 5))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
        XCTAssertTrue(app.staticTexts["12 秒"].exists)
        app.activate()
        app.buttons["settings.tab.general"].click()
        XCTAssertTrue(app.checkBoxes["在菜单栏显示迷你播放器"].waitForExistence(timeout: 5))
        attach(app, name: "设置通用页")
        app.buttons["settings.tab.files"].click()
        XCTAssertTrue(app.buttons["管理音乐文件夹…"].waitForExistence(timeout: 5))
        app.buttons["settings.tab.advanced"].click()
        XCTAssertTrue(app.sliders["启动音量"].waitForExistence(timeout: 5))
        attach(app, name: "设置高级页")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sliders["启动音量"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.windows["main"].exists)
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
        // 图标菜单仍提供中文辅助功能名称。
        let mode = app.menuButtons["player.mode"]
        XCTAssertTrue(mode.title == "播放模式" || mode.label == "播放模式")
        XCTAssertEqual(app.menuButtons["player.mode"].value as? String, "顺序播放")
        app.activate()
        let queue = app.buttons["player.queue"]
        XCTAssertTrue(queue.isHittable)
        queue.click()
        XCTAssertTrue(app.staticTexts["队列为空"].waitForExistence(timeout: 5))
        attach(app, name: "窄窗口音量与队列")
        app.buttons["完成"].click()
        XCTAssertTrue(app.staticTexts["队列为空"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(queue.isHittable)
    }

    @MainActor func testFileChooserCancellationKeepsLibraryEmpty() {
        let app = launchIsolatedApp()
        app.typeKey("o", modifierFlags: .command)
        let panel = app.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["从一首歌开始"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.buttons["显示歌词"].isEnabled)
    }

    @MainActor func testSilentFileImportAlbumArtistNavigationAndKeyboardSeek() throws {
        let fixture = try SilentUIAudioFixture()
        defer { fixture.remove() }
        let app = launchIsolatedApp()
        mute(app)
        app.typeKey("o", modifierFlags: .command)
        let panel = app.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let location = app.sheets.textFields.firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        location.click()
        location.typeKey("a", modifierFlags: .command)
        location.typeText(fixture.url.path)
        XCTAssertEqual(location.value as? String, fixture.url.path)
        location.typeKey(.return, modifierFlags: [])
        let open = panel.buttons["打开"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(open.isEnabled)
        open.click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[fixture.title].firstMatch.waitForExistence(timeout: 5))
        let pause = app.buttons["暂停"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.click()
        XCTAssertTrue(app.buttons["播放"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)

        app.staticTexts["专辑"].firstMatch.click()
        let album = app.buttons["未知专辑，未知艺术家，1 首歌曲"]
        XCTAssertTrue(album.waitForExistence(timeout: 5))
        album.click()
        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[fixture.title].firstMatch.exists)
        app.buttons["返回"].click()
        XCTAssertTrue(album.waitForExistence(timeout: 5))
        app.staticTexts["艺术家"].firstMatch.click()
        let artist = app.buttons["未知艺术家，1 首歌曲"]
        XCTAssertTrue(artist.waitForExistence(timeout: 5))
        artist.click()
        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 5))
        app.buttons["返回"].click()
        XCTAssertTrue(artist.waitForExistence(timeout: 5))

        let progress = app.sliders["播放进度"]
        XCTAssertTrue(progress.isEnabled)
        app.activate()
        // 原生 NSSlider 的默认点击点可能是当前旋钮；显式点击轨道中点。
        progress.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let time = progress
        // 先等鼠标 seek 完成，再验证方向键；避免把迟到的鼠标定位误认为键盘生效。
        let centered = NSPredicate { _, _ in
            let seconds = self.elapsedSeconds(time)
            return seconds >= 55 && seconds <= 65
        }
        expectation(for: centered, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        let before = elapsedSeconds(time)
        for _ in 0..<3 { progress.typeKey(.rightArrow, modifierFlags: []) }
        let changed = NSPredicate { _, _ in
            let difference = self.elapsedSeconds(time) - before
            return difference >= 14 && difference <= 16
        }
        expectation(for: changed, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        let advanced = elapsedSeconds(time)
        progress.typeKey(.leftArrow, modifierFlags: [])
        let reversed = NSPredicate { _, _ in
            let difference = advanced - self.elapsedSeconds(time)
            return difference >= 4 && difference <= 6
        }
        expectation(for: reversed, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["播放"].exists)
        attach(app, name: "细播放条与进度定位")
        resize(app.windows["main"], width: 640)
        app.buttons["player.nowPlaying"].click()
        XCTAssertTrue(app.otherElements["player.nowPlayingPanel"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.otherElements["player.nowPlayingPanel"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["显示歌词"].isHittable)
        XCTAssertTrue(app.buttons["player.queue"].isHittable)
        app.buttons["显示歌词"].click()
        XCTAssertTrue(app.buttons["选择歌词…"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor private func mute(_ app: XCUIApplication) {
        if app.buttons["音量"].exists { app.buttons["音量"].click() }
        let slider = app.sliders["音量"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
            .click(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)))
        if let value = slider.value as? NSNumber {
            XCTAssertEqual(value.doubleValue, 0, accuracy: 0.001)
        } else {
            XCTAssertEqual(slider.value as? String, "0%")
        }
        if app.popovers.firstMatch.exists { app.typeKey(.escape, modifierFlags: []) }
    }

    @MainActor private func elapsedSeconds(_ text: XCUIElement) -> Int {
        // NSSlider 的 AXValue 是秒数；保留原时间文本格式的兼容读取。
        if let number = text.value as? NSNumber { return Int(number.doubleValue) }
        let value = (text.value as? String) ?? text.label
        if let seconds = Double(value) { return Int(seconds) }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return -1 }
        return parts[0] * 60 + parts[1]
    }

    @MainActor private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication(url: appURL)
        // 显式传给被测 App，不能只依赖测试 runner 的环境继承。
        app.launchEnvironment["LIQUIDMUSIC_TESTING"] = "1"
        // 固定系统工具栏标签语言；应用自有中文文案保持原样。
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        // 前一用例会留下窄窗口，先恢复宽度，避免系统自动折叠侧边栏影响搜索断言。
        let window = app.windows["main"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        resize(window, width: 1_000)
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

// 新建的 PCM 数据全为零；测试不依赖用户文件、第三方音频或真实资料库。
private struct SilentUIAudioFixture {
    let directory: URL
    let url: URL
    let title = "M7 Silent Synthetic Audio With A Long Title For Album Navigation And Narrow Window Playback Controls"

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Liquidmusic-UI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(title + ".wav")
        let byteCount = 120 * 8_000 * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(byteCount + 36))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(8_000)); append(UInt32(16_000)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(byteCount))
        data.append(Data(count: byteCount))
        try data.write(to: url, options: .withoutOverwriting)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
