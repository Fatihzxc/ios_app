import XCTest

final class TrainingAccessibilityUITests: XCTestCase {
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

    func testVoiceOverOrderValuesActionsAndFiftyTwoPointSessionTargets() {
        let app = launchSession(appearance: .light, textSize: .default)

        let todaySummary = require(
            identified("today.accessibility.summary", in: app),
            "Today must publish phase, directive and context as one meaningful VoiceOver summary."
        )
        XCTAssertFalse(todaySummary.label.isEmpty)
        tap("today.action.primary", in: app)
        tap("session.warmup.skip", in: app)

        let orderedIdentifiers = [
            "session.exercise.name",
            "session.exercise.target",
            "session.exercise.completedSets",
            "session.exercise.recommendation",
            "session.exercise.safety",
            "session.set.family.weightReps",
            "session.set.save",
            "session.exercise.next",
        ]
        let publishedIdentifiers = app.descendants(matching: .any)
            .allElementsBoundByIndex
            .map(\.identifier)
        let positions = orderedIdentifiers.map { identifier -> Int in
            guard let position = publishedIdentifiers.firstIndex(of: identifier) else {
                XCTFail("VoiceOver order is missing \(identifier).")
                return Int.max
            }
            return position
        }
        XCTAssertEqual(
            positions,
            positions.sorted(),
            "Exercise semantics and actions must follow the visual reading order."
        )

        let name = require(app.staticTexts["session.exercise.name"], "Exercise name is required.")
        let target = require(app.staticTexts["session.exercise.target"], "Exercise target is required.")
        let completed = require(
            app.staticTexts["session.exercise.completedSets"],
            "Completed-set state is required."
        )
        let recommendation = require(
            app.staticTexts["session.exercise.recommendation"],
            "Recommendation semantics are required."
        )
        let safety = require(
            app.staticTexts["session.exercise.safety"],
            "Safety semantics are required."
        )
        for element in [name, target, completed, recommendation, safety] {
            XCTAssertFalse(element.label.isEmpty)
        }

        let decrement = assertFiftyTwoPointTarget(
            "session.set.weight.decrement",
            in: app
        )
        let increment = assertFiftyTwoPointTarget(
            "session.set.weight.increment",
            in: app
        )
        XCTAssertGreaterThanOrEqual(
            increment.frame.minX - decrement.frame.maxX,
            8,
            "Stepper actions need at least eight points of separation."
        )
        _ = assertFiftyTwoPointTarget("session.set.rir.2", in: app)
        _ = assertFiftyTwoPointTarget("session.set.save", in: app)
        _ = assertFiftyTwoPointTarget("session.exercise.next", in: app)
    }

    func testLightDarkAndDynamicTypeMatrixPassesSessionAudit() throws {
        for appearance in Appearance.allCases {
            for textSize in TextSize.allCases {
                let app = launchSession(appearance: appearance, textSize: textSize)
                tap("today.action.primary", in: app)
                tap("session.warmup.skip", in: app)
                let stage = require(
                    identified("session.stage.exercise", in: app),
                    "Every appearance and text-size fixture must reach the exercise stage."
                )
                XCTAssertTrue(stage.isHittable)
                _ = assertFiftyTwoPointTarget("session.set.weight.increment", in: app)
                _ = assertFiftyTwoPointTarget("session.set.save", in: app)
                try app.performAccessibilityAudit(
                    for: [.elementDetection, .hitRegion, .dynamicType, .textClipped]
                )
                scrollToTop(in: app)
                attachScreenshot(
                    named: "m1-session-\(appearance.rawValue)-\(textSize.rawValue)"
                )
                app.terminate()
            }
        }
    }

    func testReduceMotionAndHighContrastFlowsRemainOperable() {
        let reduceMotion = launchSession(
            appearance: .light,
            textSize: .ax3,
            extraArguments: ["-UIAccessibilityReduceMotionEnabled", "YES"]
        )
        tap("today.action.primary", in: reduceMotion)
        tap("session.warmup.skip", in: reduceMotion)
        require(
            identified("session.stage.exercise", in: reduceMotion),
            "Reduce Motion must retain the same semantic stage transition."
        )
        attachScreenshot(named: "m1-session-reduce-motion")
        reduceMotion.terminate()

        let highContrast = launchSession(
            appearance: .dark,
            textSize: .ax3,
            extraArguments: ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
        )
        tap("today.action.primary", in: highContrast)
        tap("session.warmup.skip", in: highContrast)
        require(
            identified("session.stage.exercise", in: highContrast),
            "Increase Contrast must retain the same semantic stage transition."
        )
        attachScreenshot(named: "m1-session-high-contrast")
    }

    func testSmallPhoneAX5SessionRemainsOperable() throws {
        let app = launchSession(appearance: .light, textSize: .ax5)
        guard app.frame.width <= 390 else {
            throw XCTSkip("The canonical small-phone gate runs in the dedicated CI job.")
        }
        tap("today.action.primary", in: app)
        tap("session.warmup.skip", in: app)
        require(
            identified("session.stage.exercise", in: app),
            "The small-phone AX5 fixture must reach the exercise stage."
        )
        _ = assertFiftyTwoPointTarget("session.set.weight.increment", in: app)
        _ = assertFiftyTwoPointTarget("session.set.save", in: app)
        attachScreenshot(named: "m1-session-small-ax5")
    }

    private func launchSession(
        appearance: Appearance,
        textSize: TextSize,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "session-flow",
            "-ui-test-appearance", appearance.rawValue,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + textSize.launchArguments + extraArguments
        app.launch()
        require(
            identified("root.today.content", in: app),
            "The accessibility fixture must load real Today content."
        )
        return app
    }

    @discardableResult
    private func assertFiftyTwoPointTarget(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        let element = require(identified(identifier, in: app), "Missing \(identifier).")
        makeHittable(element, in: app)
        XCTAssertTrue(element.isHittable, "\(identifier) must be hittable.")
        XCTAssertGreaterThanOrEqual(element.frame.width, 52, "\(identifier) must be at least 52 pt wide.")
        XCTAssertGreaterThanOrEqual(element.frame.height, 52, "\(identifier) must be at least 52 pt high.")
        return element
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = require(identified(identifier, in: app), "Missing action \(identifier).")
        makeHittable(element, in: app)
        XCTAssertTrue(element.isHittable, "\(identifier) must become hittable.")
        element.tap()
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var remainingScrolls = 12
        while !element.isHittable, remainingScrolls > 0 {
            let frame = element.frame
            if !frame.isEmpty, frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            remainingScrolls -= 1
        }
    }

    private func scrollToTop(in app: XCUIApplication) {
        for _ in 0..<10 {
            app.swipeDown()
        }
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
