import Foundation
@testable import GuidanceKit
import XCTest

final class WeeklyPallofSelectionTests: XCTestCase {
    private let plankPallof = UUID(
        uuidString: "00000000-0000-4000-8000-000000000308"
    )!
    private let sidePlankPallof = UUID(
        uuidString: "00000000-0000-4000-8000-000000000510"
    )!

    func testNoHistoryMakesPallofDueWithoutMutatingInput() {
        let calendar = calendar(firstWeekday: 2)
        let now = date(2026, 8, 20, 12, in: calendar)
        let input = makeInput(completions: [])
        let snapshot = input

        XCTAssertEqual(
            WeeklyPallofSelection.resolve(input: input, now: now, calendar: calendar),
            .suggestion(.init(proposedVariant: .pallof, reason: .pallofDue))
        )
        XCTAssertEqual(input, snapshot)
    }

    func testPallofOnEitherEligibleTemplateSelectsPlankForTheRestOfTheWeek() {
        let calendar = calendar(firstWeekday: 2)
        let now = date(2026, 8, 20, 12, in: calendar)

        for (offset, templateID) in [plankPallof, sidePlankPallof].enumerated() {
            XCTAssertEqual(
                WeeklyPallofSelection.resolve(
                    input: makeInput(
                        completions: [
                            completion(
                                id: offset + 1,
                                templateID: templateID,
                                at: date(2026, 8, 18, 12, in: calendar),
                                variant: .pallof
                            ),
                        ]
                    ),
                    now: now,
                    calendar: calendar
                ),
                .suggestion(
                    .init(proposedVariant: .plank, reason: .pallofCompletedThisWeek)
                )
            )
        }
    }

    func testPriorWeekPallofAndCurrentWeekPlankDoNotSatisfyThisWeek() {
        let calendar = calendar(firstWeekday: 2)
        let now = date(2026, 8, 20, 12, in: calendar)
        let input = makeInput(
            completions: [
                completion(
                    id: 1,
                    templateID: plankPallof,
                    at: date(2026, 8, 16, 12, in: calendar),
                    variant: .pallof
                ),
                completion(
                    id: 2,
                    templateID: sidePlankPallof,
                    at: date(2026, 8, 18, 12, in: calendar),
                    variant: .plank
                ),
            ]
        )

        XCTAssertEqual(
            WeeklyPallofSelection.resolve(input: input, now: now, calendar: calendar),
            .suggestion(.init(proposedVariant: .pallof, reason: .pallofDue))
        )
    }

    func testInjectedWeekBoundaryControlsWhetherSundayPallofCounts() {
        let mondayStart = calendar(firstWeekday: 2)
        let sundayStart = calendar(firstWeekday: 1)
        let now = date(2026, 8, 18, 12, in: mondayStart)
        let sunday = date(2026, 8, 16, 12, in: mondayStart)
        let input = makeInput(
            completions: [
                completion(
                    id: 1,
                    templateID: sidePlankPallof,
                    at: sunday,
                    variant: .pallof
                ),
            ]
        )

        XCTAssertEqual(
            WeeklyPallofSelection.resolve(
                input: input,
                now: now,
                calendar: mondayStart
            ),
            .suggestion(.init(proposedVariant: .pallof, reason: .pallofDue))
        )
        XCTAssertEqual(
            WeeklyPallofSelection.resolve(
                input: input,
                now: now,
                calendar: sundayStart
            ),
            .suggestion(.init(proposedVariant: .plank, reason: .pallofCompletedThisWeek))
        )
    }

    func testUnknownTemplatePallofIsIgnoredAndMissingEligibleTemplatesAreInvalid() {
        let calendar = calendar(firstWeekday: 2)
        let now = date(2026, 8, 20, 12, in: calendar)
        let unknown = UUID(
            uuidString: "00000000-0000-4000-8000-000000000999"
        )!

        XCTAssertEqual(
            WeeklyPallofSelection.resolve(
                input: makeInput(
                    completions: [
                        completion(
                            id: 1,
                            templateID: unknown,
                            at: now,
                            variant: .pallof
                        ),
                    ]
                ),
                now: now,
                calendar: calendar
            ),
            .suggestion(.init(proposedVariant: .pallof, reason: .pallofDue))
        )
        XCTAssertEqual(
            WeeklyPallofSelection.resolve(
                input: .init(eligibleExerciseTemplateIDs: [], completions: []),
                now: now,
                calendar: calendar
            ),
            .invalid(.missingEligibleTemplates)
        )
    }

    func testVariantStorageValuesAndPublicTypesAreStable() {
        XCTAssertEqual(WeeklyPallofSelection.Variant.pallof.rawValue, "pallof")
        XCTAssertEqual(WeeklyPallofSelection.Variant.plank.rawValue, "plank")
        assertEquatableSendable(WeeklyPallofSelection.Variant.self)
        assertEquatableSendable(WeeklyPallofSelection.Completion.self)
        assertEquatableSendable(WeeklyPallofSelection.Input.self)
        assertEquatableSendable(WeeklyPallofSelection.Reason.self)
        assertEquatableSendable(WeeklyPallofSelection.Suggestion.self)
        assertEquatableSendable(WeeklyPallofSelection.DataError.self)
        assertEquatableSendable(WeeklyPallofSelection.Outcome.self)
    }

    private func makeInput(
        completions: [WeeklyPallofSelection.Completion]
    ) -> WeeklyPallofSelection.Input {
        .init(
            eligibleExerciseTemplateIDs: [plankPallof, sidePlankPallof],
            completions: completions
        )
    }

    private func completion(
        id: Int,
        templateID: UUID,
        at date: Date,
        variant: WeeklyPallofSelection.Variant?
    ) -> WeeklyPallofSelection.Completion {
        .init(
            id: UUID(
                uuidString: String(
                    format: "00000000-0000-4000-8000-%012d",
                    id
                )
            )!,
            exerciseTemplateID: templateID,
            completedAt: date,
            performedVariant: variant
        )
    }

    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        in calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
