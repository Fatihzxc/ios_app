import XCTest

final class OHPSafetyFlowUITests: XCTestCase {
    private let expectedGeneralMessage =
        "Hareketi durdur. Kalıcı veya kötüleşen belirtiler bir sağlık profesyoneli "
        + "tarafından değerlendirilmelidir. Yeni veya belirgin şekilde kötüleşen kol veya "
        + "bacakta güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede "
        + "değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi "
        + "değerlendirme gerektirir."

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
            "-UIAccessibilityReduceMotionEnabled", "YES",
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
        assertCompleteGeneralLevelTwo(
            in: app,
            reason: "An unanswered prior OHP response must fail closed before it is answered."
        )
        attachScreenshot(named: "session-ohp-prior-question-light")

        tap("session.ohp.prior.symptom-free", in: app)
        require(
            app.descendants(matching: .any)["session.stage.warmup"],
            "Answering the prior-session question must reveal warmup."
        )
        XCTAssertFalse(
            app.staticTexts["medical.safety.l2.heading"].waitForExistence(timeout: 2),
            "An explicit symptom-free answer must clear the missing-answer L2."
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
        assertCompleteGeneralLevelTwo(
            in: app,
            reason: "The current OHP symptom must publish the complete L2."
        )
        let persistenceRetry = require(
            app.descendants(matching: .any)["session.ohp.persistence.retry"],
            "A failed write must expose its exact persistence retry."
        )
        XCTAssertGreaterThanOrEqual(
            persistenceRetry.frame.height + 0.01,
            52,
            "The shipped persistence retry target must remain at least 52 points high."
        )
        let blockedRouteControls = [
            "session.exercise.next",
            "session.exercise.back",
            "session.exercise.finish-incomplete",
            "session.close",
        ]
        for identifier in blockedRouteControls {
            XCTAssertFalse(
                require(
                    app.buttons.matching(identifier: identifier).firstMatch,
                    "Pending OHP persistence must keep the route control visible: \(identifier)."
                ).isEnabled,
                "Pending OHP persistence must disable the route control: \(identifier)."
            )
        }
        require(
            app.descendants(matching: .any)["session.ohp.persistence.error"],
            "A failed training-state write must retain the stopped route and expose retry."
        )
        let deleteButton = require(
            app.buttons.matching(identifier: "session.delete").firstMatch,
            "The toolbar delete action must remain available while the exact symptom write awaits retry."
        )
        XCTAssertTrue(deleteButton.isHittable, "The toolbar delete action must be hittable.")
        deleteButton.tap()
        tap("session.delete.confirm.action", in: app)
        require(
            app.descendants(matching: .any)["session.delete.error"],
            "A failed deletion must stay on the stopped route and expose a separate error."
        )
        require(
            app.descendants(matching: .any)["session.ohp.stop"],
            "A failed deletion must not replace the current OHP safety stop."
        )
        require(
            app.descendants(matching: .any)["session.ohp.persistence.retry"],
            "A failed deletion must preserve the exact symptom persistence retry."
        )
        for identifier in blockedRouteControls {
            XCTAssertFalse(
                require(
                    app.buttons.matching(identifier: identifier).firstMatch,
                    "Deletion failure must keep the pending route control visible: \(identifier)."
                ).isEnabled,
                "Deletion failure must keep the pending route control disabled: \(identifier)."
            )
        }
        tap("session.ohp.persistence.retry", in: app)
        require(
            app.descendants(matching: .any)["session.ohp.journal.error"],
            "The journal must start only after the exact pending training-state write succeeds."
        )
        for identifier in blockedRouteControls {
            XCTAssertTrue(
                require(
                    app.buttons.matching(identifier: identifier).firstMatch,
                    "Successful exact retry must keep the route control visible: \(identifier)."
                ).isEnabled,
                "Successful exact retry must re-enable the route control: \(identifier)."
            )
        }
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

    func testAnsweredPriorSymptomsAndUncertaintyRenderTheShippedStoppedRoute() {
        let answers = [
            (
                identifier: "session.ohp.prior.symptoms-present",
                description: "symptoms-present"
            ),
            (
                identifier: "session.ohp.prior.uncertain",
                description: "uncertain"
            ),
        ]

        for answer in answers {
            let storeIdentifier = UUID()
            let app = XCUIApplication()
            app.launchArguments = [
                "-ui-testing",
                "-ui-test-scenario", "ohp-safety",
                "-ui-test-appearance", "light",
                "-ui-test-store-identifier", storeIdentifier.uuidString,
                "-AppleLanguages", "(tr)",
                "-AppleLocale", "tr_TR",
                "-UIAccessibilityReduceMotionEnabled", "YES",
            ]
            app.launch()

            require(app.descendants(matching: .any)["root.today.content"], "Missing Today.")
            tap("today.action.primary", in: app)
            tap(answer.identifier, in: app)
            require(
                app.descendants(matching: .any)["session.stage.warmup"],
                "A recorded prior answer must leave the question route."
            )
            tap("session.warmup.skip", in: app)
            for _ in 0..<3 {
                tap("session.exercise.next", in: app)
            }

            require(
                app.descendants(matching: .any)["session.ohp.stop"],
                "Prior \(answer.description) must render a real OHP safety stop."
            )
            assertCompleteGeneralLevelTwo(
                in: app,
                reason: "Prior \(answer.description) must retain the complete L2."
            )
            XCTAssertEqual(
                require(
                    app.staticTexts["session.exercise.name"],
                    "The safe alternative must replace the stopped OHP card."
                ).label,
                "Half-Kneeling DB Press"
            )
            XCTAssertFalse(
                app.descendants(matching: .any)["session.ohp.current-symptom"].exists,
                "A prior safety stop must not expose the current-symptom action."
            )
            app.terminate()

            let relaunched = XCUIApplication()
            relaunched.launchArguments = [
                "-ui-testing",
                "-ui-test-scenario", "ohp-safety",
                "-ui-test-appearance", "light",
                "-ui-test-store-identifier", storeIdentifier.uuidString,
                "-AppleLanguages", "(tr)",
                "-AppleLocale", "tr_TR",
                "-UIAccessibilityReduceMotionEnabled", "YES",
            ]
            relaunched.launch()
            require(
                relaunched.descendants(matching: .any)["root.today.content"],
                "The stored-response relaunch must return to Today."
            )
            tap("today.action.primary", in: relaunched)
            XCTAssertFalse(
                relaunched.descendants(matching: .any)["session.ohp.question"].exists,
                "A stored prior response must not reopen the unanswered question."
            )
            require(
                relaunched.descendants(matching: .any)["session.ohp.stop"],
                "Stored prior \(answer.description) must restore the stopped route."
            )
            assertCompleteGeneralLevelTwo(
                in: relaunched,
                reason: "Stored prior \(answer.description) must restore the complete L2."
            )
            XCTAssertEqual(
                require(
                    relaunched.staticTexts["session.exercise.name"],
                    "Stored prior safety state must keep the safe alternative."
                ).label,
                "Half-Kneeling DB Press"
            )
            XCTAssertFalse(
                relaunched.descendants(matching: .any)["session.ohp.current-symptom"].exists
            )
            relaunched.terminate()
        }
    }

    private func assertCompleteGeneralLevelTwo(
        in app: XCUIApplication,
        reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        require(
            app.staticTexts["medical.safety.l2.heading"],
            reason,
            file: file,
            line: line
        )
        XCTAssertEqual(
            require(
                app.staticTexts["medical.safety.l2"],
                "The stable heading must not replace the complete L2 message.",
                file: file,
                line: line
            ).label,
            expectedGeneralMessage,
            file: file,
            line: line
        )
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
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            message,
            file: file,
            line: line
        )
        return element
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
