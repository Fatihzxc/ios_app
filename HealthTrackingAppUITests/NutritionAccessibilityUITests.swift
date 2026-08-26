import Foundation
import XCTest

final class NutritionAccessibilityUITests: XCTestCase {
    private let geometryTolerance: CGFloat = 0.01

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAX5AdhocFieldsRemainReachableOrderedAndFiftyTwoPointsTall() {
        let app = launch(
            appearance: "light",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        openAdhocEntry(in: app)

        let identifiers = [
            "nutrition.manual.adhoc.name",
            "nutrition.manual.adhoc.quantity",
            "nutrition.manual.adhoc.calories",
            "nutrition.manual.adhoc.protein",
            "nutrition.manual.adhoc.carbs",
            "nutrition.manual.adhoc.fat",
            "nutrition.manual.adhoc.save",
        ]
        for identifier in identifiers {
            let element: XCUIElement
            if identifier == "nutrition.manual.adhoc.save" {
                element = app.buttons[identifier]
            } else {
                element = app.textFields[identifier]
            }
            makeHittable(element, in: app)
            require(element)
            XCTAssertTrue(element.isHittable, "AX5 must keep \(identifier) reachable.")
            XCTAssertGreaterThanOrEqual(
                element.frame.height + geometryTolerance,
                52,
                "AX5 control must retain the 52-point interaction minimum: \(identifier)."
            )
            XCTAssertFalse(element.label.isEmpty, "VoiceOver label is required for \(identifier).")
        }
        assertReadingOrder(identifiers, in: app)
        attachScreenshot(named: "m2-nutrition-ax5-adhoc")
    }

    func testDarkHighContrastFoodSelectionRetainsSemanticRowsAndActions() {
        let app = launch(
            appearance: "dark",
            extraArguments: ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
        )
        openNutrition(in: app)
        let add = require(identified("nutrition.day.section.breakfast.add", in: app))
        makeHittable(add, in: app)
        add.tap()
        require(identified("nutrition.quick-add.state.selecting", in: app))
        let manualFood = app.buttons["nutrition.quick-add.manual.food"]
        makeHittable(manualFood, in: app)
        manualFood.tap()
        require(identified("nutrition.manual.state.food-selection", in: app))
        let food = require(firstIdentified(prefix: "nutrition.manual.food.", suffix: ".select", in: app))
        makeHittable(food, in: app)
        XCTAssertTrue(food.isHittable)
        XCTAssertFalse(food.label.isEmpty)
        XCTAssertFalse((food.value as? String)?.isEmpty ?? true)
        attachScreenshot(named: "m2-nutrition-dark-high-contrast-food")
    }

    func testReduceMotionCanCompleteAdhocEntryWithoutTransitionDependency() {
        let app = launch(
            appearance: "light",
            extraArguments: ["-UIAccessibilityReduceMotionEnabled", "YES"]
        )
        openAdhocEntry(in: app)
        replaceText(in: identified("nutrition.manual.adhoc.name", in: app), with: "Hareket azaltılmış öğün", app: app)
        replaceText(in: identified("nutrition.manual.adhoc.quantity", in: app), with: "1", app: app)
        replaceText(in: identified("nutrition.manual.adhoc.calories", in: app), with: "100", app: app)
        replaceText(in: identified("nutrition.manual.adhoc.protein", in: app), with: "10", app: app)
        replaceText(in: identified("nutrition.manual.adhoc.carbs", in: app), with: "8", app: app)
        replaceText(in: identified("nutrition.manual.adhoc.fat", in: app), with: "3", app: app)
        let save = app.buttons["nutrition.manual.adhoc.save"]
        makeHittable(save, in: app)
        save.tap()
        let savedEntry = require(
            firstIdentified(
                prefix: "nutrition.day.entry.",
                labelContaining: "Hareket azaltılmış öğün",
                in: app
            ),
            "Reduce Motion must not gate the repository-backed save completion."
        )
        makeHittable(savedEntry, in: app)
        attachScreenshot(named: "m2-nutrition-reduce-motion")
    }

    private func launch(
        appearance: String,
        extraArguments: [String]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m2-acceptance",
            "-ui-test-appearance", appearance,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + extraArguments
        app.launch()
        return app
    }

    private func openNutrition(in app: XCUIApplication) {
        require(identified("tab.nutrition", in: app)).tap()
        require(identified("root.nutrition", in: app))
        require(identified("nutrition.day.loaded", in: app))
    }

    private func openAdhocEntry(in app: XCUIApplication) {
        openNutrition(in: app)
        let add = require(identified("nutrition.day.section.breakfast.add", in: app))
        makeHittable(add, in: app)
        add.tap()
        require(identified("nutrition.quick-add.state.selecting", in: app))
        let adhoc = app.buttons["nutrition.quick-add.manual.adhoc"]
        makeHittable(adhoc, in: app)
        adhoc.tap()
        require(identified("nutrition.manual.state.adhoc-entry", in: app))
    }

    private func assertReadingOrder(_ identifiers: [String], in app: XCUIApplication) {
        let published = app.descendants(matching: .any).allElementsBoundByIndex.map(\.identifier)
        let positions = identifiers.map { identifier -> Int in
            guard let position = published.firstIndex(of: identifier) else {
                XCTFail("VoiceOver order is missing \(identifier).")
                return Int.max
            }
            return position
        }
        XCTAssertEqual(positions, positions.sorted())
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
        let dismiss = require(
            app.buttons["nutrition.keyboard.dismiss"],
            "Manual entry must expose an explicit keyboard dismissal action."
        )
        dismiss.tap()
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
        _ message: String = "Required nutrition accessibility element is missing.",
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
