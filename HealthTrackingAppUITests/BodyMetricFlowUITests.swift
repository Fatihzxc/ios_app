import Foundation
import XCTest

final class BodyMetricFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTodayBatchRetryProgressEditDeleteAndRelaunch() {
        let storeIdentifier = UUID()
        let app = launch(appearance: "light", storeIdentifier: storeIdentifier)
        openEntryFromToday(in: app)

        replaceText(in: textField("metrics.entry.weight", in: app), with: "82", app: app)
        replaceText(in: textField("metrics.entry.waist", in: app), with: "91", app: app)
        require(identified("metrics.entry.save", in: app)).tap()

        require(
            identified("metrics.entry.save-error", in: app),
            "The injected first save failure must remain retryable."
        )
        XCTAssertEqual(textField("metrics.entry.weight", in: app).value as? String, "82")
        XCTAssertEqual(textField("metrics.entry.waist", in: app).value as? String, "91")
        require(identified("metrics.entry.retry", in: app)).tap()
        require(identified("metrics.entry.saved", in: app))
        require(identified("metrics.entry.close", in: app)).tap()

        openProgress(in: app)
        require(firstIdentified(prefix: "metrics.row.weight.", in: app))
        require(firstIdentified(prefix: "metrics.row.waist.", in: app))
        attachScreenshot(named: "m3-metrics-progress-light")

        let weightRow = require(firstIdentified(prefix: "metrics.row.weight.", in: app))
        makeHittable(weightRow, in: app)
        weightRow.tap()
        require(identified("metrics.entry.editing", in: app))
        replaceText(in: textField("metrics.entry.weight", in: app), with: "83", app: app)
        require(identified("metrics.entry.save", in: app)).tap()
        require(identified("metrics.entry.saved", in: app))
        require(identified("metrics.entry.close", in: app)).tap()
        require(
            firstIdentified(prefix: "metrics.row.weight.", labelContaining: "83", in: app),
            "The Progress route must publish the edited canonical value."
        )
        app.terminate()

        let relaunched = launch(appearance: "light", storeIdentifier: storeIdentifier)
        openProgress(in: relaunched)
        let persisted = require(
            firstIdentified(prefix: "metrics.row.weight.", labelContaining: "83", in: relaunched),
            "The edited metric must survive a new app process."
        )
        makeHittable(persisted, in: relaunched)
        persisted.swipeLeft()
        require(firstIdentified(prefix: "metrics.delete.weight.", in: relaunched)).tap()
        XCTAssertFalse(
            firstIdentified(prefix: "metrics.row.weight.", in: relaunched)
                .waitForExistence(timeout: 2)
        )
        require(firstIdentified(prefix: "metrics.row.waist.", in: relaunched))
    }

    func testDarkAndAX5QuickEntryEvidenceKeepsActionsReachable() {
        let dark = launch(appearance: "dark")
        openEntryFromToday(in: dark)
        require(textField("metrics.entry.weight", in: dark))
        attachScreenshot(named: "m3-metrics-entry-dark")
        dark.terminate()

        let ax5 = launch(
            appearance: "light",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        openEntryFromToday(in: ax5)
        let save = require(identified("metrics.entry.save", in: ax5))
        makeHittable(save, in: ax5)
        XCTAssertTrue(save.isHittable)
        XCTAssertGreaterThanOrEqual(save.frame.height + 0.01, 52)
        attachScreenshot(named: "m3-metrics-entry-ax5")
    }

    private func launch(
        appearance: String,
        storeIdentifier: UUID? = nil,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-body-metrics",
            "-ui-test-appearance", appearance,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + extraArguments
        if let storeIdentifier {
            app.launchArguments += [
                "-ui-test-store-identifier",
                storeIdentifier.uuidString,
            ]
        }
        app.launch()
        return app
    }

    private func openEntryFromToday(in app: XCUIApplication) {
        require(identified("root.today.content", in: app))
        let action = require(identified("today.metrics.action", in: app))
        makeHittable(action, in: app)
        action.tap()
        require(textField("metrics.entry.weight", in: app))
    }

    private func openProgress(in app: XCUIApplication) {
        require(identified("tab.progress", in: app)).tap()
        require(identified("root.progress", in: app))
        require(identified("metrics.history.loaded", in: app))
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
        for _ in 0..<18 {
            if element.exists, element.isHittable { return }
            if element.exists,
               !element.frame.isEmpty,
               element.frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(
            element.exists && element.isHittable,
            "Element must become hittable; frame=\(element.frame), type=\(element.elementType.rawValue)."
        )
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

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M3 body-metric element is missing.",
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
