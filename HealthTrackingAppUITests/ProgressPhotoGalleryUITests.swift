import Foundation
import XCTest

final class ProgressPhotoGalleryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testChronologicalGalleryComparesTwoAvailablePhotosAndExplainsFallbacks() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-photo-gallery",
            "-ui-test-store-identifier", UUID().uuidString,
            "-ui-test-appearance", "light",
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()

        require(app.descendants(matching: .any)["tab.progress"]).tap()
        require(app.descendants(matching: .any)["root.progress"])
        let open = require(app.descendants(matching: .any)["photos.open"])
        makeHittable(open, in: app)
        open.tap()

        require(app.descendants(matching: .any)["photos.gallery.content"])
        require(app.descendants(matching: .any)["photos.gallery.missing"])
        require(app.descendants(matching: .any)["photos.gallery.corrupt"])

        let selectors = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "photos.gallery.select.")
        )
        XCTAssertGreaterThanOrEqual(selectors.count, 3)
        let first = selectors.element(boundBy: 0)
        let second = selectors.element(boundBy: 1)
        let third = selectors.element(boundBy: 2)
        makeHittable(first, in: app)
        first.tap()
        makeHittable(second, in: app)
        second.tap()

        require(app.descendants(matching: .any)["photos.compare.content"])
        require(app.descendants(matching: .any)["photos.compare.before"])
        require(app.descendants(matching: .any)["photos.compare.after"])

        makeHittable(third, in: app)
        third.tap()
        require(app.descendants(matching: .any)["photos.compare.limit"])
        XCTAssertEqual(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "photos.gallery.selected.")
            ).count,
            2
        )
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M3.8 photo gallery element is missing.",
        timeout: TimeInterval = 15
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        return element
    }
}
