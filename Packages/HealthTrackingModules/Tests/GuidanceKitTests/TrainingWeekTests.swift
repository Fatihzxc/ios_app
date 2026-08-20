import Foundation
@testable import GuidanceKit
import XCTest

final class TrainingWeekTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    func testIndexIsOneBasedBeforeAndDuringTheFirstCompletedTrainingWeek() {
        let start = date(2026, 8, 5, 10)
        let completion = date(2026, 8, 7, 18)

        XCTAssertEqual(
            TrainingWeek.resolve(
                .init(programStartDate: start, completedSessionDates: []),
                calendar: calendar
            ),
            .init(trainingWeekIndex: 1, countedWeekStarts: [])
        )
        XCTAssertEqual(
            TrainingWeek.resolve(
                .init(programStartDate: start, completedSessionDates: [completion]),
                calendar: calendar
            ),
            .init(
                trainingWeekIndex: 1,
                countedWeekStarts: [weekStart(containing: completion)]
            )
        )
    }

    func testAWeekAdvancesOnlyAfterACompletionInANewLocalCalendarWeek() {
        let start = date(2026, 8, 5, 10)
        let first = date(2026, 8, 7, 18)
        let sameWeek = date(2026, 8, 9, 9)
        let nextWeek = date(2026, 8, 10, 7)

        XCTAssertEqual(resolve(start: start, completions: [first]).trainingWeekIndex, 1)
        XCTAssertEqual(
            resolve(start: start, completions: [first, sameWeek]).trainingWeekIndex,
            1,
            "Additional sessions in the same local week must not increment the counter."
        )
        XCTAssertEqual(
            resolve(start: start, completions: [nextWeek, sameWeek, first]).trainingWeekIndex,
            2
        )
    }

    func testSkippedCalendarWeeksDoNotCreateUntrainedWeeks() {
        let start = date(2026, 8, 3, 8)
        let weekOne = date(2026, 8, 4, 18)
        let weekFour = date(2026, 8, 25, 18)

        let decision = resolve(start: start, completions: [weekFour, weekOne])

        XCTAssertEqual(decision.trainingWeekIndex, 2)
        XCTAssertEqual(
            decision.countedWeekStarts,
            [weekStart(containing: weekOne), weekStart(containing: weekFour)]
        )
    }

    func testEditingProgramStartDateRecalculatesFromEligibleCompletedHistory() {
        let completions = [
            date(2026, 8, 4, 18),
            date(2026, 8, 11, 18),
            date(2026, 8, 18, 18),
        ]

        XCTAssertEqual(
            resolve(start: date(2026, 8, 3, 8), completions: completions)
                .trainingWeekIndex,
            3
        )
        XCTAssertEqual(
            resolve(start: date(2026, 8, 10, 8), completions: completions)
                .trainingWeekIndex,
            2
        )
    }

    func testLocalWeekBoundaryUsesTheInjectedCalendarAndTimezone() {
        let start = date(2026, 8, 9, 12)
        let sunday = date(2026, 8, 9, 23, 30)
        let monday = date(2026, 8, 10, 0, 30)

        let decision = resolve(start: start, completions: [sunday, monday])

        XCTAssertEqual(decision.trainingWeekIndex, 2)
        XCTAssertNotEqual(
            decision.countedWeekStarts[0],
            decision.countedWeekStarts[1]
        )
    }

    func testPreProgramCompletionsAreIgnoredAndResolutionIsImmutable() {
        let input = TrainingWeek.Input(
            programStartDate: date(2026, 8, 10, 8),
            completedSessionDates: [
                date(2026, 8, 4, 18),
                date(2026, 8, 11, 18),
            ]
        )
        let snapshot = input

        let decision = TrainingWeek.resolve(input, calendar: calendar)

        XCTAssertEqual(decision.trainingWeekIndex, 1)
        XCTAssertEqual(input, snapshot)
        assertEquatableSendable(TrainingWeek.Input.self)
        assertEquatableSendable(TrainingWeek.Decision.self)
    }

    private func resolve(start: Date, completions: [Date]) -> TrainingWeek.Decision {
        TrainingWeek.resolve(
            .init(programStartDate: start, completedSessionDates: completions),
            calendar: calendar
        )
    }

    private func weekStart(containing date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
