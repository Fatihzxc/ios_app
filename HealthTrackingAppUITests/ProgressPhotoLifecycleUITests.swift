import Foundation
import XCTest

final class ProgressPhotoLifecycleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLocalImportRelaunchAndIdempotentDeleteWorkWithCloudDisabled() {
        let storeIdentifier = UUID()
        let app = launch(storeIdentifier: storeIdentifier)
        openProgressPhotos(in: app)

        require(identified("photos.local-only.status", in: app))
        require(identified("photos.list.empty", in: app))
        let picker = require(identified("photos.picker", in: app))
        XCTAssertTrue(picker.isEnabled)
        require(identified("photos.import.fixture", in: app)).tap()
        require(identified("photos.list.content", in: app))
        let imported = require(firstIdentified(prefix: "photos.row.", in: app))
        XCTAssertFalse(imported.label.contains("/private/"))
        XCTAssertFalse(imported.label.contains("file:"))
        app.terminate()

        let relaunched = launch(storeIdentifier: storeIdentifier)
        openProgressPhotos(in: relaunched)
        require(identified("photos.list.content", in: relaunched))
        let delete = require(firstIdentified(prefix: "photos.delete.", in: relaunched))
        makeHittable(delete, in: relaunched)
        XCTAssertGreaterThanOrEqual(delete.frame.height + 0.01, 52)
        delete.tap()
        require(identified("photos.delete-confirm", in: relaunched)).tap()
        require(identified("photos.list.empty", in: relaunched))
    }

    private func launch(storeIdentifier: UUID) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-progress-photos",
            "-ui-test-store-identifier", storeIdentifier.uuidString,
            "-ui-test-appearance", "light",
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        return app
    }

    private func openProgressPhotos(in app: XCUIApplication) {
        require(identified("tab.progress", in: app)).tap()
        require(identified("root.progress", in: app))
        let open = require(identified("photos.open", in: app))
        makeHittable(open, in: app)
        open.tap()
        require(identified("photos.lifecycle.content", in: app))
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            if element.exists, element.isHittable { return }
            if element.exists,
               !element.frame.isEmpty,
               element.frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func firstIdentified(
        prefix: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .firstMatch
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M3.7 photo lifecycle element is missing.",
        timeout: TimeInterval = 12
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        return element
    }
}
