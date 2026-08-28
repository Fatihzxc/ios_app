import Foundation
import NotificationsKit
import XCTest

final class NotificationPlanningTests: XCTestCase {
    func testStableIdentityGenericContentAndRouteDoNotDependOnInputOrder() throws {
        let firstID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000311")
        )
        let secondID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000312")
        )
        let firstDueDate = Date(timeIntervalSince1970: 1_804_060_800)
        let secondDueDate = Date(timeIntervalSince1970: 1_806_739_200)
        let first = HealthCheckNotificationDescriptor(
            reminderID: firstID,
            dueDate: firstDueDate,
            isEligible: true
        )
        let second = HealthCheckNotificationDescriptor(
            reminderID: secondID,
            dueDate: secondDueDate,
            isEligible: true
        )
        let planner = HealthCheckNotificationPlanner(
            locale: Locale(identifier: "tr_TR")
        )

        let forward = planner.requests(for: [first, second])
        let reverse = planner.requests(for: [second, first])

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.map(\.identifier), [
            "health-check-detail.v1.00000000-0000-0000-0000-000000000311",
            "health-check-detail.v1.00000000-0000-0000-0000-000000000312",
        ])
        XCTAssertEqual(forward.map(\.title), ["Hatırlatma", "Hatırlatma"])
        XCTAssertEqual(
            forward.map(\.body),
            [
                "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
                "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
            ]
        )
        XCTAssertEqual(forward.map(\.deliveryDate), [firstDueDate, secondDueDate])
        XCTAssertEqual(forward[0].userInfo, [
            "version": "1",
            "route": "health-check-detail",
            "reminderID": firstID.uuidString.lowercased(),
        ])
        XCTAssertEqual(
            HealthCheckNotificationRouteCodec.decode(forward[0].userInfo),
            .healthCheckDetail(reminderID: firstID)
        )

        let englishRequest = try XCTUnwrap(
            HealthCheckNotificationPlanner(
                locale: Locale(identifier: "en_US")
            ).request(for: first)
        )
        XCTAssertEqual(englishRequest.title, "Reminder")
        XCTAssertEqual(
            englishRequest.body,
            "View your scheduled reminder in the app."
        )
    }

    func testDuplicateAndIneligibleDescriptorsProduceAtMostOneStableRequest() throws {
        let id = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000313")
        )
        let oldDate = Date(timeIntervalSince1970: 1_804_060_800)
        let newDate = oldDate.addingTimeInterval(86_400)
        let planner = HealthCheckNotificationPlanner(
            locale: Locale(identifier: "tr_TR")
        )

        let duplicateRequests = planner.requests(for: [
            .init(reminderID: id, dueDate: oldDate, isEligible: true),
            .init(reminderID: id, dueDate: oldDate, isEligible: true),
        ])
        let replacementRequests = planner.requests(for: [
            .init(reminderID: id, dueDate: oldDate, isEligible: true),
            .init(reminderID: id, dueDate: newDate, isEligible: true),
        ])
        let disabledRequests = planner.requests(for: [
            .init(reminderID: id, dueDate: newDate, isEligible: false),
        ])

        XCTAssertEqual(duplicateRequests.count, 1)
        XCTAssertEqual(replacementRequests.count, 1)
        XCTAssertEqual(replacementRequests[0].identifier, duplicateRequests[0].identifier)
        XCTAssertEqual(replacementRequests[0].deliveryDate, newDate)
        XCTAssertTrue(disabledRequests.isEmpty)
    }

    func testRepositoryEdgeDatesReachRequestsExactlyWithoutRecurrenceArithmetic() throws {
        let planner = HealthCheckNotificationPlanner(
            locale: Locale(identifier: "tr_TR")
        )
        let edgeDates = [
            Date(timeIntervalSince1970: 1_772_323_199), // month end
            Date(timeIntervalSince1970: 1_709_251_199), // leap day
            Date(timeIntervalSince1970: 1_794_116_600), // DST edge instant
        ]

        for (index, dueDate) in edgeDates.enumerated() {
            let id = try XCTUnwrap(
                UUID(uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    320 + index
                ))
            )
            let request = try XCTUnwrap(
                planner.request(
                    for: .init(
                        reminderID: id,
                        dueDate: dueDate,
                        isEligible: true
                    )
                )
            )

            XCTAssertEqual(request.deliveryDate, dueDate)
        }
    }

    func testFractionalDueDateRoundsUpToStableSystemSecondWithoutRecurrenceArithmetic() throws {
        let id = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000323")
        )
        let fractionalDueDate = Date(timeIntervalSince1970: 1_804_060_800.125)
        let planner = HealthCheckNotificationPlanner(
            locale: Locale(identifier: "tr_TR")
        )

        let request = try XCTUnwrap(
            planner.request(
                for: .init(
                    reminderID: id,
                    dueDate: fractionalDueDate,
                    isEligible: true
                )
            )
        )

        XCTAssertEqual(
            request.deliveryDate,
            Date(timeIntervalSince1970: 1_804_060_801)
        )
        XCTAssertGreaterThanOrEqual(request.deliveryDate, fractionalDueDate)
    }

    func testRequestSerializationContainsOnlyGenericCopyAndCanonicalRoutePayload() throws {
        let id = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000314")
        )
        let request = try XCTUnwrap(
            HealthCheckNotificationPlanner(
                locale: Locale(identifier: "tr_TR")
            ).request(
                for: .init(
                    reminderID: id,
                    dueDate: Date(timeIntervalSince1970: 1_804_060_800),
                    isEligible: true
                )
            )
        )
        let serializedPayload = try XCTUnwrap(
            String(
                data: JSONSerialization.data(
                    withJSONObject: request.userInfo,
                    options: [.sortedKeys]
                ),
                encoding: .utf8
            )
        )
        let serializedRequest = [
            request.identifier,
            request.title,
            request.body,
            serializedPayload,
        ].joined(separator: "|")
        let adversarialSensitiveValues = [
            "HIV pozitif",
            "HbA1c 13.2",
            "MR sonucu",
            "servikal bulgu",
            "quarterly",
            "2027-03-01 09:30",
        ]

        XCTAssertEqual(Set(request.userInfo.keys), ["version", "route", "reminderID"])
        for sensitiveValue in adversarialSensitiveValues {
            XCTAssertFalse(serializedRequest.localizedCaseInsensitiveContains(sensitiveValue))
        }
    }
}
