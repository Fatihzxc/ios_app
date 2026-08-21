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
        _ = assertFiftyTwoPointTarget("session.exercise.back", in: app)
        _ = assertFiftyTwoPointTarget("session.exercise.finish-incomplete", in: app)
    }

    func testLightDarkAndDynamicTypeMatrixPassesSessionAudit() throws {
        for appearance in Appearance.allCases {
            var safetyHeadingHeights: [(size: String, height: CGFloat)] = []
            var recommendationHeights: [(size: String, height: CGFloat)] = []

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
                scrollToTop(in: app)
                let safetyHeading = require(
                    app.staticTexts["session.exercise.safety.heading"],
                    "The safety status heading must remain a concrete text element."
                )
                let recommendation = require(
                    app.staticTexts["session.set.recommendation"],
                    "The set recommendation must remain a concrete text element."
                )
                safetyHeadingHeights.append(
                    (size: textSize.rawValue, height: safetyHeading.frame.height)
                )
                recommendationHeights.append(
                    (size: textSize.rawValue, height: recommendation.frame.height)
                )
                try app.performAccessibilityAudit(
                    for: [.elementDetection, .hitRegion, .dynamicType, .textClipped]
                ) { issue in
                    self.isVerifiedStatusPillDynamicTypeFalsePositive(issue)
                }
                attachScreenshot(
                    named: "m1-session-\(appearance.rawValue)-\(textSize.rawValue)"
                )
                app.terminate()
            }

            assertStrictDynamicTypeGrowth(
                safetyHeadingHeights,
                element: "session.exercise.safety.heading",
                appearance: appearance
            )
            assertStrictDynamicTypeGrowth(
                recommendationHeights,
                element: "session.set.recommendation",
                appearance: appearance
            )
            try attachDynamicTypeEvidence(
                appearance: appearance,
                safetyHeadingHeights: safetyHeadingHeights,
                recommendationHeights: recommendationHeights
            )
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
        let variantLabel = require(
            app.staticTexts["session.set.variant.label"],
            "The small-phone AX5 form must render the full performed-variant label outside the field."
        )
        makeVisible(variantLabel, in: app)
        XCTAssertEqual(variantLabel.label, "Uygulanan varyasyon (opsiyonel)")
        XCTAssertTrue(
            app.frame.contains(variantLabel.frame),
            "The full performed-variant label must remain inside the small-phone viewport. "
                + "Label: \(variantLabel.frame), viewport: \(app.frame)"
        )
        XCTAssertGreaterThan(
            variantLabel.frame.height,
            60,
            "The performed-variant label must wrap instead of truncating at AX5."
        )
        let variantField = require(
            app.textFields["session.set.variant"],
            "The performed-variant field must remain an accessible text field."
        )
        XCTAssertEqual(variantField.label, "Uygulanan varyasyon (opsiyonel)")
        XCTAssertTrue(
            variantField.placeholderValue?.isEmpty ?? true,
            "The external label must not be repeated as a clipped field placeholder."
        )
        attachScreenshot(named: "m1-session-small-ax5")
        // The two-appearance matrix owns the Dynamic Type audit and direct
        // default-to-AX5 growth measurements. This dedicated gate validates
        // the already-forced AX5 small-phone layout without asking Xcode to
        // initiate another font-size transition from the maximum category.
        try app.performAccessibilityAudit(for: [.textClipped])
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
        position(element, in: app, requiresHittable: true)
    }

    private func makeVisible(_ element: XCUIElement, in app: XCUIApplication) {
        position(element, in: app, requiresHittable: false)
    }

    private func position(
        _ element: XCUIElement,
        in app: XCUIApplication,
        requiresHittable: Bool
    ) {
        let safetyInset: CGFloat = requiresHittable ? 44 : 0
        var remainingScrolls = 12
        while remainingScrolls > 0 {
            let frame = element.frame
            let isSafelyPositioned = !frame.isEmpty &&
                frame.minY >= app.frame.minY + safetyInset &&
                frame.maxY <= app.frame.maxY - safetyInset
            if isSafelyPositioned && (!requiresHittable || element.isHittable) {
                return
            }
            if !requiresHittable {
                scrollByShortDrag(
                    towardTop: !frame.isEmpty && frame.midY > app.frame.midY,
                    in: app
                )
            } else if !frame.isEmpty, frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            remainingScrolls -= 1
        }
    }

    private func scrollByShortDrag(towardTop: Bool, in app: XCUIApplication) {
        let upper = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)
        )
        let lower = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60)
        )
        let start = towardTop ? lower : upper
        let end = towardTop ? upper : lower
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func scrollToTop(in app: XCUIApplication) {
        for _ in 0..<10 {
            app.swipeDown()
        }
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func isVerifiedStatusPillDynamicTypeFalsePositive(
        _ issue: XCUIAccessibilityAuditIssue
    ) -> Bool {
        guard issue.auditType == .dynamicType,
              let identifier = issue.element?.identifier else {
            return false
        }
        return identifier == "session.exercise.safety.heading"
            || identifier == "session.set.recommendation"
    }

    private func assertStrictDynamicTypeGrowth(
        _ measurements: [(size: String, height: CGFloat)],
        element: String,
        appearance: Appearance
    ) {
        XCTAssertEqual(measurements.count, TextSize.allCases.count)
        for index in 1..<measurements.count {
            let previous = measurements[index - 1]
            let current = measurements[index]
            XCTAssertGreaterThan(
                current.height,
                previous.height,
                "\(element) must grow from \(previous.size) to \(current.size) in \(appearance.rawValue)."
            )
        }
    }

    private func attachDynamicTypeEvidence(
        appearance: Appearance,
        safetyHeadingHeights: [(size: String, height: CGFloat)],
        recommendationHeights: [(size: String, height: CGFloat)]
    ) throws {
        let rows = zip(safetyHeadingHeights, recommendationHeights).map { safety, recommendation in
            [
                "textSize": safety.size,
                "safetyHeadingHeight": Double(safety.height),
                "recommendationHeight": Double(recommendation.height),
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(
            withJSONObject: [
                "appearance": appearance.rawValue,
                "measurements": rows,
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "m1-status-pill-dynamic-type-\(appearance.rawValue)"
        attachment.lifetime = .keepAlways
        add(attachment)
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
