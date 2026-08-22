import Foundation
import XCTest

final class M2AcceptanceUITests: XCTestCase {
    private let fixtureFoodID = "00000000-0000-4000-8000-00000000d001"
    private let fixtureFoodEntryID = "00000000-0000-4000-8000-00000000d101"
    private let fixtureRecipeID = "00000000-0000-4000-8000-00000000d201"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFoodCreateEditDeleteAndHistoricalSnapshotSurviveRelaunch() {
        let storeIdentifier = UUID()
        let app = launchNutrition(storeIdentifier: storeIdentifier)
        let total = require(
            identified("nutrition.day.total", in: app),
            "The food acceptance fixture must expose its baseline day total."
        )
        XCTAssertTrue((total.value as? String)?.contains("370") == true)

        openLibrary("nutrition.day.food-library", root: "nutrition.food.library", in: app)
        assertFiftyTwoPointTarget("nutrition.food.add", in: app).tap()
        require(
            identified("nutrition.food.editor", in: app),
            "The Food library must present its real editor."
        )
        replace("nutrition.food.field.name", with: "Kabul gıdası", in: app)
        replace("nutrition.food.field.brand", with: "Yerel test", in: app)
        replace("nutrition.food.field.servingSize", with: "1", in: app)
        replace("nutrition.food.field.servingUnit", with: "porsiyon", in: app)
        replace("nutrition.food.field.calories", with: "99", in: app)
        replace("nutrition.food.field.protein", with: "9", in: app)
        replace("nutrition.food.field.carbs", with: "10", in: app)
        replace("nutrition.food.field.fat", with: "3", in: app)
        replace("nutrition.food.field.fiber", with: "2", in: app)
        assertFiftyTwoPointTarget("nutrition.food.editor.save", in: app).tap()

        let createdRow = require(
            row(
                prefix: "nutrition.food.row.",
                labelContaining: "Kabul gıdası",
                in: app
            ),
            "A saved Food must appear in the library."
        )
        let createdIdentifier = createdRow.identifier
        createdRow.tap()
        replace("nutrition.food.field.name", with: "Düzenlenen kabul gıdası", in: app)
        replace("nutrition.food.field.calories", with: "101", in: app)
        assertFiftyTwoPointTarget("nutrition.food.editor.save", in: app).tap()
        require(
            identified(createdIdentifier, in: app),
            "Editing must preserve the Food's stable identity."
        )
        attachScreenshot(named: "m2-acceptance-food-library")

        deleteRow(
            createdIdentifier,
            actionIdentifier: createdIdentifier.replacingOccurrences(
                of: "nutrition.food.row.",
                with: "nutrition.food.delete."
            ),
            in: app
        )

        let fixtureRowIdentifier = "nutrition.food.row.\(fixtureFoodID)"
        require(
            identified(fixtureRowIdentifier, in: app),
            "The referenced fixture Food must remain editable."
        ).tap()
        replace("nutrition.food.field.name", with: "Kaynağı değişen yoğurt", in: app)
        replace("nutrition.food.field.calories", with: "999", in: app)
        replace("nutrition.food.field.protein", with: "99", in: app)
        assertFiftyTwoPointTarget("nutrition.food.editor.save", in: app).tap()
        deleteRow(
            fixtureRowIdentifier,
            actionIdentifier: "nutrition.food.delete.\(fixtureFoodID)",
            in: app
        )

        app.terminate()
        let relaunched = launchNutrition(storeIdentifier: storeIdentifier)
        let persistedTotal = require(
            identified("nutrition.day.total", in: relaunched),
            "Relaunch must recover the immutable Food meal snapshot."
        )
        XCTAssertTrue((persistedTotal.value as? String)?.contains("370") == true)
        let historicalEntry = require(
            identified("nutrition.day.entry.\(fixtureFoodEntryID)", in: relaunched),
            "Deleting the Food source must not delete its historical meal row."
        )
        XCTAssertTrue((historicalEntry.value as? String)?.contains("250") == true)
        attachScreenshot(named: "m2-acceptance-food-snapshot-total")
    }

    func testRecipeCreateEditArchiveRestoreAndHistoricalSnapshotSurviveRelaunch() {
        let storeIdentifier = UUID()
        let app = launchNutrition(storeIdentifier: storeIdentifier)
        let total = require(
            identified("nutrition.day.total", in: app),
            "The recipe acceptance fixture must expose its baseline day total."
        )
        XCTAssertTrue((total.value as? String)?.contains("370") == true)

        var taps = 0
        let addBreakfast = identified("nutrition.day.section.breakfast.add", in: app)
        makeHittable(addBreakfast, in: app)
        tapAndCount(addBreakfast, count: &taps)
        tapAndCount(
            require(
                identified("nutrition.quick-add.recipe.\(fixtureRecipeID)", in: app),
                "The deterministic breakfast recipe must be the second tap."
            ),
            count: &taps
        )
        tapAndCount(
            require(
                identified("nutrition.quick-add.confirm", in: app),
                "The default one-serving confirmation must be the third tap."
            ),
            count: &taps
        )
        XCTAssertEqual(taps, 3)
        waitForValue(of: total, containing: "570")

        openLibrary("nutrition.day.recipe-library", root: "nutrition.recipe.library", in: app)
        assertFiftyTwoPointTarget("nutrition.recipe.add", in: app).tap()
        require(
            identified("nutrition.recipe.editor", in: app),
            "The Recipe library must present its direct-macro editor."
        )
        replace("nutrition.recipe.field.name", with: "Kabul tarifi", in: app)
        replace("nutrition.recipe.field.servings", with: "2", in: app)
        replace("nutrition.recipe.field.calories", with: "400", in: app)
        replace("nutrition.recipe.field.protein", with: "30", in: app)
        replace("nutrition.recipe.field.carbs", with: "40", in: app)
        replace("nutrition.recipe.field.fat", with: "12", in: app)
        replace("nutrition.recipe.field.note", with: "Doğrudan makro", in: app)
        assertFiftyTwoPointTarget("nutrition.recipe.editor.save", in: app).tap()

        let createdRow = require(
            row(
                prefix: "nutrition.recipe.row.",
                labelContaining: "Kabul tarifi",
                in: app
            ),
            "A saved direct-macro Recipe must appear in the library."
        )
        let createdIdentifier = createdRow.identifier
        createdRow.tap()
        replace("nutrition.recipe.field.name", with: "Düzenlenen kabul tarifi", in: app)
        replace("nutrition.recipe.field.calories", with: "420", in: app)
        assertFiftyTwoPointTarget("nutrition.recipe.editor.save", in: app).tap()
        deleteRow(
            createdIdentifier,
            actionIdentifier: createdIdentifier.replacingOccurrences(
                of: "nutrition.recipe.row.",
                with: "nutrition.recipe.remove."
            ),
            in: app
        )

        let fixtureRowIdentifier = "nutrition.recipe.row.\(fixtureRecipeID)"
        require(
            identified(fixtureRowIdentifier, in: app),
            "The referenced fixture Recipe must remain editable."
        ).tap()
        replace("nutrition.recipe.field.name", with: "Kaynağı değişen kahvaltı", in: app)
        replace("nutrition.recipe.field.calories", with: "999", in: app)
        replace("nutrition.recipe.field.protein", with: "99", in: app)
        assertFiftyTwoPointTarget("nutrition.recipe.editor.save", in: app).tap()
        deleteRow(
            fixtureRowIdentifier,
            actionIdentifier: "nutrition.recipe.remove.\(fixtureRecipeID)",
            waitsForDisappearance: false,
            in: app
        )
        require(
            identified("nutrition.recipe.archived.\(fixtureRecipeID)", in: app),
            "A referenced Recipe must be archived instead of hard-deleted."
        )
        assertFiftyTwoPointTarget(
            "nutrition.recipe.restore.\(fixtureRecipeID)",
            in: app
        )
        attachScreenshot(named: "m2-acceptance-recipe-archived")

        app.terminate()
        let relaunched = launchNutrition(storeIdentifier: storeIdentifier)
        let persistedTotal = require(
            identified("nutrition.day.total", in: relaunched),
            "Relaunch must recover the immutable Recipe meal snapshot."
        )
        XCTAssertTrue((persistedTotal.value as? String)?.contains("570") == true)
        attachScreenshot(named: "m2-acceptance-recipe-snapshot-total")

        openLibrary(
            "nutrition.day.recipe-library",
            root: "nutrition.recipe.library",
            in: relaunched
        )
        assertFiftyTwoPointTarget(
            "nutrition.recipe.restore.\(fixtureRecipeID)",
            in: relaunched
        ).tap()
        require(
            identified(fixtureRowIdentifier, in: relaunched),
            "Restore must return the archived Recipe to the active section."
        )
        XCTAssertFalse(
            identified("nutrition.recipe.archived.\(fixtureRecipeID)", in: relaunched).exists
        )
        attachScreenshot(named: "m2-acceptance-recipe-restored")
    }

    private func launchNutrition(storeIdentifier: UUID) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "nutrition-quick-add",
            "-ui-test-appearance", "light",
            "-ui-test-store-identifier", storeIdentifier.uuidString,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        require(
            identified("tab.nutrition", in: app),
            "The app shell must expose Nutrition."
        ).tap()
        require(
            identified("nutrition.day.loaded", in: app),
            "The deterministic M2 fixture must load its local day."
        )
        return app
    }

    private func openLibrary(
        _ actionIdentifier: String,
        root: String,
        in app: XCUIApplication
    ) {
        let action = require(
            identified(actionIdentifier, in: app),
            "Missing Nutrition library action \(actionIdentifier)."
        )
        makeHittable(action, in: app)
        action.tap()
        require(
            identified(root, in: app),
            "The library action must navigate to \(root)."
        )
    }

    private func row(
        prefix: String,
        labelContaining fragment: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                    prefix,
                    fragment
                )
            )
            .firstMatch
    }

    private func replace(
        _ identifier: String,
        with value: String,
        in app: XCUIApplication
    ) {
        let field = require(
            identified(identifier, in: app),
            "Missing editor field \(identifier)."
        )
        makeHittable(field, in: app)
        field.tap()
        field.typeText(
            String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64)
        )
        field.typeText(value)
    }

    private func deleteRow(
        _ rowIdentifier: String,
        actionIdentifier: String,
        waitsForDisappearance: Bool = true,
        in app: XCUIApplication
    ) {
        let target = require(
            identified(rowIdentifier, in: app),
            "Missing mutable row \(rowIdentifier)."
        )
        makeHittable(target, in: app)
        target.swipeLeft()
        assertFiftyTwoPointTarget(actionIdentifier, in: app).tap()
        if waitsForDisappearance {
            waitForDisappearance(target)
        }
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
            "Missing action \(identifier).",
            file: file,
            line: line
        )
        makeHittable(element, in: app, file: file, line: line)
        XCTAssertFalse(element.label.isEmpty, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width + 0.01, 52, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + 0.01, 52, file: file, line: line)
        return element
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
