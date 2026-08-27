import Foundation
import XCTest

final class HealthCheckNotificationFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPermissionRequestOccursOnlyAfterExplicitHealthCheckActionAndNeverOnRelaunch() {
        let storeIdentifier = UUID()
        let app = launch(storeIdentifier: storeIdentifier)

        require(app.descendants(matching: .any)["root.today.content"])
        assertRequestCount("0", in: app)
        acknowledgeFirstUseMedicalExplanation(in: app)
        let healthCheckAction = require(
            app.descendants(matching: .any)["today.health-check.action"]
        )
        makeHittable(healthCheckAction, in: app)
        healthCheckAction.tap()
        require(app.descendants(matching: .any)["health-check.list.loaded"])
        assertRequestCount("0", in: app)

        let explicitPermissionAction = require(
            app.buttons["health-check.notifications.permission"]
        )
        makeHittable(explicitPermissionAction, in: app)
        XCTAssertGreaterThanOrEqual(
            explicitPermissionAction.frame.height + 0.01,
            44,
            "The explicit notification permission action must retain a 44-point target."
        )
        explicitPermissionAction.tap()
        assertRequestCount("1", in: app)
        let disabledExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == false"),
            object: explicitPermissionAction
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [disabledExpectation], timeout: 5),
            .completed,
            "A resolved or in-flight request must reject repeated permission taps."
        )
        app.terminate()

        let relaunched = launch(storeIdentifier: storeIdentifier)
        require(relaunched.descendants(matching: .any)["root.today.content"])
        assertRequestCount("0", in: relaunched)
    }

    private func launch(storeIdentifier: UUID) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-health-checks",
            "-ui-test-appearance", "light",
            "-ui-test-medical-safety-first-use-evidence",
            "-ui-test-store-identifier", storeIdentifier.uuidString,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        return app
    }

    private func acknowledgeFirstUseMedicalExplanation(in app: XCUIApplication) {
        require(app.descendants(matching: .any)["medical.explanation.l0"])
        let acknowledgement = require(
            app.descendants(matching: .any)["medical.explanation.l0.acknowledge"]
        )
        makeHittable(acknowledgement, in: app)
        XCTAssertTrue(
            acknowledgement.isHittable,
            "The fresh notification fixture must expose an operable L0 acknowledgement."
        )
        XCTAssertGreaterThanOrEqual(
            acknowledgement.frame.height + 0.01,
            52,
            "The L0 acknowledgement must retain its 52-point touch target."
        )
        acknowledgement.tap()
        assertRequestCount("0", in: app)
    }

    private func assertRequestCount(_ expected: String, in app: XCUIApplication) {
        let requestCount = require(
            app.descendants(matching: .any)[
                "health-check.notifications.permission.request-count"
            ]
        )
        let labelExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected),
            object: requestCount
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [labelExpectation], timeout: 5),
            .completed,
            "Launch, Today publication, navigation, and relaunch must not auto-prompt."
        )
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        timeout: TimeInterval = 12
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Required M3.11 notification test element is missing."
        )
        return element
    }
}
