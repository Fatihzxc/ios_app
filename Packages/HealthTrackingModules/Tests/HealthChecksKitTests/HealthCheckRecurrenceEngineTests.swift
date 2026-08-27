import CoreModels
import Foundation
@testable import HealthChecksKit
import XCTest

final class HealthCheckRecurrenceEngineTests: XCTestCase {
    func testNoneNeverCreatesAnotherDueDate() throws {
        let calendar = calendar(timeZone: "Europe/Istanbul")
        let dueDate = date(2026, 8, 31, 9, 45, calendar: calendar)

        XCTAssertNil(
            try HealthCheckRecurrenceEngine.nextDueDate(
                after: dueDate,
                recurrence: .none,
                calendar: calendar
            )
        )
    }

    func testMonthlyClampsToTargetMonthAndUsesClampedResultAsNextAnchor() throws {
        let calendar = calendar(timeZone: "Europe/Istanbul")
        let january = date(2027, 1, 31, 9, 45, calendar: calendar)

        let february = try XCTUnwrap(
            HealthCheckRecurrenceEngine.nextDueDate(
                after: january,
                recurrence: .monthly,
                calendar: calendar
            )
        )
        assertLocal(february, equals: [2027, 2, 28, 9, 45], calendar: calendar)

        let march = try XCTUnwrap(
            HealthCheckRecurrenceEngine.nextDueDate(
                after: february,
                recurrence: .monthly,
                calendar: calendar
            )
        )
        assertLocal(march, equals: [2027, 3, 28, 9, 45], calendar: calendar)
    }

    func testQuarterlyClampsInvalidDayAndPreservesLocalTime() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let august = date(2026, 8, 31, 18, 20, calendar: calendar)

        let november = try XCTUnwrap(
            HealthCheckRecurrenceEngine.nextDueDate(
                after: august,
                recurrence: .quarterly,
                calendar: calendar
            )
        )
        assertLocal(november, equals: [2026, 11, 30, 18, 20], calendar: calendar)

        let february = try XCTUnwrap(
            HealthCheckRecurrenceEngine.nextDueDate(
                after: november,
                recurrence: .quarterly,
                calendar: calendar
            )
        )
        assertLocal(february, equals: [2027, 2, 28, 18, 20], calendar: calendar)
    }

    func testYearlyLeapDayClampsOnceAndKeepsThatResultAsAnchor() throws {
        let calendar = calendar(timeZone: "Europe/Istanbul")
        let leapDay = date(2024, 2, 29, 7, 5, calendar: calendar)

        let first = try XCTUnwrap(
            HealthCheckRecurrenceEngine.nextDueDate(
                after: leapDay,
                recurrence: .yearly,
                calendar: calendar
            )
        )
        assertLocal(first, equals: [2025, 2, 28, 7, 5], calendar: calendar)

        let second = try XCTUnwrap(
            HealthCheckRecurrenceEngine.nextDueDate(
                after: first,
                recurrence: .yearly,
                calendar: calendar
            )
        )
        assertLocal(second, equals: [2026, 2, 28, 7, 5], calendar: calendar)
    }

    func testLosAngelesDSTChangesOffsetWithoutMovingWallClockTime() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let beforeDST = date(2026, 2, 9, 9, 30, calendar: calendar)

        let afterDST = try XCTUnwrap(
            HealthCheckRecurrenceEngine.nextDueDate(
                after: beforeDST,
                recurrence: .monthly,
                calendar: calendar
            )
        )

        assertLocal(afterDST, equals: [2026, 3, 9, 9, 30], calendar: calendar)
        XCTAssertNotEqual(
            calendar.timeZone.secondsFromGMT(for: beforeDST),
            calendar.timeZone.secondsFromGMT(for: afterDST)
        )
    }

    func testNonGregorianCalendarFailsExplicitlyInsteadOfAssumingTwelveMonths() {
        var nonGregorian = Calendar(identifier: .islamicUmmAlQura)
        nonGregorian.timeZone = TimeZone(identifier: "Europe/Istanbul")!

        XCTAssertThrowsError(
            try HealthCheckRecurrenceEngine.nextDueDate(
                after: Date(timeIntervalSinceReferenceDate: 1_000),
                recurrence: .monthly,
                calendar: nonGregorian
            )
        ) { error in
            XCTAssertEqual(
                error as? HealthCheckRecurrenceEngineError,
                .unsupportedCalendar
            )
        }
    }

    private func calendar(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func assertLocal(
        _ date: Date,
        equals expected: [Int],
        calendar: Calendar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        XCTAssertEqual(
            [
                components.year,
                components.month,
                components.day,
                components.hour,
                components.minute,
            ].compactMap { $0 },
            expected,
            file: file,
            line: line
        )
    }
}
