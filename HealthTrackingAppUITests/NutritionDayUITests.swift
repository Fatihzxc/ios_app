import Foundation
import XCTest

final class NutritionDayUITests: XCTestCase {
    private let geometryTolerance: CGFloat = 0.01

    private enum Scenario: String {
        case content = "nutrition-content"
        case empty = "nutrition-empty"
        case errorOnce = "nutrition-error-once"
        case deleteErrorOnce = "nutrition-delete-error-once"
    }

    private enum Appearance: String {
        case light
        case dark
    }

    private enum TextSize {
        case standard
        case ax5

        var launchArguments: [String] {
            switch self {
            case .standard:
                []
            case .ax5:
                [
                    "-UIPreferredContentSizeCategoryName",
                    "UICTContentSizeCategoryAccessibilityXXXL",
                ]
            }
        }
    }

    private let fixtureEntryID = "00000000-0000-4000-8000-00000000d101"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testContentExposesCalendarNavigationTotalsStableCategoriesAndVoiceOverOrder() {
        let app = launchNutrition(scenario: .content, appearance: .light)
        let date = require(
            identified("nutrition.day.date", in: app),
            "The selected local day must expose a semantic date header."
        )
        let initialDateValue = date.value as? String
        XCTAssertFalse(initialDateValue?.isEmpty ?? true)

        let previous = assertFiftyTwoPointTarget(
            "nutrition.day.previous",
            in: app,
            label: "Önceki gün"
        )
        XCTAssertFalse(
            (previous.value as? String)?.isEmpty ?? true,
            "Previous-day navigation must announce its destination date."
        )
        previous.tap()
        waitForValue(of: date, toDifferFrom: initialDateValue)

        let next = assertFiftyTwoPointTarget(
            "nutrition.day.next",
            in: app,
            label: "Sonraki gün"
        )
        XCTAssertFalse(
            (next.value as? String)?.isEmpty ?? true,
            "Next-day navigation must announce its destination date."
        )
        next.tap()
        waitForValue(of: date, toEqual: initialDateValue)

        let picker = assertFiftyTwoPointTarget(
            "nutrition.day.date-picker",
            in: app,
            label: "Tarih seç"
        )
        XCTAssertFalse(
            (picker.value as? String)?.isEmpty ?? true,
            "The date picker must announce the currently selected date."
        )

        let total = require(
            identified("nutrition.day.total", in: app),
            "A loaded content day must expose one combined total summary."
        )
        XCTAssertTrue(total.label.contains("Gün toplamı"))
        XCTAssertFalse((total.value as? String)?.isEmpty ?? true)

        let protein = require(
            identified("nutrition.day.macro.protein", in: app),
            "Protein must expose consumed, target and remaining semantics."
        )
        XCTAssertEqual(protein.label, "Protein")
        XCTAssertTrue((protein.value as? String)?.contains("hedef") == true)
        XCTAssertTrue((protein.value as? String)?.contains("kalan") == true)

        let standardSections = [
            ("breakfast", "Kahvaltı"),
            ("lunch", "Öğle"),
            ("dinner", "Akşam"),
            ("snack", "Ara Öğün"),
        ]
        for (identifier, label) in standardSections {
            let section = require(
                identified("nutrition.day.section.\(identifier)", in: app),
                "Every standard category must remain present in a stable order."
            )
            XCTAssertEqual(section.label, label)
        }
        let customSection = require(
            identified("nutrition.day.section.custom.antrenman-sonrasi", in: app),
            "A populated custom category must follow all localized standard categories."
        )
        XCTAssertEqual(customSection.label, "Antrenman sonrası")

        let entry = require(
            identified("nutrition.day.entry.\(fixtureEntryID)", in: app),
            "The deterministic content fixture must expose its meal snapshot."
        )
        XCTAssertTrue(entry.label.contains("Yoğurt"))
        XCTAssertTrue((entry.value as? String)?.contains("Protein") == true)

        assertReadingOrder(
            [
                "nutrition.day.date",
                "nutrition.day.total",
                "nutrition.day.macro.protein",
                "nutrition.day.section.breakfast",
                "nutrition.day.entry.\(fixtureEntryID)",
            ],
            in: app
        )
        attachScreenshot(named: "nutrition-day-content-light")
    }

    func testEmptyAndRecoverableErrorStatesRemainDistinctAndRetrySameDay() {
        let empty = launchNutrition(scenario: .empty, appearance: .light)
        let emptyState = require(
            identified("nutrition.day.state.empty", in: empty),
            "A loaded day without entries must render the designed empty state."
        )
        XCTAssertFalse(identified("nutrition.day.state.error", in: empty).exists)
        makeVisibleAboveTabBar(emptyState, in: empty)
        attachScreenshot(named: "nutrition-day-empty-light")
        empty.terminate()

        let error = launchNutrition(
            scenario: .errorOnce,
            appearance: .dark,
            waitsForLoadedDay: false
        )
        let errorState = require(
            identified("nutrition.day.state.error", in: error),
            "A recoverable repository failure must not masquerade as an empty day."
        )
        XCTAssertFalse(errorState.label.isEmpty)
        XCTAssertFalse(identified("nutrition.day.state.empty", in: error).exists)
        attachScreenshot(named: "nutrition-day-error-dark")

        let retry = assertFiftyTwoPointTarget(
            "nutrition.day.retry",
            in: error,
            label: "Yeniden dene"
        )
        let selectedDate = identified("nutrition.day.date", in: error).value as? String
        retry.tap()
        require(
            identified("nutrition.day.loaded", in: error),
            "Retry must reload the same selected day through the real repository path."
        )
        require(
            identified("nutrition.day.entry.\(fixtureEntryID)", in: error),
            "Retry must publish the repository-backed content fixture."
        )
        XCTAssertEqual(
            identified("nutrition.day.date", in: error).value as? String,
            selectedDate,
            "Retry must retain the selected local day."
        )
        XCTAssertFalse(identified("nutrition.day.state.error", in: error).exists)
    }

    func testDeleteFailureRollsBackAndRetryPublishesRepositoryTotals() {
        let app = launchNutrition(scenario: .deleteErrorOnce, appearance: .light)
        let total = require(
            identified("nutrition.day.total", in: app),
            "The delete fixture must expose its initial day total."
        )
        let initialTotal = total.value as? String
        let entry = identified("nutrition.day.entry.\(fixtureEntryID)", in: app)
        require(entry, "The delete fixture must begin with the target entry.")

        let delete = assertFiftyTwoPointTarget(
            "nutrition.day.entry.\(fixtureEntryID).delete",
            in: app,
            label: "Öğünü sil"
        )
        delete.tap()

        let mutationError = require(
            identified("nutrition.day.mutation.error", in: app),
            "A failed optimistic delete must publish an accessible retryable error."
        )
        XCTAssertFalse(mutationError.label.isEmpty)
        let exposesRawEntryID = app.descendants(matching: .any)
            .allElementsBoundByIndex
            .contains { element in
                let value = element.value as? String
                return element.label.localizedCaseInsensitiveContains(fixtureEntryID)
                    || value?.localizedCaseInsensitiveContains(fixtureEntryID) == true
            }
        XCTAssertFalse(
            exposesRawEntryID,
            "VoiceOver must not expose an opaque persistence identifier."
        )
        require(entry, "A failed optimistic delete must restore the original row.")
        XCTAssertEqual(total.value as? String, initialTotal)

        let retry = assertFiftyTwoPointTarget(
            "nutrition.day.mutation.retry",
            in: app,
            label: "Silmeyi yeniden dene"
        )
        retry.tap()
        waitForDisappearance(entry)
        XCTAssertFalse(identified("nutrition.day.mutation.error", in: app).exists)
        XCTAssertNotEqual(total.value as? String, initialTotal)
    }

    func testDarkAX5ReduceMotionAndIncreaseContrastProduceCanonicalEvidence() throws {
        let dark = launchNutrition(scenario: .content, appearance: .dark)
        attachScreenshot(named: "nutrition-day-content-dark")
        dark.terminate()

        let ax5 = launchNutrition(
            scenario: .content,
            appearance: .light,
            textSize: .ax5
        )
        for identifier in [
            "nutrition.day.macro.calories",
            "nutrition.day.macro.protein",
            "nutrition.day.section.breakfast",
        ] {
            let element = require(
                identified(identifier, in: ax5),
                "AX5 must keep \(identifier) rendered and reachable."
            )
            makeVisible(element, in: ax5)
            XCTAssertFalse(element.frame.isEmpty)
            XCTAssertTrue(
                isContained(element.frame, in: ax5.frame),
                "AX5 must wrap vertically without clipping \(identifier). "
                    + "Element frame: \(element.frame); app frame: \(ax5.frame)."
            )
        }
        attachScreenshot(named: "nutrition-day-content-ax5")
        ax5.terminate()

        let reduceMotion = launchNutrition(
            scenario: .content,
            appearance: .light,
            extraArguments: ["-UIAccessibilityReduceMotionEnabled", "YES"]
        )
        assertFiftyTwoPointTarget(
            "nutrition.day.previous",
            in: reduceMotion,
            label: "Önceki gün"
        ).tap()
        let reduceMotionEmptyState = require(
            identified("nutrition.day.state.empty", in: reduceMotion),
            "Reduce Motion calendar navigation must expose the empty-day card."
        )
        makeVisibleAboveTabBar(reduceMotionEmptyState, in: reduceMotion)
        require(
            identified("nutrition.day.loaded", in: reduceMotion),
            "Reduce Motion must retain calendar navigation and a loaded day state."
        )
        attachScreenshot(named: "nutrition-day-reduce-motion-light")
        reduceMotion.terminate()

        let highContrast = launchNutrition(
            scenario: .content,
            appearance: .dark,
            extraArguments: ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
        )
        require(
            identified("nutrition.day.total", in: highContrast),
            "Increase Contrast must retain the semantic macro summary."
        )
        attachScreenshot(named: "nutrition-day-high-contrast-dark")
    }

    @discardableResult
    private func launchNutrition(
        scenario: Scenario,
        appearance: Appearance,
        textSize: TextSize = .standard,
        extraArguments: [String] = [],
        waitsForLoadedDay: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", scenario.rawValue,
            "-ui-test-appearance", appearance.rawValue,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + textSize.launchArguments + extraArguments
        app.launch()

        let nutritionTab = require(
            identified("tab.nutrition", in: app),
            "The five-tab shell must expose the Nutrition route."
        )
        nutritionTab.tap()
        require(
            identified("root.nutrition", in: app),
            "The Nutrition tab must own one isolated navigation root."
        )
        if waitsForLoadedDay {
            require(
                identified("nutrition.day.loaded", in: app),
                "The deterministic fixture must finish its Nutrition day load."
            )
        }
        return app
    }

    @discardableResult
    private func assertFiftyTwoPointTarget(
        _ identifier: String,
        in app: XCUIApplication,
        label: String
    ) -> XCUIElement {
        let element = require(identified(identifier, in: app), "Missing action \(identifier).")
        makeHittable(element, in: app)
        XCTAssertEqual(element.label, label)
        XCTAssertTrue(element.isHittable, "\(identifier) must be hittable.")
        XCTAssertGreaterThanOrEqual(
            element.frame.width + geometryTolerance,
            52,
            "\(identifier) must remain at least 52 points wide. Frame: \(element.frame)"
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height + geometryTolerance,
            52,
            "\(identifier) must remain at least 52 points tall. Frame: \(element.frame)"
        )
        return element
    }

    private func assertReadingOrder(_ identifiers: [String], in app: XCUIApplication) {
        let published = app.descendants(matching: .any)
            .allElementsBoundByIndex
            .map(\.identifier)
        let positions = identifiers.map { identifier -> Int in
            guard let position = published.firstIndex(of: identifier) else {
                XCTFail("VoiceOver order is missing \(identifier).")
                return Int.max
            }
            return position
        }
        XCTAssertEqual(
            positions,
            positions.sorted(),
            "Date, total, categories and entries must follow the visual reading order."
        )
    }

    private func waitForValue(
        of element: XCUIElement,
        toDifferFrom original: String?
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", original ?? ""),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func waitForValue(of element: XCUIElement, toEqual expected: String?) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected ?? ""),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func waitForDisappearance(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func makeVisible(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 {
            let frame = element.frame
            if isContained(frame, in: app.frame) { return }
            if frame.maxY > app.frame.maxY + geometryTolerance {
                scrollUpSmallStep(in: app)
            } else if frame.minY < app.frame.minY - geometryTolerance {
                scrollDownSmallStep(in: app)
            } else {
                return
            }
        }
    }

    private func makeVisibleAboveTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<10 {
            let frame = element.frame
            let visibleBottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
            if !frame.isEmpty,
               frame.minY >= app.frame.minY - geometryTolerance,
               frame.maxY <= visibleBottom - geometryTolerance {
                return
            }
            app.swipeUp()
        }

        let visibleBottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
        XCTAssertFalse(element.frame.isEmpty, "Empty-state evidence must have a rendered frame.")
        XCTAssertLessThanOrEqual(
            element.frame.maxY,
            visibleBottom - geometryTolerance,
            "Empty-state evidence must not be obscured by the tab bar."
        )
    }

    private func scrollUpSmallStep(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.46)
                )
            )
    }

    private func scrollDownSmallStep(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.46))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58)
                )
            )
    }

    private func isContained(_ frame: CGRect, in container: CGRect) -> Bool {
        !frame.isEmpty
            && container.insetBy(
                dx: -geometryTolerance,
                dy: -geometryTolerance
            ).contains(frame)
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
