import Foundation
import XCTest

final class M3AccessibilityUITests: XCTestCase {
    private enum Appearance: String, CaseIterable {
        case light
        case dark
    }

    private enum TextSize: String, CaseIterable {
        case `default`
        case xxl
        case ax3
        case ax5

        var launchArguments: [String] {
            let category: String?
            switch self {
            case .default:
                category = nil
            case .xxl:
                category = "UICTContentSizeCategoryXXL"
            case .ax3:
                category = "UICTContentSizeCategoryAccessibilityXL"
            case .ax5:
                category = "UICTContentSizeCategoryAccessibilityXXXL"
            }
            guard let category else { return [] }
            return ["-UIPreferredContentSizeCategoryName", category]
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testProgressHubLightDarkDefaultXXLAX3AX5Matrix() {
        for appearance in Appearance.allCases {
            for textSize in TextSize.allCases {
                let app = launch(
                    appearance: appearance,
                    textSize: textSize
                )
                openProgress(in: app)
                let action = assertAccessibleAction("progress.metrics.action", in: app)
                attachScreenshot(
                    named: "m3-progress-\(appearance.rawValue)-\(textSize.rawValue)"
                )
                action.tap()
                let field = require(app.textFields["metrics.entry.weight"])
                makeHittable(field, in: app)
                XCTAssertFalse(field.label.isEmpty)
                XCTAssertGreaterThanOrEqual(field.frame.height + 0.01, 52)
                app.terminate()
            }
        }
    }

    func testEveryMetricTextFieldExposesFiftyTwoPointInteractionGeometry() {
        let app = launch(appearance: .light, textSize: .default)
        openProgress(in: app)
        assertAccessibleAction("progress.metrics.action", in: app).tap()

        let fields: [(identifier: String, label: String)] = [
            ("metrics.entry.weight", "Vücut ağırlığı"),
            ("metrics.entry.waist", "Bel çevresi"),
            ("metrics.entry.custom.name", "Ölçüm adı"),
            ("metrics.entry.custom.value", "Değer"),
            ("metrics.entry.custom.unit", "Birim"),
        ]
        for contract in fields {
            let field = require(app.textFields[contract.identifier])
            makeHittable(field, in: app)
            XCTAssertTrue(field.isHittable)
            XCTAssertEqual(field.label, contract.label)
            XCTAssertGreaterThanOrEqual(field.frame.height + 0.01, 52)
        }
    }

    func testReduceMotionAndHighContrastTrackerRoutesRemainOperable() {
        let reduceMotion = launch(
            appearance: .light,
            textSize: .ax3,
            extraArguments: ["-UIAccessibilityReduceMotionEnabled", "YES"]
        )
        openProgress(in: reduceMotion)
        assertAccessibleAction("progress.posture.action", in: reduceMotion).tap()
        require(identified("posture.entry.loaded", in: reduceMotion))
        attachScreenshot(named: "m3-progress-reduce-motion")
        reduceMotion.terminate()

        let highContrast = launch(
            appearance: .dark,
            textSize: .ax3,
            extraArguments: ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
        )
        openProgress(in: highContrast)
        assertAccessibleAction("progress.health-check.action", in: highContrast).tap()
        require(identified("health-check.list.loaded", in: highContrast))
        attachScreenshot(named: "m3-progress-high-contrast")
    }

    func testSmallPhoneAX5TrackerRoutesRemainOperable() throws {
        guard ProcessInfo.processInfo.environment["M3_SMALL_PHONE_GATE"] == "1" else {
            throw XCTSkip("The canonical M3 small-phone gate runs in its dedicated CI job.")
        }
        let app = launch(appearance: .light, textSize: .ax5)
        XCTAssertLessThanOrEqual(
            app.frame.width,
            390,
            "The dedicated M3 small-phone job must use the canonical compact destination."
        )
        openProgress(in: app)
        let metrics = assertAccessibleAction("progress.metrics.action", in: app)
        let health = assertAccessibleAction("progress.health-check.action", in: app)
        attachScreenshot(named: "m3-progress-small-ax5")
        makeHittable(metrics, in: app)
        metrics.tap()
        let metricField = require(app.textFields["metrics.entry.weight"])
        let metricClose = require(app.buttons["metrics.entry.close"])
        XCTAssertTrue(
            metricClose.isHittable,
            "The AX5 Metrics draft close action must be immediately operable."
        )
        XCTAssertLessThan(
            metricClose.frame.midY,
            app.frame.midY,
            "The AX5 Metrics draft close action must remain above the long form."
        )
        metricClose.tap()
        waitForDisappearance(
            of: metricField,
            message: "The Metrics sheet must dismiss before exercising the Health Checks route."
        )
        makeHittable(health, in: app)
        health.tap()
        require(identified("health-check.list.loaded", in: app))
    }

    private func launch(
        appearance: Appearance,
        textSize: TextSize,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-health-checks",
            "-ui-test-appearance", appearance.rawValue,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + textSize.launchArguments + extraArguments
        app.launch()
        require(identified("root.today.content", in: app))
        return app
    }

    private func openProgress(in app: XCUIApplication) {
        require(identified("tab.progress", in: app)).tap()
        require(identified("root.progress", in: app))
        require(identified("metrics.history.loaded", in: app))
    }

    @discardableResult
    private func assertAccessibleAction(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        let element = require(identified(identifier, in: app), "Missing M3 action: \(identifier)")
        makeHittable(element, in: app)
        XCTAssertTrue(element.isHittable)
        XCTAssertFalse(element.label.isEmpty)
        XCTAssertGreaterThanOrEqual(element.frame.height + 0.01, 52)
        return element
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            let frame = element.frame
            let safelyVisible = !frame.isEmpty
                && frame.minY >= app.frame.minY + 44
                && frame.maxY <= app.frame.maxY - 44
            if element.exists, element.isHittable, safelyVisible { return }
            let towardTop = frame.isEmpty || frame.midY >= app.frame.midY
            shortDrag(towardTop: towardTop, in: app)
        }
        XCTFail("Unable to position M3 accessibility element: \(element.identifier)")
    }

    private func shortDrag(towardTop: Bool, in app: XCUIApplication) {
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let start = towardTop ? lower : upper
        let end = towardTop ? upper : lower
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M3 accessibility element is missing.",
        timeout: TimeInterval = 15
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        return element
    }

    private func waitForDisappearance(of element: XCUIElement, message: String) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            message
        )
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
