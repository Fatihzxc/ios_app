import XCTest

final class TrainingHistoryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHistoryEditDeleteAndMissingTemplateRecoveryUseRealRoutes() {
        let app = launch()
        selectTraining(in: app)
        tap("training.history.link", in: app)
        require(
            identified("training.history.root", in: app),
            "Training must push its repository-backed history route."
        )
        let newest = require(
            identified("training.history.session.0", in: app),
            "The newest completed session must be listed first."
        )
        let older = require(
            identified("training.history.session.1", in: app),
            "Older completed history must remain available."
        )
        XCTAssertFalse(newest.label.isEmpty)
        XCTAssertFalse(older.label.isEmpty)
        attachScreenshot(named: "training-history-list-light")

        newest.tap()
        require(
            identified("training.history.detail", in: app),
            "A history row must open real recorded details."
        )
        let setRow = require(
            identified("training.history.set.0", in: app),
            "The detail must render the real recorded set."
        )
        XCTAssertTrue(setRow.label.contains("8"))
        require(
            identified("training.history.set.edit.0", in: app),
            "Every editable set needs an explicit edit action."
        )
        require(
            identified("training.history.set.delete.0", in: app),
            "Every set needs an explicit delete action."
        )
        XCTAssertFalse(
            setRow.value as? String == "",
            "The set row must expose accessible measurement context."
        )

        tap("training.history.set.edit.0", in: app)
        require(
            identified("training.history.edit.root", in: app),
            "Edit must open a measurement-aware form."
        )
        tap("training.history.edit.reps.increment", in: app)
        tap("training.history.edit.save", in: app)
        waitFor(
            NSPredicate(format: "label CONTAINS %@", "9"),
            on: identified("training.history.set.0", in: app),
            message: "A successful edit must reload the detail from repository history."
        )
        attachScreenshot(named: "training-history-edited-light")

        tap("training.history.set.delete.0", in: app)
        let cancelSetDelete = require(
            app.alerts.buttons["İptal"],
            "Set deletion must require a destructive confirmation."
        )
        cancelSetDelete.tap()
        XCTAssertTrue(identified("training.history.set.0", in: app).exists)
        tap("training.history.set.delete.0", in: app)
        require(app.alerts.buttons["Seti sil"], "The alert needs an explicit set delete.").tap()
        waitFor(
            NSPredicate(format: "exists == false"),
            on: identified("training.history.set.0", in: app),
            message: "Confirmed set deletion must refresh detail without a stale row."
        )

        tap("training.history.session.delete", in: app)
        require(
            app.alerts.buttons["İptal"],
            "Session deletion must also require confirmation."
        ).tap()
        XCTAssertTrue(identified("training.history.detail", in: app).exists)
        tap("training.history.session.delete", in: app)
        require(
            app.alerts.buttons["Seansı sil"],
            "The alert needs an explicit session delete."
        ).tap()
        waitFor(
            NSPredicate(format: "exists == false"),
            on: identified("training.history.session.1", in: app),
            message: "Deleting the newest session must leave one reindexed older row."
        )
        let remaining = require(
            identified("training.history.session.0", in: app),
            "The older missing-template fixture must survive deletion."
        )
        remaining.tap()
        require(
            identified("training.history.missingTemplate", in: app),
            "Deleted catalog references need a recoverable localized fallback."
        )
        attachScreenshot(named: "training-history-missing-template-light")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "training-history",
            "-ui-test-appearance", "light",
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        return app
    }

    private func selectTraining(in app: XCUIApplication) {
        let tab = require(
            identified("tab.training", in: app),
            "Training tab must exist."
        )
        tab.tap()
        require(identified("root.training", in: app), "Training root must load.")
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = require(
            identified(identifier, in: app),
            "Missing required history action: \(identifier)."
        )
        var remainingScrolls = 10
        while !element.isHittable, remainingScrolls > 0 {
            app.swipeUp()
            remainingScrolls -= 1
        }
        XCTAssertTrue(element.isHittable, "History action must be hittable: \(identifier).")
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
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
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
