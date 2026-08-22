import Foundation
import XCTest

final class M2AcceptanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRecipeCreateThreeTapSnapshotArchiveRestoreAndRelaunch() {
        let storeIdentifier = UUID()
        let recipeName = "M2 kabul kasesi"
        let app = launch(storeIdentifier: storeIdentifier)
        openNutrition(in: app)

        openRecipeLibrary(in: app)
        require(app.buttons["nutrition.recipe.add"]).tap()
        require(identified("nutrition.recipe.editor", in: app))
        enterRecipe(
            name: recipeName,
            calories: "310",
            protein: "26",
            carbs: "38",
            fat: "9",
            in: app
        )
        require(app.buttons["nutrition.recipe.editor.save"]).tap()
        require(
            firstIdentified(prefix: "nutrition.recipe.row.", labelContaining: recipeName, in: app),
            "The real recipe editor must publish the created direct-macro recipe."
        )
        tapNavigationBack(in: app)

        let initialTotal = require(identified("nutrition.day.total", in: app)).value as? String
        let breakfastAdd = require(identified("nutrition.day.section.breakfast.add", in: app))
        makeHittable(breakfastAdd, in: app)
        breakfastAdd.tap()
        let quickRecipe = require(
            firstIdentified(
                prefix: "nutrition.quick-add.recipe.",
                suffix: ".add",
                labelContaining: recipeName,
                in: app
            ),
            "Tap two must offer the newly created breakfast recipe."
        )
        makeHittable(quickRecipe, in: app)
        quickRecipe.tap()
        let confirm = require(identified("nutrition.quick-add.confirm", in: app))
        makeHittable(confirm, in: app)
        confirm.tap()

        let savedTotal = require(identified("nutrition.day.total", in: app)).value as? String
        XCTAssertNotEqual(savedTotal, initialTotal)

        openRecipeLibrary(in: app)
        let editableRow = require(
            firstIdentified(prefix: "nutrition.recipe.row.", labelContaining: recipeName, in: app)
        )
        makeHittable(editableRow, in: app)
        editableRow.tap()
        replaceText(
            in: identified("nutrition.recipe.editor.calories", in: app),
            with: "999",
            app: app
        )
        replaceText(
            in: identified("nutrition.recipe.editor.protein", in: app),
            with: "99",
            app: app
        )
        require(app.buttons["nutrition.recipe.editor.save"]).tap()
        require(
            firstIdentified(prefix: "nutrition.recipe.row.", labelContaining: recipeName, in: app)
        )
        tapNavigationBack(in: app)
        reloadSelectedDay(in: app)
        XCTAssertEqual(identified("nutrition.day.total", in: app).value as? String, savedTotal)

        openRecipeLibrary(in: app)
        let archiveRow = require(
            firstIdentified(prefix: "nutrition.recipe.row.", labelContaining: recipeName, in: app)
        )
        makeHittable(archiveRow, in: app)
        archiveRow.swipeLeft()
        let archive = require(
            firstIdentified(prefix: "nutrition.recipe.archive.", in: app),
            "A referenced recipe must expose an explicit archive action."
        )
        archive.tap()
        let restore = require(
            firstIdentified(prefix: "nutrition.recipe.restore.", in: app),
            "The archived recipe must remain restorable."
        )
        makeHittable(restore, in: app)
        restore.tap()
        require(
            firstIdentified(prefix: "nutrition.recipe.row.", labelContaining: recipeName, in: app)
        )
        tapNavigationBack(in: app)
        reloadSelectedDay(in: app)
        XCTAssertEqual(identified("nutrition.day.total", in: app).value as? String, savedTotal)
        let historicalRecipe = require(
            firstIdentified(prefix: "nutrition.day.entry.", labelContaining: recipeName, in: app)
        )
        makeHittable(historicalRecipe, in: app)
        attachScreenshot(named: "m2-acceptance-recipe-history")
        app.terminate()

        let relaunched = launch(storeIdentifier: storeIdentifier)
        openNutrition(in: relaunched)
        XCTAssertEqual(
            require(identified("nutrition.day.total", in: relaunched)).value as? String,
            savedTotal,
            "Recipe edits and archive/restore must not rewrite a historical entry snapshot."
        )
        require(
            firstIdentified(prefix: "nutrition.day.entry.", labelContaining: recipeName, in: relaunched)
        )
    }

    func testFoodAndAdhocSourcesKeepHistoricalTotalsAfterFoodDeletionAndRelaunch() {
        let storeIdentifier = UUID()
        let foodName = "M2 kabul yoğurdu"
        let adhocName = "M2 serbest tabak"
        let app = launch(storeIdentifier: storeIdentifier)
        openNutrition(in: app)

        openFoodLibrary(in: app)
        require(app.buttons["nutrition.food.add"]).tap()
        enterFood(
            name: foodName,
            calories: "180",
            protein: "18",
            carbs: "12",
            fat: "6",
            in: app
        )
        require(app.buttons["nutrition.food.editor.save"]).tap()
        require(firstIdentified(prefix: "nutrition.food.row.", labelContaining: foodName, in: app))
        tapNavigationBack(in: app)

        let initialTotal = require(identified("nutrition.day.total", in: app)).value as? String
        openBreakfastQuickAdd(in: app)
        let manualFood = app.buttons["nutrition.quick-add.manual.food"]
        makeHittable(manualFood, in: app)
        manualFood.tap()
        let foodSelection = require(
            firstIdentified(
                prefix: "nutrition.manual.food.",
                suffix: ".select",
                labelContaining: foodName,
                in: app
            )
        )
        makeHittable(foodSelection, in: app)
        foodSelection.tap()
        let foodConfirm = require(identified("nutrition.manual.confirm", in: app))
        makeHittable(foodConfirm, in: app)
        foodConfirm.tap()
        require(firstIdentified(prefix: "nutrition.day.entry.", labelContaining: foodName, in: app))
        let foodTotal = require(identified("nutrition.day.total", in: app)).value as? String
        XCTAssertNotEqual(foodTotal, initialTotal)

        openBreakfastQuickAdd(in: app)
        let manualAdhoc = app.buttons["nutrition.quick-add.manual.adhoc"]
        makeHittable(manualAdhoc, in: app)
        manualAdhoc.tap()
        replaceText(
            in: identified("nutrition.manual.adhoc.name", in: app),
            with: adhocName,
            app: app
        )
        replaceText(
            in: identified("nutrition.manual.adhoc.quantity", in: app),
            with: "2",
            app: app
        )
        replaceText(
            in: identified("nutrition.manual.adhoc.calories", in: app),
            with: "220",
            app: app
        )
        replaceText(
            in: identified("nutrition.manual.adhoc.protein", in: app),
            with: "22",
            app: app
        )
        replaceText(
            in: identified("nutrition.manual.adhoc.carbs", in: app),
            with: "20",
            app: app
        )
        replaceText(
            in: identified("nutrition.manual.adhoc.fat", in: app),
            with: "8",
            app: app
        )
        let adhocSave = require(identified("nutrition.manual.adhoc.save", in: app))
        makeHittable(adhocSave, in: app)
        adhocSave.tap()
        require(firstIdentified(prefix: "nutrition.day.entry.", labelContaining: adhocName, in: app))
        let mixedTotal = require(identified("nutrition.day.total", in: app)).value as? String
        XCTAssertNotEqual(mixedTotal, foodTotal)

        openFoodLibrary(in: app)
        let editableFood = require(
            firstIdentified(prefix: "nutrition.food.row.", labelContaining: foodName, in: app)
        )
        makeHittable(editableFood, in: app)
        editableFood.tap()
        replaceText(
            in: identified("nutrition.food.editor.calories", in: app),
            with: "999",
            app: app
        )
        replaceText(
            in: identified("nutrition.food.editor.protein", in: app),
            with: "99",
            app: app
        )
        require(app.buttons["nutrition.food.editor.save"]).tap()
        let deletableFood = require(
            firstIdentified(prefix: "nutrition.food.row.", labelContaining: foodName, in: app)
        )
        makeHittable(deletableFood, in: app)
        deletableFood.swipeLeft()
        require(firstIdentified(prefix: "nutrition.food.delete.", in: app)).tap()
        tapNavigationBack(in: app)
        reloadSelectedDay(in: app)

        XCTAssertEqual(identified("nutrition.day.total", in: app).value as? String, mixedTotal)
        let deletedFoodEntry = require(
            firstIdentified(
                prefix: "nutrition.day.entry.",
                labelContaining: "Silinmiş besin",
                in: app
            )
        )
        let adhocEntry = require(
            firstIdentified(prefix: "nutrition.day.entry.", labelContaining: adhocName, in: app)
        )
        makeHittable(deletedFoodEntry, in: app)
        makeHittable(adhocEntry, in: app)
        attachScreenshot(named: "m2-acceptance-mixed-sources")
        app.terminate()

        let relaunched = launch(storeIdentifier: storeIdentifier)
        openNutrition(in: relaunched)
        XCTAssertEqual(identified("nutrition.day.total", in: relaunched).value as? String, mixedTotal)
        require(firstIdentified(prefix: "nutrition.day.entry.", labelContaining: adhocName, in: relaunched))
    }

    private func launch(storeIdentifier: UUID) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m2-acceptance",
            "-ui-test-appearance", "light",
            "-ui-test-store-identifier", storeIdentifier.uuidString,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        return app
    }

    private func openNutrition(in app: XCUIApplication) {
        require(identified("tab.nutrition", in: app)).tap()
        require(identified("root.nutrition", in: app))
        require(identified("nutrition.day.loaded", in: app))
    }

    private func openRecipeLibrary(in app: XCUIApplication) {
        let button = require(app.buttons["nutrition.day.recipe-library"])
        button.tap()
        require(identified("nutrition.recipe.library", in: app))
    }

    private func openFoodLibrary(in app: XCUIApplication) {
        let button = require(app.buttons["nutrition.day.food-library"])
        button.tap()
        require(identified("nutrition.food.library", in: app))
    }

    private func openBreakfastQuickAdd(in app: XCUIApplication) {
        let add = require(identified("nutrition.day.section.breakfast.add", in: app))
        makeHittable(add, in: app)
        add.tap()
        require(identified("nutrition.quick-add.state.selecting", in: app))
    }

    private func enterRecipe(
        name: String,
        calories: String,
        protein: String,
        carbs: String,
        fat: String,
        in app: XCUIApplication
    ) {
        replaceText(
            in: identified("nutrition.recipe.editor.name", in: app),
            with: name,
            app: app
        )
        let category = require(identified("nutrition.recipe.editor.category", in: app))
        category.tap()
        require(app.buttons["Kahvaltı"]).tap()
        replaceText(
            in: identified("nutrition.recipe.editor.servings", in: app),
            with: "1",
            app: app
        )
        replaceText(
            in: identified("nutrition.recipe.editor.calories", in: app),
            with: calories,
            app: app
        )
        replaceText(
            in: identified("nutrition.recipe.editor.protein", in: app),
            with: protein,
            app: app
        )
        replaceText(
            in: identified("nutrition.recipe.editor.carbs", in: app),
            with: carbs,
            app: app
        )
        replaceText(
            in: identified("nutrition.recipe.editor.fat", in: app),
            with: fat,
            app: app
        )
    }

    private func enterFood(
        name: String,
        calories: String,
        protein: String,
        carbs: String,
        fat: String,
        in app: XCUIApplication
    ) {
        replaceText(
            in: identified("nutrition.food.editor.name", in: app),
            with: name,
            app: app
        )
        replaceText(
            in: identified("nutrition.food.editor.serving-size", in: app),
            with: "1",
            app: app
        )
        replaceText(
            in: identified("nutrition.food.editor.serving-unit", in: app),
            with: "porsiyon",
            app: app
        )
        replaceText(
            in: identified("nutrition.food.editor.calories", in: app),
            with: calories,
            app: app
        )
        replaceText(
            in: identified("nutrition.food.editor.protein", in: app),
            with: protein,
            app: app
        )
        replaceText(
            in: identified("nutrition.food.editor.carbs", in: app),
            with: carbs,
            app: app
        )
        replaceText(
            in: identified("nutrition.food.editor.fat", in: app),
            with: fat,
            app: app
        )
    }

    private func reloadSelectedDay(in app: XCUIApplication) {
        let date = require(identified("nutrition.day.date", in: app))
        let initialDate = date.value as? String
        let previous = require(identified("nutrition.day.previous", in: app))
        makeHittable(previous, in: app)
        previous.tap()
        waitForValue(of: date, toDifferFrom: initialDate)
        let next = require(identified("nutrition.day.next", in: app))
        makeHittable(next, in: app)
        next.tap()
        waitForValue(of: date, toEqual: initialDate)
        require(identified("nutrition.day.loaded", in: app))
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

    private func tapNavigationBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        require(back, "The library must remain in the Nutrition navigation stack.").tap()
        require(identified("nutrition.day.loaded", in: app))
    }

    private func replaceText(
        in element: XCUIElement,
        with value: String,
        app: XCUIApplication
    ) {
        makeHittable(element, in: app)
        require(element)
        element.tap()
        let current = (element.value as? String) ?? ""
        if !current.isEmpty {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        element.typeText(value)
        dismissKeyboard(in: app)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let dismiss = app.buttons["nutrition.keyboard.dismiss"]
        if dismiss.waitForExistence(timeout: 2) {
            dismiss.tap()
        }
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<18 {
            if element.exists, element.isHittable { return }
            if element.exists,
               !element.frame.isEmpty,
               element.frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Element must become hittable.")
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func firstIdentified(
        prefix: String,
        suffix: String? = nil,
        labelContaining: String? = nil,
        in app: XCUIApplication
    ) -> XCUIElement {
        var predicates = [NSPredicate(format: "identifier BEGINSWITH %@", prefix)]
        if let suffix {
            predicates.append(NSPredicate(format: "identifier ENDSWITH %@", suffix))
        }
        if let labelContaining {
            predicates.append(NSPredicate(format: "label CONTAINS[c] %@", labelContaining))
        }
        return app.descendants(matching: .any)
            .matching(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
            .firstMatch
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M2 acceptance element is missing.",
        timeout: TimeInterval = 12
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
