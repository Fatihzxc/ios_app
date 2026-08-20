import XCTest

final class PhaseTransitionFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStayKeepsChecklistAccessibleThenExplicitAndManualSelectionsPersist() {
        let app = launch()
        let priorityCard = require(
            identified("today.alert.phase", in: app),
            "A due calendar estimate must expose the phase decision on Today."
        )
        XCTAssertTrue(priorityCard.label.contains("Faz"))
        attachScreenshot(named: "phase-transition-priority-light")

        select(tab: "training", in: app)
        require(
            identified("phase.transition.card", in: app),
            "The phase decision must remain accessible in phase detail."
        )
        require(
            identified("phase.transition.checklist", in: app),
            "The phase card must label its source checklist."
        )
        let sourceMilestone = require(
            identified("phase.transition.checklist.0", in: app),
            "The checklist must render the seeded milestone without an invented threshold."
        )
        XCTAssertTrue(sourceMilestone.label.contains("Bel"))
        require(
            identified("phase.transition.confirm", in: app),
            "The due review must provide explicit confirmation."
        )

        tap("phase.transition.stay", in: app)
        require(
            identified("phase.transition.card", in: app),
            "Şimdilik kal must preserve the review in phase detail."
        )
        attachScreenshot(named: "phase-transition-detail-light")
        tap("phase.transition.confirm", in: app)

        let activePhase = require(
            identified("phase.transition.current", in: app),
            "Explicit confirmation must expose the newly active phase."
        )
        waitFor(
            NSPredicate(format: "label == %@", "İnşa"),
            on: activePhase,
            message: "Explicit confirmation must activate İnşa."
        )
        XCTAssertFalse(identified("phase.transition.confirm", in: app).exists)

        select(tab: "settings", in: app)
        tap("settings.phase-link", in: app)
        require(
            identified("phase.selection.root", in: app),
            "Settings must push the real manual phase selection route."
        )
        tap("phase.selection.option.0", in: app)
        let manuallySelected = require(
            identified("phase.selection.option.0", in: app),
            "Manual selection must keep the selected phase visible."
        )
        waitFor(
            NSPredicate(format: "value == %@", "Aktif"),
            on: manuallySelected,
            message: "Manual selection must persist Temel as the active phase."
        )
        attachScreenshot(named: "phase-selection-manual-light")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "phase-transition",
            "-ui-test-appearance", "light",
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        return app
    }

    private func select(tab: String, in app: XCUIApplication) {
        let element = require(
            identified("tab.\(tab)", in: app),
            "Missing tab: \(tab)."
        )
        XCTAssertTrue(element.isHittable)
        element.tap()
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

    private func waitFor(
        _ predicate: NSPredicate,
        on element: XCUIElement,
        message: String,
        timeout: TimeInterval = 8
    ) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            message
        )
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
