import Foundation
import XCTest

final class HealthCheckFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTodayDueCardRetryCompletionSuccessorAndProgressRelaunch() {
        let storeIdentifier = UUID()
        let app = launch(storeIdentifier: storeIdentifier)

        require(identified("root.today.content", in: app))
        require(identified("today.health-check.summary", in: app))
        let todayAction = require(identified("today.health-check.action", in: app))
        makeHittable(todayAction, in: app)
        todayAction.tap()

        require(identified("health-check.list.loaded", in: app))
        require(identified("medical.disclaimer.l1", in: app))
        let pendingRow = require(
            firstIdentified(prefix: "health-check.row.", labelContaining: "Genel", in: app)
        )
        makeHittable(pendingRow, in: app)
        pendingRow.tap()
        let complete = require(identified("health-check.detail.complete", in: app))
        makeHittable(complete, in: app)
        complete.tap()
        require(
            identified("health-check.detail.complete-error", in: app),
            "The injected transaction failure must remain retryable."
        )
        require(identified("health-check.detail.retry", in: app)).tap()
        require(identified("health-check.detail.completed", in: app))
        require(identified("health-check.detail.successor", in: app))
        attachScreenshot(named: "m3-health-check-completed-light")
        require(identified("health-check.close", in: app)).tap()

        require(identified("tab.progress", in: app)).tap()
        require(identified("health-check.history.loaded", in: app))
        require(
            firstIdentified(prefix: "health-check.row.", labelContaining: "Yapıldı", in: app)
        )
        require(
            firstIdentified(prefix: "health-check.row.", labelContaining: "Bekliyor", in: app)
        )
        attachScreenshot(named: "m3-health-check-progress-light")
        app.terminate()

        let relaunched = launch(storeIdentifier: storeIdentifier)
        require(identified("tab.progress", in: relaunched)).tap()
        require(identified("health-check.history.loaded", in: relaunched))
        require(
            firstIdentified(
                prefix: "health-check.row.",
                labelContaining: "Yapıldı",
                in: relaunched
            ),
            "Completion and its single successor must survive a new app process."
        )
    }

    func testAX5KeepsDisclaimerAndCompletionActionReachable() {
        let app = launch(
            storeIdentifier: UUID(),
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        require(identified("root.today.content", in: app))
        let todayAction = require(identified("today.health-check.action", in: app))
        makeHittable(todayAction, in: app)
        todayAction.tap()
        require(identified("medical.disclaimer.l1", in: app))
        let row = require(
            firstIdentified(prefix: "health-check.row.", labelContaining: "Genel", in: app)
        )
        makeHittable(row, in: app)
        row.tap()
        let complete = require(identified("health-check.detail.complete", in: app))
        makeHittable(complete, in: app)
        XCTAssertGreaterThanOrEqual(complete.frame.height + 0.01, 52)
        attachScreenshot(named: "m3-health-check-detail-ax5")
    }

    private func launch(
        storeIdentifier: UUID,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-health-checks",
            "-ui-test-appearance", "light",
            "-ui-test-store-identifier", storeIdentifier.uuidString,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + extraArguments
        app.launch()
        return app
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

    private func firstIdentified(
        prefix: String,
        labelContaining: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                    prefix,
                    labelContaining
                )
            )
            .firstMatch
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M3 health-check element is missing.",
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
