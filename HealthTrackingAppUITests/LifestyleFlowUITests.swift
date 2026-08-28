import Foundation
import XCTest

final class LifestyleFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCombinedSleepMoodSaveSurvivesRelaunchWithoutPartialState() {
        let storeIdentifier = UUID()
        let app = launch(storeIdentifier: storeIdentifier)
        openEntry(in: app)

        replaceText(in: textField("lifestyle.sleep.duration", in: app), with: "8", app: app)
        replaceText(in: textField("lifestyle.sleep.quality", in: app), with: "9", app: app)
        replaceText(in: textField("lifestyle.sleep.note", in: app), with: "Kesintisiz", app: app)
        replaceText(in: textField("lifestyle.mood.score", in: app), with: "8", app: app)
        replaceText(in: textField("lifestyle.mood.tags", in: app), with: "Sakin, Odak", app: app)
        replaceText(in: textField("lifestyle.mood.energy", in: app), with: "7", app: app)
        replaceText(in: textField("lifestyle.mood.note", in: app), with: "İyi bir gün", app: app)
        require(identified("lifestyle.entry.save", in: app)).tap()

        require(
            identified("lifestyle.entry.save-error", in: app),
            "The injected combined failure must remain retryable without partial success."
        )
        XCTAssertEqual(textField("lifestyle.sleep.duration", in: app).value as? String, "8")
        XCTAssertEqual(textField("lifestyle.sleep.quality", in: app).value as? String, "9")
        XCTAssertEqual(textField("lifestyle.sleep.note", in: app).value as? String, "Kesintisiz")
        XCTAssertEqual(textField("lifestyle.mood.score", in: app).value as? String, "8")
        XCTAssertEqual(textField("lifestyle.mood.tags", in: app).value as? String, "Sakin, Odak")
        XCTAssertEqual(textField("lifestyle.mood.energy", in: app).value as? String, "7")
        XCTAssertEqual(textField("lifestyle.mood.note", in: app).value as? String, "İyi bir gün")
        require(identified("lifestyle.entry.retry", in: app)).tap()
        require(identified("lifestyle.entry.saved", in: app))
        attachScreenshot(named: "m3-lifestyle-combined-light")
        require(identified("lifestyle.entry.close", in: app)).tap()
        require(identified("tab.progress", in: app)).tap()
        require(identified("metrics.history.loaded", in: app))
        require(identified("lifestyle.progress.loaded", in: app))
        attachScreenshot(named: "m3-lifestyle-progress-light")
        app.terminate()

        let relaunched = launch(storeIdentifier: storeIdentifier)
        openEntry(in: relaunched)
        XCTAssertEqual(textField("lifestyle.sleep.duration", in: relaunched).value as? String, "8")
        XCTAssertEqual(textField("lifestyle.sleep.quality", in: relaunched).value as? String, "9")
        XCTAssertEqual(textField("lifestyle.sleep.note", in: relaunched).value as? String, "Kesintisiz")
        XCTAssertEqual(textField("lifestyle.mood.score", in: relaunched).value as? String, "8")
        XCTAssertEqual(textField("lifestyle.mood.tags", in: relaunched).value as? String, "Sakin, Odak")
        XCTAssertEqual(textField("lifestyle.mood.energy", in: relaunched).value as? String, "7")
        XCTAssertEqual(textField("lifestyle.mood.note", in: relaunched).value as? String, "İyi bir gün")
    }

    func testDarkAndAX5CombinedEntryKeepsOrderedActionsReachable() {
        let dark = launch(storeIdentifier: UUID(), appearance: "dark")
        openEntry(in: dark)
        attachScreenshot(named: "m3-lifestyle-entry-dark")
        dark.terminate()

        let ax5 = launch(
            storeIdentifier: UUID(),
            appearance: "light",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        openEntry(in: ax5)
        assertReadingOrder(
            [
                "lifestyle.entry.loaded",
                "lifestyle.entry.date",
                "lifestyle.sleep.duration",
                "lifestyle.sleep.quality",
                "lifestyle.sleep.note",
                "lifestyle.mood.score",
                "lifestyle.mood.tags",
                "lifestyle.mood.energy",
                "lifestyle.mood.note",
                "lifestyle.entry.save",
            ],
            in: ax5
        )
        let save = require(identified("lifestyle.entry.save", in: ax5))
        makeHittable(save, in: ax5)
        XCTAssertTrue(save.isHittable)
        XCTAssertGreaterThanOrEqual(save.frame.height + 0.01, 52)
        attachScreenshot(named: "m3-lifestyle-entry-ax5")
    }

    private func launch(
        storeIdentifier: UUID,
        appearance: String = "light",
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-sleep-mood",
            "-ui-test-appearance", appearance,
            "-ui-test-store-identifier", storeIdentifier.uuidString,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + extraArguments
        app.launch()
        return app
    }

    private func openEntry(in app: XCUIApplication) {
        require(identified("root.today.content", in: app))
        let action = require(identified("today.lifestyle.action", in: app))
        makeHittable(action, in: app)
        action.tap()
        require(textField("lifestyle.sleep.duration", in: app))
        require(identified("lifestyle.entry.loaded", in: app))
    }

    private func replaceText(
        in element: XCUIElement,
        with value: String,
        app: XCUIApplication
    ) {
        makeHittable(element, in: app)
        require(element).tap()
        let current = (element.value as? String) ?? ""
        if !current.isEmpty {
            element.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
            )
        }
        element.typeText(value)
        let dismiss = app.buttons["quick-entry.keyboard.dismiss"]
        if dismiss.waitForExistence(timeout: 2) {
            dismiss.tap()
        }
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Element must become hittable.")
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func textField(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.textFields[identifier]
    }

    private func assertReadingOrder(
        _ identifiers: [String],
        in app: XCUIApplication
    ) {
        let published = app.descendants(matching: .any)
            .allElementsBoundByIndex
            .map(\.identifier)
        let positions = identifiers.map { identifier -> Int in
            XCTAssertEqual(
                published.filter { $0 == identifier }.count,
                1,
                "VoiceOver order must expose exactly one \(identifier)."
            )
            guard let position = published.firstIndex(of: identifier) else {
                XCTFail("VoiceOver order is missing \(identifier).")
                return Int.max
            }
            return position
        }
        XCTAssertEqual(
            positions,
            positions.sorted(),
            "Sleep, mood and save semantics must follow visual reading order."
        )
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M3 sleep/mood element is missing.",
        timeout: TimeInterval = 12
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        return element
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
