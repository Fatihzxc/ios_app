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

        let first = require(
            app.buttons[
                "photos.gallery.select.00000000-0000-0000-0000-000000000201"
            ]
        )
        let second = require(
            app.buttons[
                "photos.gallery.select.00000000-0000-0000-0000-000000000202"
            ]
        )
        let third = require(
            app.buttons[
                "photos.gallery.select.00000000-0000-0000-0000-000000000203"
            ]
        )
        let firstID = first.identifier.replacingOccurrences(
            of: "photos.gallery.select.",
            with: ""
        )
        let thirdID = third.identifier.replacingOccurrences(
            of: "photos.gallery.select.",
            with: ""
        )
        XCTAssertTrue(first.label.contains("Ön"))
        XCTAssertTrue(first.label.contains("1970"))
        XCTAssertFalse(first.label.contains("file:"))
        XCTAssertFalse(first.label.contains("/private/"))
        makeHittable(first, in: app)
        first.tap()
        makeHittable(second, in: app)
        second.tap()

        require(app.descendants(matching: .any)["photos.compare.content"])
        let before = require(app.descendants(matching: .any)["photos.compare.before"])
        let after = require(app.descendants(matching: .any)["photos.compare.after"])
        XCTAssertTrue(before.label.contains("1970"))
        XCTAssertTrue(after.label.contains("1970"))
        XCTAssertTrue(["Ön", "Yan", "Arka"].contains { before.label.contains($0) })
        XCTAssertTrue(["Ön", "Yan", "Arka"].contains { after.label.contains($0) })

        makeHittable(third, in: app)
        third.tap()
        require(app.descendants(matching: .any)["photos.compare.replaced"])
        XCTAssertFalse(
            app.descendants(matching: .any)["photos.gallery.selected.\(firstID)"].exists
        )
        require(
            app.descendants(matching: .any)["photos.gallery.selected.\(thirdID)"]
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "photos.gallery.selected.")
            ).count,
            2
        )

        findByScrolling("photos.gallery.missing", in: app)
        findByScrolling("photos.gallery.corrupt", in: app)
    }

    private func findByScrolling(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)[identifier]
        for _ in 0..<24 {
            if element.exists { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "Missing gallery fallback: \(identifier)")
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
