import Foundation
import XCTest

final class NutritionAccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAX5LibraryActionsExposeVoiceOverOrderLabelsAndTouchTargets() {
        let app = launch(
            appearance: "light",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        let food = assertFiftyTwoPointTarget("nutrition.day.food-library", in: app)
        let recipe = assertFiftyTwoPointTarget("nutrition.day.recipe-library", in: app)
        XCTAssertFalse(food.label.isEmpty)
        XCTAssertFalse(recipe.label.isEmpty)
        assertReadingOrder(
            ["nutrition.day.food-library", "nutrition.day.recipe-library"],
            in: app
        )

        food.tap()
        require(
            identified("nutrition.food.library", in: app),
            "The Food library must remain reachable at AX5."
        )
        assertFiftyTwoPointTarget("nutrition.food.add", in: app)
        let fixtureRow = require(
            identified(
                "nutrition.food.row.00000000-0000-4000-8000-00000000d001",
                in: app
            ),
            "Food rows need stable, meaningful VoiceOver elements."
        )
        makeHittable(fixtureRow, in: app)
        XCTAssertFalse(fixtureRow.label.isEmpty)
        XCTAssertGreaterThanOrEqual(fixtureRow.frame.height + 0.01, 52)
        XCTAssertGreaterThanOrEqual(fixtureRow.frame.minX + 0.5, app.frame.minX)
        XCTAssertLessThanOrEqual(fixtureRow.frame.maxX - 0.5, app.frame.maxX)
        attachScreenshot(named: "m2-nutrition-voiceover-ax5")
    }

    func testRecipeEditorDarkAX5UsesSemanticErrorAndOperableControls() {
        let app = launch(
            appearance: "dark",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        assertFiftyTwoPointTarget("nutrition.day.recipe-library", in: app).tap()
        require(
            identified("nutrition.recipe.library", in: app),
            "The Recipe library must remain reachable in dark AX5."
        )
        assertFiftyTwoPointTarget("nutrition.recipe.add", in: app).tap()
        require(
            identified("nutrition.recipe.editor", in: app),
            "The direct-macro Recipe editor must be exposed."
        )

        for identifier in [
            "nutrition.recipe.field.name",
            "nutrition.recipe.field.category",
            "nutrition.recipe.field.servings",
            "nutrition.recipe.field.calories",
            "nutrition.recipe.field.protein",
            "nutrition.recipe.field.carbs",
            "nutrition.recipe.field.fat",
            "nutrition.recipe.field.note",
        ] {
            let field = require(
                identified(identifier, in: app),
                "Dark AX5 must keep \(identifier) reachable."
            )
            makeVisible(field, in: app)
            XCTAssertFalse(field.label.isEmpty)
            XCTAssertGreaterThanOrEqual(field.frame.height + 0.01, 52)
            XCTAssertGreaterThanOrEqual(field.frame.minX + 0.5, app.frame.minX)
            XCTAssertLessThanOrEqual(field.frame.maxX - 0.5, app.frame.maxX)
        }

        assertFiftyTwoPointTarget("nutrition.recipe.editor.cancel", in: app)
        let save = assertFiftyTwoPointTarget("nutrition.recipe.editor.save", in: app)
        save.tap()
        let error = require(
            identified("nutrition.recipe.editor.error", in: app),
            "Invalid direct-macro input must publish one semantic error."
        )
        makeVisible(error, in: app)
        XCTAssertFalse(error.label.isEmpty)
        attachScreenshot(named: "m2-recipe-editor-dark-ax5")
    }

    func testQuickAddRemainsOperableWithReduceMotionAndIncreaseContrast() {
        let reduceMotion = launch(
            appearance: "light",
            extraArguments: ["-UIAccessibilityReduceMotionEnabled", "YES"]
        )
        saveBreakfast(in: reduceMotion)
        let total = require(
            identified("nutrition.day.total", in: reduceMotion),
            "Reduce Motion must preserve immediate totals."
        )
        waitForValue(of: total, containing: "570")
        attachScreenshot(named: "m2-nutrition-reduce-motion-total")
        reduceMotion.terminate()

        let highContrast = launch(
            appearance: "dark",
            extraArguments: ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
        )
        let addBreakfast = identified("nutrition.day.section.breakfast.add", in: highContrast)
        makeHittable(addBreakfast, in: highContrast)
        addBreakfast.tap()
        require(
            identified(
                "nutrition.quick-add.recipe.00000000-0000-4000-8000-00000000d201",
                in: highContrast
            ),
            "Increase Contrast must preserve the ranked recipe action."
        ).tap()
        let confirm = assertFiftyTwoPointTarget(
            "nutrition.quick-add.confirm",
            in: highContrast
        )
        XCTAssertFalse(confirm.label.isEmpty)
        attachScreenshot(named: "m2-nutrition-high-contrast")
    }

    private func launch(
        appearance: String,
        extraArguments: [String]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "nutrition-quick-add",
            "-ui-test-appearance", appearance,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + extraArguments
        app.launch()
        require(
            identified("tab.nutrition", in: app),
            "The app shell must expose Nutrition."
        ).tap()
        require(
            identified("nutrition.day.loaded", in: app),
            "The deterministic accessibility fixture must load."
        )
        return app
    }

    private func saveBreakfast(in app: XCUIApplication) {
        let addBreakfast = identified("nutrition.day.section.breakfast.add", in: app)
        makeHittable(addBreakfast, in: app)
        addBreakfast.tap()
        require(
            identified(
                "nutrition.quick-add.recipe.00000000-0000-4000-8000-00000000d201",
                in: app
            ),
            "The breakfast recipe must remain operable."
        ).tap()
        assertFiftyTwoPointTarget("nutrition.quick-add.confirm", in: app).tap()
        waitForDisappearance(identified("nutrition.quick-add.root", in: app))
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
        XCTAssertEqual(positions, positions.sorted())
    }

    @discardableResult
    private func assertFiftyTwoPointTarget(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let element = require(
            identified(identifier, in: app),
            "Missing accessibility action \(identifier).",
            file: file,
            line: line
        )
        makeHittable(element, in: app, file: file, line: line)
        XCTAssertFalse(element.label.isEmpty, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width + 0.01, 52, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + 0.01, 52, file: file, line: line)
        return element
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

    private func waitForValue(
        of element: XCUIElement,
        containing fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS[c] %@", fragment),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10),
            .completed,
            file: file,
            line: line
        )
    }

    private func waitForDisappearance(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10),
            .completed,
            file: file,
            line: line
        )
    }

    private func makeVisible(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            let frame = element.frame
            if frame.minY >= app.frame.minY, frame.maxY <= app.frame.maxY {
                return
            }
            if frame.midY > app.frame.midY {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
        XCTFail("Element did not settle inside the viewport: \(element.identifier).")
    }

    private func makeHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<12 where !element.isHittable {
            if element.frame.midY > app.frame.midY {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
