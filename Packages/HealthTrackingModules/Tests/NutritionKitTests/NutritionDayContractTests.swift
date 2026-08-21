import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

final class NutritionDayContractTests: XCTestCase {
    func testHoursWithinTheSameLocalDayResolveToOneImmutableKey() throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let morning = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 7,
            calendar: calendar
        )
        let evening = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 23,
            calendar: calendar
        )

        let morningKey = try NutritionDayKey(containing: morning, calendar: calendar)
        let eveningKey = try NutritionDayKey(containing: evening, calendar: calendar)

        XCTAssertEqual(morningKey, eveningKey)
        XCTAssertEqual(morningKey.start, calendar.startOfDay(for: morning))
        XCTAssertTrue(morningKey.contains(morning))
        XCTAssertTrue(morningKey.contains(evening))
        XCTAssertFalse(morningKey.contains(morningKey.end))
        assertEquatableSendable(morningKey)
    }

    func testAdjacentMonthAndYearDaysResolveToDistinctKeys() throws {
        let calendar = makeCalendar(timeZoneID: "UTC")
        let dates = [
            makeDate(year: 2026, month: 8, day: 31, hour: 23, calendar: calendar),
            makeDate(year: 2026, month: 9, day: 1, hour: 0, calendar: calendar),
            makeDate(year: 2026, month: 12, day: 31, hour: 23, calendar: calendar),
            makeDate(year: 2027, month: 1, day: 1, hour: 0, calendar: calendar),
        ]

        let keys = try dates.map { try NutritionDayKey(containing: $0, calendar: calendar) }

        XCTAssertEqual(Set(keys).count, dates.count)
        XCTAssertEqual(keys[0].end, keys[1].start)
        XCTAssertEqual(keys[2].end, keys[3].start)
    }

    func testDSTDaysUseCalendarIntervalsInsteadOfFixedSeconds() throws {
        let calendar = makeCalendar(timeZoneID: "America/New_York")
        let spring = makeDate(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12,
            calendar: calendar
        )
        let autumn = makeDate(
            year: 2026,
            month: 11,
            day: 1,
            hour: 12,
            calendar: calendar
        )

        let springKey = try NutritionDayKey(containing: spring, calendar: calendar)
        let autumnKey = try NutritionDayKey(containing: autumn, calendar: calendar)

        XCTAssertEqual(springKey.end.timeIntervalSince(springKey.start), 23 * 60 * 60)
        XCTAssertEqual(autumnKey.end.timeIntervalSince(autumnKey.start), 25 * 60 * 60)
    }

    func testTheSameInstantUsesTheInjectedTimezoneDeterministically() throws {
        let instant = Date(timeIntervalSince1970: 1_787_333_400)
        let utc = makeCalendar(timeZoneID: "UTC")
        let losAngeles = makeCalendar(timeZoneID: "America/Los_Angeles")

        let utcKey = try NutritionDayKey(containing: instant, calendar: utc)
        let losAngelesKey = try NutritionDayKey(containing: instant, calendar: losAngeles)

        XCTAssertNotEqual(utcKey.start, losAngelesKey.start)
        XCTAssertTrue(utcKey.contains(instant))
        XCTAssertTrue(losAngelesKey.contains(instant))
    }

    func testEntryDaySnapshotDerivesExactDayAndCategoryTotalsFromEntries() throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let date = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 12,
            calendar: calendar
        )
        let day = try NutritionDayKey(containing: date, calendar: calendar)
        let dayID = uuid("00000000-0000-4000-8000-000000000721")
        let firstID = uuid("00000000-0000-4000-8000-000000000722")
        let secondID = uuid("00000000-0000-4000-8000-000000000723")
        let first = try entry(
            id: firstID,
            category: MealCategory(kind: .breakfast),
            value: "0.1",
            dayID: dayID
        )
        let second = try entry(
            id: secondID,
            category: MealCategory(kind: .lunch),
            value: "0.2",
            dayID: dayID
        )
        let log = NutritionDaySnapshot(
            id: dayID,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            day: day,
            mealEntryIDs: [firstID, secondID]
        )

        let snapshot = try NutritionDayEntriesSnapshot(
            day: day,
            log: log,
            entries: [first, second]
        )

        XCTAssertEqual(snapshot.totalMacros, try macros("0.3"))
        XCTAssertEqual(
            try snapshot.totalMacros(for: MealCategory(kind: .breakfast)),
            try macros("0.1")
        )
        XCTAssertEqual(
            try snapshot.totalMacros(for: MealCategory(kind: .dinner)),
            .zero
        )
        assertEquatableSendable(snapshot)
    }

    private func entry(
        id: UUID,
        category: MealCategory,
        value: String,
        dayID: UUID
    ) throws -> MealEntrySnapshot {
        MealEntrySnapshot(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            category: category,
            source: .adhoc(name: "Kase"),
            quantity: 1,
            resolvedMacros: try macros(value),
            loggedAt: Date(timeIntervalSinceReferenceDate: 100),
            nutritionDayID: dayID
        )
    }

    private func macros(_ value: String) throws -> NutritionMacros {
        let value = Decimal(
            string: value,
            locale: Locale(identifier: "en_US_POSIX")
        )!
        return try NutritionMacros(
            calories: value,
            proteinG: value,
            carbG: value,
            fatG: value
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func makeCalendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
