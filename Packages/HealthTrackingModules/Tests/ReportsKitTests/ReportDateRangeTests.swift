@testable import ReportsKit
import Foundation
import XCTest

final class ReportDateRangeTests: XCTestCase {
    func testEndExclusiveIsTheNextLocalDayAfterShortLongAndStableOffsetDays() throws {
        let fixtures: [(timeZone: String, reference: String, expectedEnd: String)] = [
            // Istanbul's historical spring-forward day is 23 hours long.
            ("Europe/Istanbul", "2015-03-29T09:00:00Z", "2015-03-29T21:00:00Z"),
            // Los Angeles spring-forward day is 23 hours long.
            ("America/Los_Angeles", "2024-03-10T19:00:00Z", "2024-03-11T07:00:00Z"),
            // Los Angeles fall-back day is 25 hours long.
            ("America/Los_Angeles", "2024-11-03T20:00:00Z", "2024-11-04T08:00:00Z"),
            // Istanbul remains UTC+3 while nearby European zones change offset.
            ("Europe/Istanbul", "2024-10-27T09:00:00Z", "2024-10-27T21:00:00Z"),
        ]

        for fixture in fixtures {
            let interval = try ReportDateRangeResolver.resolve(
                .oneMonth,
                referenceDate: try date(fixture.reference),
                calendar: try calendar(timeZoneIdentifier: fixture.timeZone)
            )

            XCTAssertEqual(
                interval.endExclusive,
                try date(fixture.expectedEnd),
                "End must be the next local midnight in \(fixture.timeZone)"
            )
        }
    }

    func testEveryPresetUsesCalendarBoundariesInIstanbul() throws {
        let calendar = try calendar(timeZoneIdentifier: "Europe/Istanbul")
        let referenceDate = try date("2024-03-31T09:00:00Z") // 12:00 in Istanbul.
        let expectedEnd = try date("2024-03-31T21:00:00Z") // 2024-04-01 00:00 in Istanbul.
        let fixtures: [(preset: ReportDateRangePreset, expectedStart: String)] = [
            (.oneMonth, "2024-02-29T21:00:00Z"), // 2024-03-01 local.
            (.threeMonths, "2023-12-31T21:00:00Z"), // 2024-01-01 local.
            (.sixMonths, "2023-09-30T21:00:00Z"), // 2023-10-01 local.
            (.oneYear, "2023-03-31T21:00:00Z"), // 2023-04-01 local.
        ]
        XCTAssertEqual(fixtures.map(\.preset), ReportDateRangePreset.allCases)

        for fixture in fixtures {
            let interval = try ReportDateRangeResolver.resolve(
                fixture.preset,
                referenceDate: referenceDate,
                calendar: calendar
            )

            XCTAssertEqual(interval.start, try date(fixture.expectedStart), "Wrong start for \(fixture.preset)")
            XCTAssertEqual(interval.endExclusive, expectedEnd, "Wrong end for \(fixture.preset)")
        }
    }

    func testEveryPresetUsesCalendarBoundariesAcrossLosAngelesSpringDST() throws {
        let calendar = try calendar(timeZoneIdentifier: "America/Los_Angeles")
        let referenceDate = try date("2024-03-10T19:00:00Z") // 12:00 after the spring transition.
        let expectedEnd = try date("2024-03-11T07:00:00Z") // 2024-03-11 00:00 PDT.
        let fixtures: [(preset: ReportDateRangePreset, expectedStart: String)] = [
            (.oneMonth, "2024-02-11T08:00:00Z"), // 2024-02-11 00:00 PST.
            (.threeMonths, "2023-12-11T08:00:00Z"),
            (.sixMonths, "2023-09-11T07:00:00Z"), // 2023-09-11 00:00 PDT.
            (.oneYear, "2023-03-11T08:00:00Z"),
        ]
        XCTAssertEqual(fixtures.map(\.preset), ReportDateRangePreset.allCases)

        for fixture in fixtures {
            let interval = try ReportDateRangeResolver.resolve(
                fixture.preset,
                referenceDate: referenceDate,
                calendar: calendar
            )

            XCTAssertEqual(interval.start, try date(fixture.expectedStart), "Wrong start for \(fixture.preset)")
            XCTAssertEqual(interval.endExclusive, expectedEnd, "Wrong end for \(fixture.preset)")
        }
    }

    func testIntervalContainsStartAndLastInstantButExcludesEndExclusive() throws {
        let start = try date("2024-02-11T08:00:00Z")
        let endExclusive = try date("2024-03-11T07:00:00Z")
        let interval = ReportDateInterval(start: start, endExclusive: endExclusive)

        XCTAssertFalse(interval.contains(start.addingTimeInterval(-0.001)))
        XCTAssertTrue(interval.contains(start))
        XCTAssertTrue(interval.contains(endExclusive.addingTimeInterval(-0.001)))
        XCTAssertFalse(interval.contains(endExclusive))
        XCTAssertFalse(interval.contains(endExclusive.addingTimeInterval(0.001)))
    }

    func testEmptyCoverageHasZeroObservationsAndNoInventedBoundaryDates() {
        let observations: [(date: Date, value: Double?)] = []
        let coverage = ReportCoverage(observations: observations)

        XCTAssertEqual(coverage.observedCount, 0)
        XCTAssertNil(coverage.firstObservationAt)
        XCTAssertNil(coverage.lastObservationAt)
    }

    func testCoverageCountsZeroValuedObservationAndExcludesMissingObservation() throws {
        let earliest = try date("2024-02-11T08:00:00Z")
        let middle = try date("2024-03-10T19:00:00Z")
        let latest = try date("2024-11-03T20:00:00Z")
        let observations: [(date: Date, value: Double?)] = [
            (date: middle, value: nil),
            (date: latest, value: 42),
            (date: earliest, value: 0),
        ]

        let coverage = ReportCoverage(observations: observations)

        XCTAssertEqual(coverage.observedCount, 2)
        XCTAssertEqual(coverage.firstObservationAt, earliest)
        XCTAssertEqual(coverage.lastObservationAt, latest)
    }

    private func calendar(timeZoneIdentifier: String) throws -> Calendar {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw FixtureError.invalidTimeZone(timeZoneIdentifier)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw FixtureError.invalidDate(value)
        }
        return date
    }

    private enum FixtureError: Error {
        case invalidDate(String)
        case invalidTimeZone(String)
    }
}
