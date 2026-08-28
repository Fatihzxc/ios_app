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
        attachScreenshot(named: "m3-photo-local-lifecycle-light")
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

    func testSuccessfulImportOffersAccessibleExactUndo() {
        let app = launch(storeIdentifier: UUID())
        openProgressPhotos(in: app)

        require(identified("photos.import.fixture", in: app)).tap()
        require(identified("photos.import.saved", in: app))
        let undo = require(identified("photos.import.undo", in: app))
        makeHittable(undo, in: app)
        XCTAssertGreaterThanOrEqual(undo.frame.height + 0.01, 52)
        undo.tap()

        require(identified("photos.list.empty", in: app))
        XCTAssertFalse(identified("photos.import.undo", in: app).exists)
    }

    func testDeniedAndLimitedBroaderAccessKeepActualSystemPickerOperable() {
        for accessState in ["denied", "limited"] {
            let app = launch(
                storeIdentifier: UUID(),
                broaderPhotoLibraryAccessState: accessState
            )
            openProgressPhotos(in: app)

            let picker = require(identified("photos.picker", in: app))
            makeHittable(picker, in: app)
            XCTAssertTrue(
                picker.isEnabled,
                "The system picker must remain enabled for broader access state \(accessState)."
            )
            XCTAssertEqual(
                picker.value as? String,
                accessState,
                "The shipped picker must consume the exact injected broader-access state."
            )
            XCTAssertTrue(picker.isHittable)
            XCTAssertGreaterThanOrEqual(
                picker.frame.height + 0.01,
                52,
                "The actual system picker must retain its accessible touch target."
            )
            app.terminate()
        }
    }

    private func launch(
        storeIdentifier: UUID,
        broaderPhotoLibraryAccessState: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-progress-photos",
            "-ui-test-store-identifier", storeIdentifier.uuidString,
            "-ui-test-appearance", "light",
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        if let broaderPhotoLibraryAccessState {
            app.launchArguments += [
                "-ui-test-photo-library-access",
                broaderPhotoLibraryAccessState,
            ]
        }
        app.launch()
        return app
    }

    private func openProgressPhotos(in app: XCUIApplication) {
        require(identified("tab.progress", in: app)).tap()
        require(identified("root.progress", in: app))
        let open = require(identified("progress.photos.action", in: app))
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

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
