import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

final class MealCategorySuggestionTests: XCTestCase {
    func testLocalHourBoundariesUseTheInjectedCalendarAndTimeZone() throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let cases: [(hour: Int, minute: Int, expected: MealCategory.Kind)] = [
            (4, 59, .snack),
            (5, 0, .breakfast),
            (10, 59, .breakfast),
            (11, 0, .lunch),
            (15, 59, .lunch),
            (16, 0, .dinner),
            (21, 59, .dinner),
            (22, 0, .snack),
        ]

        for item in cases {
            let date = try XCTUnwrap(
                calendar.date(
                    from: DateComponents(
                        calendar: calendar,
                        timeZone: calendar.timeZone,
                        year: 2026,
                        month: 8,
                        day: 22,
                        hour: item.hour,
                        minute: item.minute
                    )
                )
            )
            XCTAssertEqual(
                try MealCategorySuggestion.category(at: date, calendar: calendar).kind,
                item.expected,
                "Unexpected category at \(item.hour):\(item.minute)."
            )
        }
    }

    func testSameInstantUsesTheInjectedLocalHourInsteadOfTheProcessTimeZone() throws {
        let instant = Date(timeIntervalSince1970: 1_787_357_400)
        let istanbul = makeCalendar(timeZoneID: "Europe/Istanbul")
        let losAngeles = makeCalendar(timeZoneID: "America/Los_Angeles")

        let istanbulHour = istanbul.component(.hour, from: instant)
        let losAngelesHour = losAngeles.component(.hour, from: instant)
        XCTAssertNotEqual(istanbulHour, losAngelesHour)
        XCTAssertEqual(
            try MealCategorySuggestion.category(at: instant, calendar: istanbul).kind,
            expectedKind(hour: istanbulHour)
        )
        XCTAssertEqual(
            try MealCategorySuggestion.category(at: instant, calendar: losAngeles).kind,
            expectedKind(hour: losAngelesHour)
        )
    }

    private func expectedKind(hour: Int) -> MealCategory.Kind {
        switch hour {
        case 5...10: .breakfast
        case 11...15: .lunch
        case 16...21: .dinner
        default: .snack
        }
    }

    private func makeCalendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }
}
