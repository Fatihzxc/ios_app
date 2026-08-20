import XCTest

final class DeloadFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testScheduledWeekShowsVisibleWarningAndAcceptedDeloadLoad() {
        let app = launch(scenario: "deload-scheduled")
        let todayDirective = require(
            identified("today.alert.deload", in: app),
            "Today must explain the scheduled deload before the session opens."
        )
        XCTAssertFalse(todayDirective.label.isEmpty)
        XCTAssertTrue(
            require(
                identified("today.alert.context", in: app),
                "Today must explain the scheduled deload week."
            ).label.contains("5")
        )
        openSession(in: app)

        let recommendation = require(
            identified("session.deload.recommendation", in: app),
            "Scheduled week five must show a deload recommendation before warmup."
        )
        XCTAssertTrue(recommendation.label.contains("5"))
        XCTAssertTrue(
            app.images["session.deload.warning-icon"].exists,
            "The warning must include visible icon semantics, not color or haptic alone."
        )
        XCTAssertFalse(identified("session.stage.warmup", in: app).exists)
        for action in ["accept", "stay", "technique-review", "skip"] {
            XCTAssertTrue(
                identified("session.deload.action.\(action)", in: app).exists,
                "Every explicit deload choice must be available."
            )
        }
        attachScreenshot(named: "session-deload-scheduled-recommendation-light")

        tap("session.deload.action.accept", in: app)

        require(
            identified("session.stage.warmup", in: app),
            "Accepting deload must enter the unchanged workout through warmup."
        )
        require(
            identified("session.deload.active", in: app),
            "An active deload must expose visible DELOAD text."
        )
        tap("session.warmup.skip", in: app)
        let load = require(
            app.staticTexts["session.deload.load"],
            "The movement card must explain the default deload load."
        )
        XCTAssertTrue(load.label.contains("50"))
        attachScreenshot(named: "session-deload-active-load-light")
    }

    func testReactiveTechniqueReviewSuppressesOnlyTheCurrentWeekWithoutMutation() {
        let app = launch(scenario: "deload-reactive")
        let todayDirective = require(
            identified("today.alert.deload", in: app),
            "Today must explain the reactive deload before the session opens."
        )
        XCTAssertFalse(todayDirective.label.isEmpty)
        XCTAssertTrue(
            require(
                identified("today.alert.context", in: app),
                "Today must explain why the reactive deload is recommended."
            ).label.lowercased().contains("iki")
        )
        openSession(in: app)

        let recommendation = require(
            identified("session.deload.recommendation", in: app),
            "Two stagnant sessions must show a reactive deload recommendation."
        )
        XCTAssertTrue(recommendation.label.lowercased().contains("iki"))
        XCTAssertTrue(
            identified("session.deload.action.technique-review", in: app).exists
        )
        attachScreenshot(named: "session-deload-reactive-recommendation-light")

        tap("session.deload.action.technique-review", in: app)

        require(
            identified("session.stage.warmup", in: app),
            "Technique review must dismiss the current-week warning and preserve the workout."
        )
        XCTAssertFalse(identified("session.deload.recommendation", in: app).exists)
        XCTAssertFalse(identified("session.deload.active", in: app).exists)
        attachScreenshot(named: "session-deload-technique-review-light")
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", scenario,
            "-ui-test-appearance", "light",
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        return app
    }

    private func openSession(in app: XCUIApplication) {
        require(
            identified("root.today.content", in: app),
            "The deload fixture must load through the real Today root."
        )
        tap("today.action.primary", in: app)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = require(
            identified(identifier, in: app),
            "Missing required action: \(identifier)."
        )
        var remainingScrolls = 10
        while !element.isHittable, remainingScrolls > 0 {
            app.swipeUp()
            remainingScrolls -= 1
        }
        XCTAssertTrue(element.isHittable, "The action must be hittable: \(identifier).")
        element.tap()
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String,
        timeout: TimeInterval = 8
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
