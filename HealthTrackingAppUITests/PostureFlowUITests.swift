import Foundation
import XCTest

final class PostureFlowUITests: XCTestCase {
    private let disclaimer =
        "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
    private let expectedGeneralMessage =
        "Hareketi durdur. Kalıcı veya kötüleşen belirtiler bir sağlık profesyoneli "
        + "tarafından değerlendirilmelidir. Yeni veya belirgin şekilde kötüleşen kol veya "
        + "bacakta güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede "
        + "değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi "
        + "değerlendirme gerektirir."

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWeeklyEntryRetrySafetyHistoryAndRelaunch() {
        let storeIdentifier = UUID()
        let app = launch(storeIdentifier: storeIdentifier)
        openEntry(in: app)

        assertDisclaimer(in: app)
        require(identified("posture.entry.wall.fail", in: app)).tap()
        replaceText(in: textField("posture.entry.region", in: app), with: "Boyun", app: app)
        replaceText(
            in: textField("posture.entry.note", in: app),
            with: "OHP sonrası takip",
            app: app
        )
        replaceText(
            in: textField("posture.entry.symptom", in: app),
            with: "6",
            app: app,
            dismissKeyboardAfterTyping: false
        )
        assertCompleteGeneralLevelTwo(
            in: app,
            reason: "The final symptom input must immediately publish the complete L2."
        )
        dismissKeyboard(in: app)
        require(identified("posture.entry.save", in: app)).tap()

        require(
            identified("posture.entry.save-error", in: app),
            "The injected save failure must keep the posture journal retryable."
        )
        XCTAssertEqual(textField("posture.entry.symptom", in: app).value as? String, "6")
        XCTAssertEqual(textField("posture.entry.region", in: app).value as? String, "Boyun")
        XCTAssertEqual(
            textField("posture.entry.note", in: app).value as? String,
            "OHP sonrası takip"
        )
        require(identified("posture.entry.retry", in: app)).tap()
        require(identified("posture.entry.saved", in: app))
        attachScreenshot(named: "m3-posture-entry-light")
        require(identified("posture.entry.close", in: app)).tap()

        require(identified("tab.progress", in: app)).tap()
        require(identified("posture.history.loaded", in: app))
        let savedRow = require(
            firstIdentified(prefix: "posture.row.", labelContaining: "6", in: app)
        )
        makeHittable(savedRow, in: app)
        assertDisclaimer(in: app)
        attachScreenshot(named: "m3-posture-progress-light")
        app.terminate()

        let relaunched = launch(storeIdentifier: storeIdentifier)
        require(identified("tab.progress", in: relaunched)).tap()
        require(identified("posture.history.loaded", in: relaunched))
        require(
            firstIdentified(prefix: "posture.row.", labelContaining: "6", in: relaunched),
            "The posture journal must survive a new app process."
        )
    }

    func testDarkAX5AndHighContrastKeepDisclaimerAndActionsReachable() {
        let dark = launch(storeIdentifier: UUID(), appearance: "dark")
        openEntry(in: dark)
        assertDisclaimer(in: dark)
        attachScreenshot(named: "m3-posture-entry-dark")
        dark.terminate()

        let ax5 = launch(
            storeIdentifier: UUID(),
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        openEntry(in: ax5)
        assertReadingOrder(
            [
                "posture.entry.loaded",
                "medical.disclaimer.l1",
                "posture.entry.date",
                "posture.entry.wall.label",
                "posture.entry.symptom",
                "posture.entry.region",
                "posture.entry.note",
                "posture.entry.save",
            ],
            in: ax5
        )
        let dateLabel = require(identified("posture.entry.date.label", in: ax5))
        XCTAssertGreaterThanOrEqual(dateLabel.frame.width + 0.01, 160)
        let save = require(identified("posture.entry.save", in: ax5))
        makeHittable(save, in: ax5)
        XCTAssertTrue(save.isHittable)
        XCTAssertGreaterThanOrEqual(save.frame.height + 0.01, 52)
        assertDisclaimer(in: ax5)
        attachScreenshot(named: "m3-posture-entry-ax5")
        ax5.terminate()

        let highContrast = launch(
            storeIdentifier: UUID(),
            appearance: "dark",
            extraArguments: ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
        )
        openEntry(in: highContrast)
        assertDisclaimer(in: highContrast)
        attachScreenshot(named: "m3-posture-high-contrast")
    }

    private func launch(
        storeIdentifier: UUID,
        appearance: String = "light",
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-posture",
            "-ui-test-appearance", appearance,
            "-ui-test-store-identifier", storeIdentifier.uuidString,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
            "-UIAccessibilityReduceMotionEnabled", "YES",
        ] + extraArguments
        app.launch()
        return app
    }

    private func openEntry(in app: XCUIApplication) {
        require(identified("root.today.content", in: app))
        let action = require(identified("today.posture.action", in: app))
        makeHittable(action, in: app)
        action.tap()
        require(textField("posture.entry.symptom", in: app))
        require(identified("posture.entry.loaded", in: app))
    }

    private func assertDisclaimer(in app: XCUIApplication) {
        XCTAssertEqual(
            require(
                app.descendants(matching: .any)
                    .matching(identifier: "medical.disclaimer.l1")
                    .firstMatch
            ).label,
            disclaimer
        )
    }

    private func assertCompleteGeneralLevelTwo(
        in app: XCUIApplication,
        reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        require(
            identified("medical.safety.l2.heading", in: app),
            reason
        )
        XCTAssertEqual(
            require(
                identified("medical.safety.l2", in: app),
                "The stable heading must not replace the complete L2 message."
            ).label,
            expectedGeneralMessage,
            file: file,
            line: line
        )
    }

    private func replaceText(
        in element: XCUIElement,
        with value: String,
        app: XCUIApplication,
        dismissKeyboardAfterTyping: Bool = true
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
        if dismissKeyboardAfterTyping {
            dismissKeyboard(in: app)
        }
    }

    private func dismissKeyboard(in app: XCUIApplication) {
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
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func textField(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.textFields[identifier]
    }

    private func firstIdentified(
        prefix: String,
        labelContaining: String? = nil,
        in app: XCUIApplication
    ) -> XCUIElement {
        var predicates = [NSPredicate(format: "identifier BEGINSWITH %@", prefix)]
        if let labelContaining {
            predicates.append(NSPredicate(format: "label CONTAINS[c] %@", labelContaining))
        }
        return app.descendants(matching: .any)
            .matching(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
            .firstMatch
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
        XCTAssertEqual(positions, positions.sorted())
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M3 posture element is missing.",
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
