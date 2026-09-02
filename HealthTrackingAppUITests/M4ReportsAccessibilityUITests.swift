import Foundation
import XCTest

final class M4ReportsAccessibilityUITests: XCTestCase {
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
            switch self {
            case .default:
                []
            case .xxl:
                ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
            case .ax3:
                ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
            case .ax5:
                ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDashboardLightDarkDefaultXXLAX3AX5Matrix() {
        for appearance in Appearance.allCases {
            for textSize in TextSize.allCases {
                let app = launch(appearance: appearance, textSize: textSize)
                openProgress(in: app)
                let chart = requireByScrolling(
                    "reports.chart.body.kg.segment.1",
                    in: app,
                    elementType: .other
                )
                XCTAssertFalse(chart.label.isEmpty)
                let range = requireByScrolling("reports.range.one_year", in: app)
                XCTAssertFalse(range.label.isEmpty)
                XCTAssertTrue(range.isHittable)
                XCTAssertGreaterThanOrEqual(range.frame.height + 0.01, 52)
                attachScreenshot(
                    named: "m4-reports-\(appearance.rawValue)-\(textSize.rawValue)"
                )
                app.terminate()
            }
        }
    }

    func testReduceMotionAndHighContrastDashboardRemainOperable() {
        let reduceMotion = launch(
            appearance: .light,
            textSize: .ax3,
            extraArguments: ["-UIAccessibilityReduceMotionEnabled", "YES"]
        )
        openProgress(in: reduceMotion)
        let reduceRange = requireByScrolling("reports.range.six_months", in: reduceMotion)
        reduceRange.tap()
        XCTAssertTrue(reduceRange.isSelected)
        requireByScrolling(
            "reports.chart.body.kg.segment.1",
            in: reduceMotion,
            elementType: .other
        )
        attachScreenshot(named: "m4-reports-reduce-motion")
        reduceMotion.terminate()

        let highContrast = launch(
            appearance: .dark,
            textSize: .ax3,
            extraArguments: ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
        )
        openProgress(in: highContrast)
        let export = requireByScrolling("reports.export.open", in: highContrast)
        XCTAssertFalse(export.label.isEmpty)
        XCTAssertGreaterThanOrEqual(export.frame.height + 0.01, 52)
        attachScreenshot(named: "m4-reports-high-contrast")
        highContrast.terminate()
    }

    func testSmallPhoneAX5DashboardAndExportRemainOperable() throws {
        guard ProcessInfo.processInfo.environment["M4_SMALL_PHONE_GATE"] == "1" else {
            throw XCTSkip("The canonical M4 compact audit runs in the dedicated small-phone job.")
        }
        let app = launch(appearance: .light, textSize: .ax5)
        defer { app.terminate() }
        XCTAssertLessThanOrEqual(
            app.frame.width,
            390,
            "The dedicated M4 job must use the canonical compact destination."
        )
        openProgress(in: app)
        let range = requireByScrolling("reports.range.one_year", in: app)
        XCTAssertTrue(range.isHittable)
        XCTAssertGreaterThanOrEqual(range.frame.height + 0.01, 52)
        requireByScrolling(
            "reports.chart.body.kg.segment.1",
            in: app,
            elementType: .other
        )
        let export = requireByScrolling("reports.export.open", in: app)
        XCTAssertTrue(export.isHittable)
        XCTAssertGreaterThanOrEqual(export.frame.height + 0.01, 52)
        attachScreenshot(named: "m4-reports-small-ax5")
        export.tap()
        let format = requireByScrolling(
            "reports.export.format",
            in: app,
            elementType: .segmentedControl
        )
        XCTAssertTrue(format.isHittable)
        XCTAssertFalse(format.label.isEmpty)
        XCTAssertGreaterThanOrEqual(format.frame.height + 0.01, 32)
    }

    private func launch(
        appearance: Appearance,
        textSize: TextSize,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TZ"] = "Europe/Istanbul"
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m4-reports",
            "-ui-test-appearance", appearance.rawValue,
            "-ui-test-now", "2026-09-02T09:00:00Z",
            "-ui-test-time-zone", "Europe/Istanbul",
            "-ui-test-reports-export-behavior", "success",
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + textSize.launchArguments + extraArguments
        app.launch()
        let acknowledgement = app.buttons["medical.explanation.l0.acknowledge"]
        if acknowledgement.waitForExistence(timeout: 2) { acknowledgement.tap() }
        require(identified("root.today.content", in: app))
        return app
    }

    private func openProgress(in app: XCUIApplication) {
        require(identified("tab.progress", in: app)).tap()
        require(identified("root.progress", in: app))
        require(identified("reports.dashboard", in: app))
    }

    private func requireByScrolling(
        _ identifier: String,
        in app: XCUIApplication,
        elementType: XCUIElement.ElementType = .any
    ) -> XCUIElement {
        let element = app.descendants(matching: elementType)[identifier]
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
        for searchesDown in [true, false] {
            for _ in 0..<40 {
                var shouldSearchDown = searchesDown
                if element.exists {
                    let frame = element.frame
                    let hasReliableFrame = !frame.isEmpty
                        && !frame.isNull
                        && !frame.isInfinite
                    let visible = hasReliableFrame
                        && frame.minY >= app.frame.minY + 44
                        && frame.maxY <= app.frame.maxY - 44
                    if element.isHittable, visible {
                        return require(element, timeout: 1)
                    }
                    if hasReliableFrame {
                        shouldSearchDown = frame.midY >= app.frame.midY
                    }
                }
                (shouldSearchDown ? lower : upper).press(
                    forDuration: 0.05,
                    thenDragTo: shouldSearchDown ? upper : lower
                )
            }
        }

        _ = require(
            element,
            "Unable to expose M4 accessibility element: \(identifier)",
            timeout: 1
        )
        XCTAssertTrue(
            element.isHittable,
            "M4 accessibility element is not hittable after bounded real scrolling: \(identifier)"
        )
        return element
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M4 accessibility element is missing.",
        timeout: TimeInterval = 15
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
