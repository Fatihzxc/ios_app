import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

final class MealCategorySuggestionTests: XCTestCase {
    func testLocalHourBoundariesMapToTheFourStandardCategories() throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let expected: [(hour: Int, kind: MealCategory.Kind)] = [
            (0, .snack),
            (4, .snack),
            (5, .breakfast),
            (10, .breakfast),
            (11, .lunch),
            (15, .lunch),
            (16, .dinner),
            (21, .dinner),
            (22, .snack),
            (23, .snack),
        ]

        for item in expected {
            let date = try XCTUnwrap(
                calendar.date(
                    from: DateComponents(
                        timeZone: calendar.timeZone,
                        year: 2026,
                        month: 8,
                        day: 22,
                        hour: item.hour,
                        minute: 30
                    )
                )
            )

            XCTAssertEqual(
                MealCategorySuggestion.category(at: date, calendar: calendar).kind,
                item.kind,
                "Hour \(item.hour) must be resolved using the injected local calendar."
            )
        }
    }

    func testSameInstantCanSuggestDifferentCategoriesInDifferentTimeZones() throws {
        let instant = Date(timeIntervalSince1970: 1_788_576_000)
        let istanbul = makeCalendar(timeZoneID: "Europe/Istanbul")
        let losAngeles = makeCalendar(timeZoneID: "America/Los_Angeles")

        let istanbulCategory = MealCategorySuggestion.category(
            at: instant,
            calendar: istanbul
        )
        let losAngelesCategory = MealCategorySuggestion.category(
            at: instant,
            calendar: losAngeles
        )

        XCTAssertNotEqual(
            istanbul.component(.hour, from: instant),
            losAngeles.component(.hour, from: instant)
        )
        XCTAssertNotEqual(istanbulCategory, losAngelesCategory)
        assertEquatableSendable(istanbulCategory)
    }

    private func makeCalendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
