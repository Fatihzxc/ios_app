import Foundation
@testable import GuidanceKit
import XCTest

final class TodayDirectiveTests: XCTestCase {
    private let dayA = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!
    private let dayB = UUID(uuidString: "00000000-0000-4000-8000-000000000202")!
    private let dayC = UUID(uuidString: "00000000-0000-4000-8000-000000000203")!

    func testNoHistoryTrainsFirstTemplateByOrderIndex() {
        let calendar = calendar(timeZoneID: "Europe/Istanbul")
        let now = date(2026, 8, 20, 12, in: calendar)

        XCTAssertEqual(
            TodayDirective.resolve(
                input: input(sessions: [], target: 3),
                now: now,
                calendar: calendar
            ),
            .train(templateID: dayA, reason: .scheduled)
        )
    }

    func testInProgressSessionWinsOverRestTargetAndOverride() {
        let calendar = calendar(timeZoneID: "Europe/Istanbul")
        let now = date(2026, 8, 20, 12, in: calendar)
        let inProgressID = uuid(11)
        let input = TodayDirective.Input(
            templates: templates(),
            sessions: [
                session(id: 10, templateID: dayA, at: now, status: .completed),
                session(id: 11, templateID: dayB, at: now, status: .inProgress)
            ],
            weeklyWorkoutTarget: 1,
            overrideRest: true
        )

        XCTAssertEqual(
            TodayDirective.resolve(input: input, now: now, calendar: calendar),
            .resume(sessionID: inProgressID, templateID: dayB)
        )
    }

    func testSameDayPreviousDayAndWeeklyTargetProduceDistinctRestReasons() {
        let calendar = calendar(timeZoneID: "Europe/Istanbul")
        let now = date(2026, 8, 20, 12, in: calendar)

        XCTAssertEqual(
            TodayDirective.resolve(
                input: input(
                    sessions: [session(id: 1, templateID: dayA, at: now, status: .completed)],
                    target: 3
                ),
                now: now,
                calendar: calendar
            ),
            .rest(reason: .completedToday, nextTemplateID: dayB)
        )

        let previousDay = date(2026, 8, 19, 12, in: calendar)
        XCTAssertEqual(
            TodayDirective.resolve(
                input: input(
                    sessions: [session(id: 2, templateID: dayB, at: previousDay, status: .completed)],
                    target: 3
                ),
                now: now,
                calendar: calendar
            ),
            .rest(reason: .completedPreviousCalendarDay, nextTemplateID: dayC)
        )

        let weekStart = date(2026, 8, 17, 12, in: calendar)
        let midweek = date(2026, 8, 18, 12, in: calendar)
        XCTAssertEqual(
            TodayDirective.resolve(
                input: input(
                    sessions: [
                        session(id: 3, templateID: dayA, at: weekStart, status: .completed),
                        session(id: 4, templateID: dayB, at: midweek, status: .completed)
                    ],
                    target: 2
                ),
                now: now,
                calendar: calendar
            ),
            .rest(reason: .weeklyTargetReached(completed: 2, target: 2), nextTemplateID: dayC)
        )
    }

    func testRestOverrideTrainsThePreservedNextTemplateWithoutMutatingInput() {
        let calendar = calendar(timeZoneID: "Europe/Istanbul")
        let now = date(2026, 8, 20, 12, in: calendar)
        let original = input(
            sessions: [session(id: 1, templateID: dayA, at: now, status: .completed)],
            target: 3,
            overrideRest: true
        )
        let snapshot = original

        XCTAssertEqual(
            TodayDirective.resolve(input: original, now: now, calendar: calendar),
            .train(templateID: dayB, reason: .restOverride(.completedToday))
        )
        XCTAssertEqual(original, snapshot)
    }

    func testInjectedTimeZoneControlsCalendarDayBoundary() {
        let istanbul = calendar(timeZoneID: "Europe/Istanbul")
        let utc = calendar(timeZoneID: "UTC")
        let now = date(2026, 8, 20, 0, minute: 30, in: istanbul)
        let completion = date(2026, 8, 19, 23, minute: 30, in: istanbul)
        let input = input(
            sessions: [session(id: 1, templateID: dayA, at: completion, status: .completed)],
            target: 3
        )

        XCTAssertEqual(
            TodayDirective.resolve(input: input, now: now, calendar: istanbul),
            .rest(reason: .completedPreviousCalendarDay, nextTemplateID: dayB)
        )
        XCTAssertEqual(
            TodayDirective.resolve(input: input, now: now, calendar: utc),
            .rest(reason: .completedToday, nextTemplateID: dayB)
        )
    }

    func testInjectedFirstWeekdayControlsWeeklyTargetBoundary() {
        var mondayStart = calendar(timeZoneID: "UTC")
        mondayStart.firstWeekday = 2
        var sundayStart = calendar(timeZoneID: "UTC")
        sundayStart.firstWeekday = 1
        let now = date(2026, 8, 18, 12, in: mondayStart)
        let sunday = date(2026, 8, 16, 12, in: mondayStart)
        let input = input(
            sessions: [session(id: 1, templateID: dayA, at: sunday, status: .completed)],
            target: 1
        )

        XCTAssertEqual(
            TodayDirective.resolve(input: input, now: now, calendar: mondayStart),
            .train(templateID: dayB, reason: .scheduled)
        )
        XCTAssertEqual(
            TodayDirective.resolve(input: input, now: now, calendar: sundayStart),
            .rest(reason: .weeklyTargetReached(completed: 1, target: 1), nextTemplateID: dayB)
        )
    }

    func testInvalidTemplateSessionAndTargetDataProduceExplicitOutcomes() {
        let calendar = calendar(timeZoneID: "UTC")
        let now = date(2026, 8, 20, 12, in: calendar)
        let unknownTemplateID = uuid(999)

        XCTAssertEqual(
            TodayDirective.resolve(
                input: .init(
                    templates: [], sessions: [], weeklyWorkoutTarget: 3, overrideRest: false
                ),
                now: now,
                calendar: calendar
            ),
            .invalid(.rotation(.missingTemplates))
        )
        XCTAssertEqual(
            TodayDirective.resolve(
                input: input(sessions: [], target: 0),
                now: now,
                calendar: calendar
            ),
            .invalid(.invalidWeeklyWorkoutTarget(0))
        )
        XCTAssertEqual(
            TodayDirective.resolve(
                input: input(
                    sessions: [
                        session(id: 1, templateID: dayA, at: now, status: .inProgress),
                        session(id: 2, templateID: dayB, at: now, status: .inProgress)
                    ],
                    target: 3
                ),
                now: now,
                calendar: calendar
            ),
            .invalid(.multipleInProgressSessions(count: 2))
        )
        XCTAssertEqual(
            TodayDirective.resolve(
                input: input(
                    sessions: [
                        session(id: 3, templateID: unknownTemplateID, at: now, status: .inProgress)
                    ],
                    target: 3
                ),
                now: now,
                calendar: calendar
            ),
            .invalid(.unknownInProgressTemplate(unknownTemplateID))
        )
    }

    func testPublicDirectiveValuesAreEquatableAndSendable() {
        assertEquatableSendable(TodayDirective.Session.self)
        assertEquatableSendable(TodayDirective.Session.Status.self)
        assertEquatableSendable(TodayDirective.Input.self)
        assertEquatableSendable(TodayDirective.RestReason.self)
        assertEquatableSendable(TodayDirective.TrainReason.self)
        assertEquatableSendable(TodayDirective.DataError.self)
        assertEquatableSendable(TodayDirective.Outcome.self)
    }

    private func input(
        sessions: [TodayDirective.Session],
        target: Int,
        overrideRest: Bool = false
    ) -> TodayDirective.Input {
        .init(
            templates: templates(),
            sessions: sessions,
            weeklyWorkoutTarget: target,
            overrideRest: overrideRest
        )
    }

    private func templates() -> [WorkoutRotation.Template] {
        [
            .init(id: dayC, orderIndex: 3),
            .init(id: dayA, orderIndex: 1),
            .init(id: dayB, orderIndex: 2)
        ]
    }

    private func session(
        id: Int,
        templateID: UUID,
        at date: Date,
        status: TodayDirective.Session.Status
    ) -> TodayDirective.Session {
        .init(id: uuid(id), templateID: templateID, date: date, status: status)
    }

    private func calendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        minute: Int = 0,
        in calendar: Calendar
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

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
