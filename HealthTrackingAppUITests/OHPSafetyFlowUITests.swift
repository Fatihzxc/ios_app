import XCTest

final class OHPSafetyFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPriorQuestionPrecedesWarmupAndCurrentSymptomsRouteToHalfKneeling() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "ohp-safety",
            "-ui-test-appearance", "light",
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()

        require(
            app.descendants(matching: .any)["root.today.content"],
            "The OHP fixture must load through the real Today root."
        )
        tap("today.action.primary", in: app)

        let question = require(
            app.staticTexts["session.ohp.question.body"],
            "An unanswered prior OHP session must show one question before warmup."
        )
        let normalizedQuestion = question.label.lowercased()
        XCTAssertTrue(normalizedQuestion.contains("sağ işaret parmağ"))
        XCTAssertTrue(normalizedQuestion.contains("uyuşma"))
        XCTAssertTrue(normalizedQuestion.contains("karıncalanma"))
        XCTAssertFalse(normalizedQuestion.contains("tanı"))
        XCTAssertFalse(normalizedQuestion.contains("teşhis"))
        XCTAssertFalse(app.descendants(matching: .any)["session.stage.warmup"].exists)
        attachScreenshot(named: "session-ohp-prior-question-light")

        tap("session.ohp.prior.symptom-free", in: app)
        require(
            app.descendants(matching: .any)["session.stage.warmup"],
            "Answering the prior-session question must reveal warmup."
        )
        tap("session.warmup.skip", in: app)
        for _ in 0..<3 {
            tap("session.exercise.next", in: app)
        }

        XCTAssertEqual(
            require(app.staticTexts["session.exercise.name"], "OHP must be active.").label,
            "DB Overhead Press"
        )
        XCTAssertEqual(
            require(
                app.staticTexts["session.ohp.variant"],
                "The week-three OHP variant must be visible as text."
            ).label,
            "Ayakta nötr tutuş"
        )
        XCTAssertTrue(
            require(
                app.staticTexts["session.exercise.recommendation"],
                "A symptom-free prior response must expose the qualified recommendation."
            ).label.contains("+2,5")
        )

        tap("session.ohp.current-symptom", in: app)

        let stop = require(
            app.descendants(matching: .any)["session.ohp.stop"],
            "Current symptoms must create a visible safety stop, not a color-only state."
        )
        XCTAssertTrue(stop.label.lowercased().contains("durdur"))
        XCTAssertEqual(
            require(
                app.staticTexts["medical.disclaimer.l1"],
                "The permanent medical disclaimer must remain independently accessible."
            ).label,
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
        )
        let levelTwo = require(
            app.staticTexts["medical.safety.l2"],
            "The current OHP symptom must publish the event-triggered stop notice."
        ).label
        XCTAssertTrue(levelTwo.hasPrefix("Hareketi durdur."))
        XCTAssertTrue(levelTwo.lowercased().contains("sağlık profesyoneli"))
        require(
            app.descendants(matching: .any)["session.ohp.journal.error"],
            "A journal write failure must be visible without removing the safety stop."
        )
        tap("session.ohp.journal.retry", in: app)
        require(
            app.descendants(matching: .any)["session.ohp.journal.recorded"],
            "Retry must complete the same stable symptom event."
        )
        XCTAssertEqual(
            require(
                app.staticTexts["session.exercise.name"],
                "The existing safe alternative must replace only the OHP card."
            ).label,
            "Half-Kneeling DB Press"
        )
        let visibleText = app.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .joined(separator: " ")
            .lowercased()
        XCTAssertFalse(visibleText.contains("tanı"))
        XCTAssertFalse(visibleText.contains("teşhis"))
        attachScreenshot(named: "session-ohp-blocked-light")
        attachScreenshot(named: "session-ohp-half-kneeling-alternative-light")
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = require(
            app.descendants(matching: .any)[identifier],
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
