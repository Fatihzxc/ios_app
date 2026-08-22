import Foundation
import XCTest

final class NutritionQuickAddUITests: XCTestCase {
    private let recipeID = "00000000-0000-4000-8000-00000000d200"
    private let entryID = "00000000-0000-4000-8000-00000000d201"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCategoryRecipeAndDefaultConfirmAreExactlyThreeTapsAndPersistAfterRelaunch() {
        let storeIdentifier = UUID()
        let app = launch(
            appearance: "light",
            storeIdentifier: storeIdentifier
        )
        openNutrition(in: app)
        let initialTotal = require(identified("nutrition.day.total", in: app)).value as? String
        let categoryAdd = require(
            identified("nutrition.day.section.breakfast.add", in: app),
            "The breakfast section must expose its 52-point quick-add action."
        )
        makeHittable(categoryAdd, in: app)

        XCTContext.runActivity(named: "Tap 1 — breakfast category add") { _ in
            categoryAdd.tap()
        }
        require(
            identified("nutrition.quick-add.state.selecting", in: app),
            "The first tap must open the ranked active-recipe list."
        )
        let recipeAdd = require(
            identified("nutrition.quick-add.recipe.\(recipeID).add", in: app),
            "The deterministic active breakfast recipe must be selectable."
        )
        makeHittable(recipeAdd, in: app)

        XCTContext.runActivity(named: "Tap 2 — frequent recipe") { _ in
            recipeAdd.tap()
        }
        require(
            identified("nutrition.quick-add.state.confirming", in: app),
            "The second tap must retain the selected recipe and show confirmation."
        )
        let quantity = require(identified("nutrition.quick-add.quantity", in: app))
        XCTAssertTrue(
            ["1", "1,0", "1.0"].contains(quantity.value as? String ?? ""),
            "The acceptance path must be prefilled with one serving."
        )
        let confirm = require(identified("nutrition.quick-add.confirm", in: app))
        makeHittable(confirm, in: app)

        XCTContext.runActivity(named: "Tap 3 — confirm default serving") { _ in
            confirm.tap()
        }
        require(
            identified("nutrition.day.entry.\(entryID)", in: app),
            "The third tap must save the real repository-backed entry."
        )
        let updatedTotal = require(identified("nutrition.day.total", in: app)).value as? String
        XCTAssertNotEqual(updatedTotal, initialTotal)
        attachScreenshot(named: "nutrition-quick-add-saved-light")
        app.terminate()

        let relaunched = launch(
            appearance: "light",
            storeIdentifier: storeIdentifier
        )
        openNutrition(in: relaunched)
        require(
            identified("nutrition.day.entry.\(entryID)", in: relaunched),
            "The three-tap entry must survive a new app process on the same local store."
        )
        XCTAssertEqual(
            identified("nutrition.day.total", in: relaunched).value as? String,
            updatedTotal
        )
    }

    func testTodayMealActionOwnsTheTabRouteAndOpensSuggestedLocalTodayIntent() {
        let app = launch(appearance: "light")
        require(
            identified("root.today.content", in: app),
            "Today must publish its training directive before nutrition routing."
        )
        let mealAction = require(
            identified("today.nutrition.action", in: app),
            "Today content must expose the secondary meal action."
        )
        makeHittable(mealAction, in: app)
        mealAction.tap()

        require(
            identified("root.nutrition", in: app),
            "The app-owned action must select the Nutrition tab."
        )
        require(
            identified("nutrition.quick-add.state.selecting", in: app),
            "The same action must open a local-today suggested category intent."
        )
        let category = require(identified("nutrition.quick-add.category", in: app))
        XCTAssertFalse(category.label.isEmpty)
        XCTAssertFalse((category.value as? String)?.isEmpty ?? true)
    }

    func testDarkRecipeSelectionAndAX5ConfirmationHaveCanonicalEvidence() {
        let dark = launch(appearance: "dark")
        openNutrition(in: dark)
        let darkAdd = require(identified("nutrition.day.section.breakfast.add", in: dark))
        makeHittable(darkAdd, in: dark)
        darkAdd.tap()
        require(identified("nutrition.quick-add.state.selecting", in: dark))
        attachScreenshot(named: "nutrition-quick-add-select-dark")
        dark.terminate()

        let ax5 = launch(
            appearance: "light",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        openNutrition(in: ax5)
        let ax5Add = require(identified("nutrition.day.section.breakfast.add", in: ax5))
        makeHittable(ax5Add, in: ax5)
        ax5Add.tap()
        let recipeAdd = require(
            identified("nutrition.quick-add.recipe.\(recipeID).add", in: ax5)
        )
        makeHittable(recipeAdd, in: ax5)
        recipeAdd.tap()
        let confirmation = require(
            identified("nutrition.quick-add.state.confirming", in: ax5)
        )
        XCTAssertTrue(ax5.frame.intersects(confirmation.frame))
        let confirm = require(identified("nutrition.quick-add.confirm", in: ax5))
        makeHittable(confirm, in: ax5)
        XCTAssertTrue(confirm.isHittable)
        XCTAssertGreaterThanOrEqual(confirm.frame.height + 0.01, 52)
        attachScreenshot(named: "nutrition-quick-add-confirm-ax5")
    }

    private func launch(
        appearance: String,
        storeIdentifier: UUID? = nil,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "nutrition-quick-add",
            "-ui-test-appearance", appearance,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + extraArguments
        if let storeIdentifier {
            app.launchArguments += [
                "-ui-test-store-identifier",
                storeIdentifier.uuidString,
            ]
        }
        app.launch()
        return app
    }

    private func openNutrition(in app: XCUIApplication) {
        let tab = require(identified("tab.nutrition", in: app))
        tab.tap()
        require(identified("root.nutrition", in: app))
        require(identified("nutrition.day.loaded", in: app))
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 {
            if element.isHittable { return }
            let frame = element.frame
            let appFrame = app.frame
            if frame.midY > appFrame.midY {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                    .press(
                        forDuration: 0.05,
                        thenDragTo: app.coordinate(
                            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)
                        )
                    )
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
                    .press(
                        forDuration: 0.05,
                        thenDragTo: app.coordinate(
                            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)
                        )
                    )
            }
        }
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required quick-add element is missing.",
        timeout: TimeInterval = 10
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
