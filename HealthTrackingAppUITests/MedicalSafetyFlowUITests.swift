import XCTest

final class MedicalSafetyFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Mutation caught: acknowledging L0 globally, failing to persist it, or using it
    // to suppress L1 would hide essential safety information on a later launch.
    func testFirstUseExplanationPersistsIndependentlyFromPermanentReminderDisclaimer() {
        let storeIdentifier = UUID()
        let firstLaunch = launch(storeIdentifier: storeIdentifier)

        require(
            identified("medical.explanation.l0", in: firstLaunch),
            "The non-medical first-use explanation must be visible before acknowledgement."
        )
        require(identified("medical.explanation.l0.acknowledge", in: firstLaunch)).tap()
        openReminder(in: firstLaunch)
        XCTAssertEqual(
            require(identified("medical.disclaimer.l1", in: firstLaunch)).label,
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
        )
        firstLaunch.terminate()

        let relaunched = launch(storeIdentifier: storeIdentifier)
        XCTAssertFalse(
            identified("medical.explanation.l0", in: relaunched).waitForExistence(timeout: 2),
            "A successfully acknowledged L0 must remain hidden after relaunch."
        )
        openReminder(in: relaunched)
        XCTAssertEqual(
            require(identified("medical.disclaimer.l1", in: relaunched)).label,
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
        )
    }

    private func launch(storeIdentifier: UUID) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-health-checks",
            "-ui-test-appearance", "light",
            "-ui-test-store-identifier", storeIdentifier.uuidString,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        return app
    }

    private func openReminder(in app: XCUIApplication) {
        require(identified("root.today.content", in: app))
        let action = require(identified("today.health-check.action", in: app))
        makeHittable(action, in: app)
        action.tap()
        require(identified("health-check.list.loaded", in: app))
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M3.10 medical-safety element is missing.",
        timeout: TimeInterval = 12
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        return element
    }
}
