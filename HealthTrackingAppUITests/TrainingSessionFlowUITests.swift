import XCTest

final class TrainingSessionFlowUITests: XCTestCase {
    private enum Appearance: String {
        case light
        case dark
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTodayAndTrainingOpenTheSameRealFullScreenSession() {
        let app = launchApp(scenario: "seeded", appearance: .light)

        requireFoundationContent("root.today.content", in: app)
        tapAction(
            "today.action.primary",
            in: app,
            message: "Today must expose a real session action."
        )
        requireElement(
            app.descendants(matching: .any)["session.stage.warmup"],
            "Today must open the full-screen warmup stage."
        )
        requireElement(
            app.descendants(matching: .any)["session.root"],
            "The guided flow must own one full-screen semantic root."
        )
        requireElement(
            app.buttons["session.close"],
            "The session must expose one real close button."
        ).tap()

        selectTrainingTab(in: app)
        requireFoundationContent("root.training.content", in: app)
        tapAction(
            "training.day-row.0",
            in: app,
            message: "A seeded Training day must be a real session route."
        )
        requireElement(
            app.descendants(matching: .any)["session.stage.warmup"],
            "Training must resume the same in-progress warmup."
        )
        attachScreenshot(named: "session-warmup-from-training")
    }

    func testGuidedOrderTapBudgetsSafetyAndOptionalSummary() {
        let app = launchApp(scenario: "session-flow", appearance: .light)
        selectTrainingTab(in: app)
        requireFoundationContent("root.training.content", in: app)
        tapAction("training.day-row.0", in: app, message: "Day A must be available.")

        let warmup = requireElement(
            app.descendants(matching: .any)["session.stage.warmup"],
            "The flow must begin at warmup."
        )
        XCTAssertTrue(warmup.isHittable)
        attachScreenshot(named: "session-warmup-light")
        tapAction(
            "session.warmup.skip",
            in: app,
            message: "Warmup needs an explicit skip."
        )

        assertExercise(
            named: "Goblet Squat",
            family: "weightReps",
            in: app
        )
        let target = app.staticTexts["session.exercise.target"].label
        XCTAssertTrue(target.contains("3"))
        XCTAssertTrue(target.contains("RIR"))
        XCTAssertFalse(app.staticTexts["session.exercise.recommendation"].label.isEmpty)
        XCTAssertTrue(app.staticTexts["session.exercise.safety"].label.contains("3sn"))
        XCTAssertFalse(app.staticTexts["session.exercise.failure"].label.isEmpty)
        attachScreenshot(named: "session-weight-reps-safety-light")

        // One field adjustment plus save is exactly two deliberate taps.
        tapAction(
            "session.set.weight.increment",
            in: app,
            message: "Weight must expose a stepper increment."
        )
        tapAction(
            "session.set.save",
            in: app,
            message: "The set save action is required."
        )
        waitForLabel("1 / 3", identifier: "session.exercise.completedSets", in: app)
        tapAction(
            "session.exercise.next",
            in: app,
            message: "Exercise navigation is required."
        )

        assertExercise(named: "Chin-up", family: "reps", in: app)
        // Accepted template prefill saves in one tap.
        tapAction(
            "session.set.save",
            in: app,
            message: "Reps prefill must be directly savable."
        )
        waitForLabel("1 / 3", identifier: "session.exercise.completedSets", in: app)
        // A RIR choice plus save is exactly two deliberate taps.
        tapAction("session.set.rir.2", in: app, message: "RIR 2 must be selectable.")
        tapAction(
            "session.set.save",
            in: app,
            message: "The second set save is required."
        )
        waitForLabel("2 / 3", identifier: "session.exercise.completedSets", in: app)

        tapAction(
            "session.exercise.finish-incomplete",
            in: app,
            message: "An incomplete session must have an explicit safe finish action."
        )
        let summary = requireElement(
            app.descendants(matching: .any)["session.stage.summary"],
            "Incomplete finish must preserve sets and open summary."
        )
        XCTAssertTrue(summary.isHittable)
        let recoveryUnset = requireElement(
            identified("session.summary.recovery.unset", in: app),
            "Recovery must default to an explicit unset choice."
        )
        XCTAssertEqual(recoveryUnset.value as? String, "Seçili")
        let note = requireElement(
            app.textViews["session.summary.note"],
            "Summary note must be optional."
        )
        XCTAssertEqual(note.value as? String, "")
        XCTAssertFalse(
            app.descendants(matching: .any)["session.summary.warmup"].label.isEmpty
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["session.summary.cooldown"].label.isEmpty
        )
        attachScreenshot(named: "session-summary-optional-empty-light")
    }

    func testEveryMeasurementBarFamilyCooldownAndSummaryHaveLightDarkEvidence() {
        for appearance in [Appearance.light, .dark] {
            let app = launchApp(scenario: "session-families", appearance: appearance)
            requireFoundationContent("root.today.content", in: app)
            tapAction(
                "today.action.primary",
                in: app,
                message: "The family fixture must use the real Today route."
            )
            requireElement(
                identified("session.warmup.skip", in: app),
                "The family fixture must enter the real deck through warmup."
            )
            attachScreenshot(named: "session-warmup-\(appearance.rawValue)")
            tapAction(
                "session.warmup.skip",
                in: app,
                message: "The family fixture must enter the real deck through warmup."
            )

            let families = [
                (name: "weightReps", control: "session.set.weight.increment"),
                (name: "reps", control: "session.set.reps.increment"),
                (name: "duration", control: "session.set.duration.increment"),
                (name: "steps", control: "session.set.steps.increment"),
                (name: "quality", control: "session.set.quality.reps.increment"),
            ]
            for family in families {
                requireElement(
                    app.descendants(matching: .any)["session.set.family.\(family.name)"],
                    "The \(family.name) recording bar must be rendered."
                )
                if family.name == "weightReps" {
                    attachScreenshot(named: "session-safety-\(appearance.rawValue)")
                }
                let familyControl = requireElement(
                    identified(family.control, in: app),
                    "The \(family.name) family needs a visible measurement control."
                )
                makeHittable(familyControl, in: app)
                XCTAssertTrue(
                    familyControl.isHittable,
                    "The \(family.name) measurement control must be visible in its evidence."
                )
                attachScreenshot(
                    named: "session-family-\(family.name)-\(appearance.rawValue)"
                )
                tapAction(
                    "session.set.save",
                    in: app,
                    message: "Every deterministic family fixture must have a valid accepted prefill."
                )
                tapAction(
                    "session.exercise.next",
                    in: app,
                    message: "Every family card must advance through the same real flow."
                )
            }

            requireElement(
                app.descendants(matching: .any)["session.stage.cooldown"],
                "All measurement families must lead to cooldown."
            )
            attachScreenshot(named: "session-cooldown-\(appearance.rawValue)")
            tapAction(
                "session.cooldown.skip",
                in: app,
                message: "Cooldown needs explicit skip."
            )
            requireElement(
                app.descendants(matching: .any)["session.stage.summary"],
                "Cooldown must lead to summary."
            )
            attachScreenshot(named: "session-summary-\(appearance.rawValue)")
            app.terminate()
        }
    }

    func testResumeRestoresTheSameMovementAcrossRelaunch() {
        let first = launchApp(scenario: "session-resume", appearance: .light)
        requireFoundationContent("root.today.content", in: first)
        tapAction(
            "today.action.primary",
            in: first,
            message: "Resume needs a real Today action."
        )
        assertExercise(named: "Plank / Pallof", family: "duration", in: first)
        attachScreenshot(named: "session-resume-before-relaunch")
        first.terminate()

        let second = launchApp(scenario: "session-resume", appearance: .light)
        requireFoundationContent("root.today.content", in: second)
        tapAction(
            "today.action.primary",
            in: second,
            message: "Relaunch must expose resume."
        )
        assertExercise(named: "Plank / Pallof", family: "duration", in: second)
        attachScreenshot(named: "session-resume-after-relaunch")
    }

    func testMissingRIRHistoryNeverDisplaysALoadIncrease() {
        let app = launchApp(scenario: "progression-missing-rir", appearance: .light)
        requireFoundationContent("root.today.content", in: app)
        tapAction(
            "today.action.primary",
            in: app,
            message: "The progression fixture must use the real Today route."
        )
        tapAction(
            "session.warmup.skip",
            in: app,
            message: "The progression fixture must enter the real exercise deck."
        )

        let recommendation = requireElement(
            app.staticTexts["session.exercise.recommendation"],
            "Missing RIR needs an explicit hold reason."
        )
        XCTAssertTrue(recommendation.label.contains("RIR"))
        XCTAssertFalse(recommendation.label.contains("+2,5"))
        attachScreenshot(named: "session-progression-missing-rir-light")
    }

    func testWeeklyPallofVariantChooserPersistsExplicitOverride() {
        let app = launchApp(scenario: "weekly-pallof", appearance: .light)
        requireFoundationContent("root.today.content", in: app)
        tapAction(
            "today.action.primary",
            in: app,
            message: "The weekly Pallof fixture must use the real Today route."
        )
        assertExercise(named: "Plank / Pallof", family: "duration", in: app)

        let pallof = requireElement(
            app.buttons["session.set.variant.pallof"],
            "Pallof must be a real accessible variant choice."
        )
        let plank = requireElement(
            app.buttons["session.set.variant.plank"],
            "Plank must be a real accessible variant choice."
        )
        XCTAssertEqual(pallof.value as? String, "Seçili")
        XCTAssertEqual(plank.value as? String, "")

        plank.tap()
        XCTAssertEqual(plank.value as? String, "Seçili")
        tapAction(
            "session.set.save",
            in: app,
            message: "The explicit Plank override must persist as the real set value."
        )
        waitForLabel("1 / 3", identifier: "session.exercise.completedSets", in: app)
        XCTAssertEqual(
            requireElement(
                app.buttons["session.set.variant.plank"],
                "The next set must preserve the user's real variant override."
            ).value as? String,
            "Seçili"
        )
        attachScreenshot(named: "session-weekly-pallof-override-light")
    }

    private func assertExercise(
        named expectedName: String,
        family: String,
        in app: XCUIApplication
    ) {
        requireElement(
            app.descendants(matching: .any)["session.stage.exercise"],
            "The exercise stage must be visible."
        )
        let name = requireElement(
            app.staticTexts["session.exercise.name"],
            "The exercise must expose a stable semantic name."
        )
        XCTAssertEqual(name.label, expectedName)
        requireElement(
            app.descendants(matching: .any)["session.set.family.\(family)"],
            "The \(family) set bar must match \(expectedName)."
        )
    }

    private func launchApp(scenario: String, appearance: Appearance) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", scenario,
            "-ui-test-appearance", appearance.rawValue,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        return app
    }

    private func selectTrainingTab(in app: XCUIApplication) {
        let tab = requireElement(
            app.descendants(matching: .any)["tab.training"],
            "Training tab must be available."
        )
        tab.tap()
        requireElement(
            app.descendants(matching: .any)["root.training"],
            "Training tab must expose its distinct root."
        )
    }

    private func requireFoundationContent(
        _ identifier: String,
        in app: XCUIApplication
    ) {
        requireElement(
            app.descendants(matching: .any)[identifier],
            "The seeded foundation content must finish loading before routing."
        )
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func tapAction(
        _ identifier: String,
        in app: XCUIApplication,
        message: String
    ) {
        let element = requireElement(identified(identifier, in: app), message)
        makeHittable(element, in: app)
        XCTAssertTrue(element.isHittable, "\(message) The action must become hittable.")
        element.tap()
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var remainingScrolls = 10
        while remainingScrolls > 0 {
            let elementFrame = element.frame
            let needsSafeSessionPosition = element.identifier.hasPrefix("session.")
            let isSafelyPositioned = !needsSafeSessionPosition || (
                !elementFrame.isEmpty &&
                    elementFrame.minY >= app.frame.minY + 44 &&
                    elementFrame.maxY <= app.frame.maxY - 44
            )
            if element.isHittable && isSafelyPositioned {
                return
            }
            let isAboveViewport = !elementFrame.isEmpty
                && elementFrame.midY < app.frame.midY
            if isAboveViewport {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            remainingScrolls -= 1
        }
    }

    private func waitForLabel(
        _ label: String,
        identifier: String,
        in app: XCUIApplication
    ) {
        let element = app.staticTexts[identifier]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 8),
            .completed,
            "Expected \(identifier) to become \(label); found \(element.label)."
        )
    }

    @discardableResult
    private func requireElement(
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
