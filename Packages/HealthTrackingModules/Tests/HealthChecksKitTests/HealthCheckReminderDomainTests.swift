import CoreModels
import Foundation
@testable import HealthChecksKit
import XCTest

final class HealthCheckReminderDomainTests: XCTestCase {
    func testInputTrimsNameAndRejectsBlankName() throws {
        let dueDate = Date(timeIntervalSinceReferenceDate: 10_000)
        let input = try HealthCheckReminderInput(
            name: "  Ferritin  ",
            dueDate: dueDate,
            recurrence: .monthly
        )

        XCTAssertEqual(input.name, "Ferritin")
        XCTAssertEqual(input.dueDate, dueDate)
        XCTAssertEqual(input.recurrence, .monthly)
        XCTAssertThrowsError(
            try HealthCheckReminderInput(
                name: " \n ",
                dueDate: dueDate,
                recurrence: .none
            )
        ) { error in
            XCTAssertEqual(error as? HealthCheckReminderInputError, .missingName)
        }
    }

    func testDueStateIsDerivedFromStatusAndInjectedLocalCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 27, hour: 8)
        )!
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        XCTAssertEqual(
            snapshot(dueDate: startOfToday, status: .pending)
                .dueState(at: now, calendar: calendar),
            .due
        )
        XCTAssertEqual(
            snapshot(dueDate: tomorrow, status: .pending)
                .dueState(at: now, calendar: calendar),
            .pending
        )
        XCTAssertEqual(
            snapshot(dueDate: tomorrow, status: .done)
                .dueState(at: now, calendar: calendar),
            .done
        )
    }

    func testOrderingUsesDueDateThenStableUUID() {
        let sameDate = Date(timeIntervalSinceReferenceDate: 20_000)
        let firstID = UUID(uuidString: "00000000-0000-4000-8000-000000000501")!
        let secondID = UUID(uuidString: "00000000-0000-4000-8000-000000000502")!
        let earlierID = UUID(uuidString: "00000000-0000-4000-8000-000000000503")!
        let values = [
            snapshot(id: secondID, dueDate: sameDate),
            snapshot(id: firstID, dueDate: sameDate),
            snapshot(id: earlierID, dueDate: sameDate.addingTimeInterval(-1)),
        ]

        XCTAssertEqual(
            values.sorted(by: HealthCheckReminderOrdering.dueFirst).map(\.id),
            [earlierID, firstID, secondID]
        )
    }

    private func snapshot(
        id: UUID = UUID(),
        dueDate: Date,
        status: HealthCheckStatus = .pending
    ) -> HealthCheckReminderSnapshot {
        HealthCheckReminderSnapshot(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 2_000),
            name: "Kontrol",
            dueDate: dueDate,
            recurrence: .none,
            status: status
        )
    }
}
