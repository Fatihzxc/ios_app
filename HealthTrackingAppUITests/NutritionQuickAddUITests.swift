import Foundation
import XCTest

final class NutritionQuickAddUITests: XCTestCase {
    private enum Scenario: String {
        case quickAdd = "nutrition-quick-add"
        case errorOnce = "nutrition-quick-add-error-once"
    }

    private enum Appearance: String {
        case light
        case dark
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCategoryRouteSavesInExactlyThreeTapsAndPersistsAfterRelaunch() {
        let storeIdentifier = UUID()
        let app = launch(
            scenario: .quickAdd,
            appearance: .light,
            storeIdentifier: storeIdentifier,
            opensNutrition: true
        )
        let total = require(
            identified("nutrition.day.total", in: app),
            "The quick-add fixture must expose its baseline day total."
        )
        XCTAssertTrue((total.value as? String)?.contains("370") == true)
        var taps = 0

        let categoryAdd = require(
            identified("nutrition.day.section.breakfast.add", in: app),
            "Tap one must be the selected category's add action."
        )
        makeHittable(categoryAdd, in: app)
        tapAndCount(categoryAdd, count: &taps)
        require(
            identified("nutrition.quick-add.root", in: app),
            "The category intent must open the app's quick-add route."
        )
        tapAndCount(firstRecipe(in: app), count: &taps)

        let quantity = require(
            identified("nutrition.quick-add.quantity", in: app),
            "The confirmation must prefill one serving without an extra required tap."
        )
        XCTAssertTrue((quantity.value as? String)?.contains("1") == true)
        attachScreenshot(named: "nutrition-quick-add-light")
        tapAndCount(
            require(
                identified("nutrition.quick-add.confirm", in: app),
                "Tap three must confirm the default one-serving intent."
            ),
            count: &taps
        )

        XCTAssertEqual(taps, 3)
        waitForDisappearance(identified("nutrition.quick-add.root", in: app))
        waitForValue(of: total, containing: "570")
        app.terminate()

        let relaunched = launch(
            scenario: .quickAdd,
            appearance: .light,
            storeIdentifier: storeIdentifier,
            opensNutrition: true
        )
        let persistedTotal = require(
            identified("nutrition.day.total", in: relaunched),
            "Relaunch must load the disk-backed canonical meal snapshot."
        )
        XCTAssertTrue((persistedTotal.value as? String)?.contains("570") == true)
        XCTAssertFalse(identified("nutrition.quick-add.root", in: relaunched).exists)
    }

    func testTodayMealActionAlsoCompletesInExactlyThreeTaps() {
        let app = launch(
            scenario: .quickAdd,
            appearance: .light,
            storeIdentifier: UUID(),
            opensNutrition: false
        )
        require(
            identified("root.today.content", in: app),
            "The workout directive must be visible before the nutrition route starts."
        )
        var taps = 0

        tapAndCount(
            require(
                identified("today.nutrition.action", in: app),
                "Tap one must be Today's app-owned meal action."
            ),
            count: &taps
        )
        require(
            identified("root.nutrition", in: app),
            "Today must switch to the Nutrition tab without cross-feature imports."
        )
        require(
            identified("nutrition.quick-add.root", in: app),
            "Today must carry the inferred local-day category intent."
        )
        tapAndCount(firstRecipe(in: app), count: &taps)
        tapAndCount(
            require(
                identified("nutrition.quick-add.confirm", in: app),
                "Tap three must save the default serving."
            ),
            count: &taps
        )

        XCTAssertEqual(taps, 3)
        waitForDisappearance(identified("nutrition.quick-add.root", in: app))
        waitForValue(
            of: require(
                identified("nutrition.day.total", in: app),
                "The destination day must reconcile its total."
            ),
            containing: "570"
        )
    }

    func testFailureRollsBackThenRetryKeepsSelectionAndUsesTheSameIntent() {
        let app = launch(
            scenario: .errorOnce,
            appearance: .light,
            storeIdentifier: UUID(),
            opensNutrition: true
        )
        let total = require(
            identified("nutrition.day.total", in: app),
            "The failure fixture must expose its baseline total."
        )
        let baseline = total.value as? String

        let categoryAdd = identified("nutrition.day.section.breakfast.add", in: app)
        makeHittable(categoryAdd, in: app)
        categoryAdd.tap()
        firstRecipe(in: app).tap()
        identified("nutrition.quick-add.confirm", in: app).tap()

        let error = require(
            identified("nutrition.quick-add.error", in: app),
            "A failed optimistic insert needs an accessible retry state."
        )
        XCTAssertFalse(error.label.isEmpty)
        XCTAssertEqual(total.value as? String, baseline)
        XCTAssertTrue(identified("nutrition.quick-add.selection", in: app).exists)
        attachScreenshot(named: "nutrition-quick-add-error-light")

        let retry = require(
            identified("nutrition.quick-add.retry", in: app),
            "Retry must preserve and resubmit the same user intent."
        )
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        waitForDisappearance(identified("nutrition.quick-add.root", in: app))
        waitForValue(of: total, containing: "570")
    }

    func testDarkAX5AndVoiceOverSemanticsRemainReadable() {
        let dark = launch(
            scenario: .quickAdd,
            appearance: .dark,
            storeIdentifier: nil,
            opensNutrition: true
        )
        let darkAdd = identified("nutrition.day.section.breakfast.add", in: dark)
        makeHittable(darkAdd, in: dark)
        darkAdd.tap()
        firstRecipe(in: dark).tap()
        require(
            identified("nutrition.quick-add.confirm", in: dark),
            "Dark appearance must retain the confirmation action."
        )
        attachScreenshot(named: "nutrition-quick-add-dark")
        dark.terminate()

        let ax5 = launch(
            scenario: .quickAdd,
            appearance: .light,
            storeIdentifier: nil,
            opensNutrition: true,
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        let ax5Add = identified("nutrition.day.section.breakfast.add", in: ax5)
        makeHittable(ax5Add, in: ax5)
        ax5Add.tap()
        let recipe = firstRecipe(in: ax5)
        makeHittable(recipe, in: ax5)
        XCTAssertTrue(recipe.isHittable)
        XCTAssertFalse(recipe.label.isEmpty)
        XCTAssertFalse((recipe.value as? String)?.isEmpty ?? true)
        XCTAssertGreaterThanOrEqual(
            recipe.frame.minX + 0.5,
            ax5.frame.minX,
            "AX5 recipe rows must not clip past the leading viewport edge. "
                + "App frame: \(ax5.frame); recipe frame: \(recipe.frame)."
        )
        XCTAssertLessThanOrEqual(
            recipe.frame.maxX - 0.5,
            ax5.frame.maxX,
            "AX5 recipe rows must not clip past the trailing viewport edge. "
                + "App frame: \(ax5.frame); recipe frame: \(recipe.frame)."
        )
        attachScreenshot(named: "nutrition-quick-add-ax5")
    }

    @discardableResult
    private func launch(
        scenario: Scenario,
        appearance: Appearance,
        storeIdentifier: UUID?,
        opensNutrition: Bool,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", scenario.rawValue,
            "-ui-test-appearance", appearance.rawValue,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + (storeIdentifier.map {
            ["-ui-test-store-identifier", $0.uuidString]
        } ?? []) + extraArguments
        app.launch()

        if opensNutrition {
            require(
                identified("tab.nutrition", in: app),
                "The shell must expose Nutrition."
            ).tap()
            require(
                identified("nutrition.day.loaded", in: app),
                "The quick-add fixture must load its selected local day."
            )
        }
        return app
    }

    private func firstRecipe(in app: XCUIApplication) -> XCUIElement {
        let query = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "nutrition.quick-add.recipe."
            )
        )
        return require(
            query.firstMatch,
            "The inferred category must expose at least one active recipe."
        )
    }

    private func tapAndCount(_ element: XCUIElement, count: inout Int) {
        XCTAssertTrue(element.isHittable)
        element.tap()
        count += 1
    }

    private func identified(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String,
        timeout: TimeInterval = 10,
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

    private func waitForDisappearance(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10),
            .completed,
            file: file,
            line: line
        )
    }

    private func waitForValue(
        of element: XCUIElement,
        containing fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(
            format: "value CONTAINS[c] %@",
            fragment
        )
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10),
            .completed,
            file: file,
            line: line
        )
    }

    private func makeHittable(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) {
        for _ in 0..<12 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
