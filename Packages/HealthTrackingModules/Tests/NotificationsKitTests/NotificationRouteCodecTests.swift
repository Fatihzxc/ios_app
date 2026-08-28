import Foundation
import NotificationsKit
import XCTest

final class NotificationRouteCodecTests: XCTestCase {
    func testCanonicalHealthCheckDetailRouteRoundTrips() throws {
        let id = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000331")
        )
        let route = HealthCheckNotificationRoute.healthCheckDetail(reminderID: id)

        let payload = HealthCheckNotificationRouteCodec.encode(route)

        XCTAssertEqual(payload, [
            "version": "1",
            "route": "health-check-detail",
            "reminderID": "00000000-0000-0000-0000-000000000331",
        ])
        XCTAssertEqual(HealthCheckNotificationRouteCodec.decode(payload), route)
    }

    func testDecoderRejectsMalformedUnknownAndSensitivePayloads() {
        let canonical = [
            "version": "1",
            "route": "health-check-detail",
            "reminderID": "aaaaaaaa-0000-0000-0000-000000000332",
        ]
        let invalidPayloads: [[String: String]] = [
            [:],
            ["version": "1", "route": "health-check-detail", "reminderID": ""],
            ["version": "1", "route": "health-check-detail", "reminderID": "not-a-uuid"],
            ["version": "2", "route": "health-check-detail", "reminderID": canonical["reminderID"]!],
            ["version": "1", "route": "unknown", "reminderID": canonical["reminderID"]!],
            [
                "version": "1",
                "route": "health-check-detail",
                "reminderID": "aaaaaaaa-0000-0000-0000-000000000332".uppercased(),
            ],
            canonical.merging(["name": "HIV pozitif"]) { _, new in new },
            canonical.merging(["result": "HbA1c 13.2"]) { _, new in new },
            canonical.merging(["recurrence": "quarterly"]) { _, new in new },
        ]

        for payload in invalidPayloads {
            XCTAssertNil(HealthCheckNotificationRouteCodec.decode(payload))
        }
    }
}
