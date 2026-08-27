@testable import HealthChecksKit
import XCTest

final class HealthCheckNotificationPermissionGateTests: XCTestCase {
    func testFailureReenablesExplicitPermissionActionAndTerminalResultKeepsItDisabled() {
        var gate = HealthCheckNotificationPermissionGate()

        XCTAssertTrue(gate.beginRequest())
        XCTAssertTrue(gate.isDisabled)
        XCTAssertFalse(gate.beginRequest())

        gate.completeRequest(allowsRetry: true)
        XCTAssertFalse(gate.isDisabled)
        XCTAssertTrue(gate.beginRequest())

        gate.completeRequest(allowsRetry: false)
        XCTAssertTrue(gate.isDisabled)
        XCTAssertFalse(gate.beginRequest())
    }
}
