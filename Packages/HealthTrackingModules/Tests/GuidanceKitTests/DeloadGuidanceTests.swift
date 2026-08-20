import Foundation
@testable import GuidanceKit
import XCTest

final class DeloadGuidanceTests: XCTestCase {
    private let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    func testScheduledRecommendationOccursOnlyOnWeeksFiveTenFifteenAndMultiplesOfFive() {
        for week in [1, 4, 6, 9, 11, 14, 16] {
            XCTAssertEqual(evaluate(week: week, histories: []), .none)
        }
        for week in [5, 10, 15, 20] {
            XCTAssertEqual(evaluate(week: week, histories: []), .recommended(.scheduled))
        }
    }

    func testTwoNewestSameLoadSessionsWithNoTotalRepIncreaseAreReactive() {
        let older = session(dayOffset: -7, weightKg: 10, reps: [10, 10, 10])
        let newer = session(dayOffset: 0, weightKg: 10, reps: [10, 10, 10])

        XCTAssertEqual(
            evaluate(
                week: 6,
                histories: [.init(exerciseID: exerciseID, sessions: [older, newer])]
            ),
            .recommended(.reactive(exerciseID: exerciseID))
        )
    }

    func testReactiveFalsePositivesAreRejected() {
        let older = session(dayOffset: -7, weightKg: 10, reps: [10, 10, 10])
        let moreReps = session(dayOffset: 0, weightKg: 10, reps: [11, 10, 10])
        let moreLoad = session(dayOffset: 0, weightKg: 12.5, reps: [8, 8, 8])
        let lessLoad = session(dayOffset: 0, weightKg: 7.5, reps: [10, 10, 10])
        let mixedLoad = session(
            dayOffset: 0,
            sets: [set(1, 10, 10), set(2, 12.5, 10)]
        )
        let missingReps = session(
            dayOffset: 0,
            sets: [set(1, 10, 10), set(2, 10, nil)]
        )

        for newer in [moreReps, moreLoad, lessLoad, mixedLoad, missingReps] {
            XCTAssertEqual(
                evaluate(
                    week: 6,
                    histories: [.init(exerciseID: exerciseID, sessions: [newer, older])]
                ),
                .none
            )
        }
        XCTAssertEqual(
            evaluate(
                week: 6,
                histories: [.init(exerciseID: exerciseID, sessions: [older])]
            ),
            .none
        )
    }

    func testWarmupsAndPerceivedRecoveryAreExcludedFromReactiveDecision() {
        let older = session(
            dayOffset: -7,
            perceivedRecovery: 10,
            sets: [
                .init(setIndex: 0, weightKg: nil, reps: nil, isWarmupSet: true),
                set(1, 10, 10),
                set(2, 10, 10),
            ]
        )
        let newerLowRecovery = session(
            dayOffset: 0,
            perceivedRecovery: 1,
            sets: [
                .init(setIndex: 0, weightKg: 100, reps: 1, isWarmupSet: true),
                set(1, 10, 10),
                set(2, 10, 10),
            ]
        )
        let newerNoRecovery = session(
            dayOffset: 0,
            perceivedRecovery: nil,
            sets: newerLowRecovery.sets
        )
        let historyWithRecovery = DeloadGuidance.ExerciseHistory(
            exerciseID: exerciseID,
            sessions: [older, newerLowRecovery]
        )
        let historyWithoutRecovery = DeloadGuidance.ExerciseHistory(
            exerciseID: exerciseID,
            sessions: [older, newerNoRecovery]
        )

        XCTAssertEqual(
            evaluate(week: 6, histories: [historyWithRecovery]),
            evaluate(week: 6, histories: [historyWithoutRecovery])
        )
    }

    func testScheduledReasonPrecedesReactiveAndStoredStatesSuppressOrExposeAsExpected() {
        let stagnant = DeloadGuidance.ExerciseHistory(
            exerciseID: exerciseID,
            sessions: [
                session(dayOffset: 0, weightKg: 10, reps: [10, 10]),
                session(dayOffset: -7, weightKg: 10, reps: [10, 10]),
            ]
        )
        XCTAssertEqual(evaluate(week: 5, histories: [stagnant]), .recommended(.scheduled))
        XCTAssertEqual(
            evaluate(week: 5, status: .skipped, histories: [stagnant]),
            .none
        )
        XCTAssertEqual(
            evaluate(
                week: 5,
                status: .active,
                storedReason: .scheduled,
                histories: [stagnant]
            ),
            .active(.scheduled)
        )
    }

    func testDefaultLoadIsFiftyPercentRoundedToEquipmentIncrement() {
        XCTAssertEqual(
            DeloadGuidance.loadRecommendation(
                lastWeightKg: 20,
                equipmentIncrementKg: 2.5
            ),
            .init(defaultWeightKg: 10, allowedFractionRange: 0.4...0.5)
        )
        XCTAssertEqual(
            DeloadGuidance.loadRecommendation(
                lastWeightKg: 17.5,
                equipmentIncrementKg: 2.5
            ),
            .init(defaultWeightKg: 10, allowedFractionRange: 0.4...0.5)
        )
        XCTAssertNil(
            DeloadGuidance.loadRecommendation(
                lastWeightKg: nil,
                equipmentIncrementKg: 2.5
            )
        )
    }

    func testEveryExplicitActionProducesTheStoredStateMachineValue() {
        let at = date(dayOffset: 0)
        let cases: [(DeloadGuidance.Action, DeloadGuidance.Status)] = [
            (.accepted, .active),
            (.stay, .skipped),
            (.techniqueReview, .skipped),
            (.skipped, .skipped),
        ]

        for (action, expectedStatus) in cases {
            let state = DeloadGuidance.transition(
                reason: .reactive(exerciseID: exerciseID),
                action: action,
                at: at
            )
            XCTAssertEqual(state.status, expectedStatus)
            XCTAssertEqual(state.reason, .reactive(exerciseID: exerciseID))
            XCTAssertEqual(state.deloadUpdatedAt, at)
            XCTAssertEqual(state.lastAction, action)
            XCTAssertEqual(
                state.lastDeloadSkippedAt,
                action == .accepted ? nil : at
            )
        }
    }

    func testActiveAndSkippedRollOverOnlyWhenANewLocalWeekReceivesACompletion() {
        let decisionAt = date(dayOffset: 0)
        let sameWeek = date(dayOffset: 2)
        let nextWeek = date(dayOffset: 7)
        for action in [DeloadGuidance.Action.accepted, .techniqueReview, .skipped] {
            let state = DeloadGuidance.transition(
                reason: .scheduled,
                action: action,
                at: decisionAt
            )
            XCTAssertEqual(
                DeloadGuidance.rollover(state, completedAt: sameWeek, calendar: calendar),
                state
            )
            let rolled = DeloadGuidance.rollover(
                state,
                completedAt: nextWeek,
                calendar: calendar
            )
            XCTAssertEqual(rolled.status, .none)
            XCTAssertNil(rolled.reason)
            XCTAssertEqual(rolled.lastAction, state.lastAction)
            XCTAssertEqual(rolled.lastDeloadSkippedAt, state.lastDeloadSkippedAt)
        }
    }

    func testInputsAreImmutableAndPublicValuesAreEquatableAndSendable() {
        let history = DeloadGuidance.ExerciseHistory(
            exerciseID: exerciseID,
            sessions: [session(dayOffset: 0, weightKg: 10, reps: [8, 8])]
        )
        let input = DeloadGuidance.Input(
            trainingWeekIndex: 6,
            status: .none,
            storedReason: nil,
            histories: [history]
        )
        let snapshot = input
        _ = DeloadGuidance.evaluate(input)
        XCTAssertEqual(input, snapshot)

        assertEquatableSendable(DeloadGuidance.Status.self)
        assertEquatableSendable(DeloadGuidance.Reason.self)
        assertEquatableSendable(DeloadGuidance.Action.self)
        assertEquatableSendable(DeloadGuidance.WorkingSet.self)
        assertEquatableSendable(DeloadGuidance.CompletedSession.self)
        assertEquatableSendable(DeloadGuidance.ExerciseHistory.self)
        assertEquatableSendable(DeloadGuidance.Input.self)
        assertEquatableSendable(DeloadGuidance.Recommendation.self)
        assertEquatableSendable(DeloadGuidance.LoadRecommendation.self)
        assertEquatableSendable(DeloadGuidance.StoredState.self)
    }

    private func evaluate(
        week: Int,
        status: DeloadGuidance.Status = .none,
        storedReason: DeloadGuidance.Reason? = nil,
        histories: [DeloadGuidance.ExerciseHistory]
    ) -> DeloadGuidance.Recommendation {
        DeloadGuidance.evaluate(
            .init(
                trainingWeekIndex: week,
                status: status,
                storedReason: storedReason,
                histories: histories
            )
        )
    }

    private func session(
        dayOffset: Int,
        weightKg: Double,
        reps: [Int],
        perceivedRecovery: Int? = nil
    ) -> DeloadGuidance.CompletedSession {
        session(
            dayOffset: dayOffset,
            perceivedRecovery: perceivedRecovery,
            sets: reps.enumerated().map { offset, reps in
                set(offset + 1, weightKg, reps)
            }
        )
    }

    private func session(
        dayOffset: Int,
        perceivedRecovery: Int? = nil,
        sets: [DeloadGuidance.WorkingSet]
    ) -> DeloadGuidance.CompletedSession {
        .init(
            id: UUID(),
            completedAt: date(dayOffset: dayOffset),
            perceivedRecovery: perceivedRecovery,
            sets: sets
        )
    }

    private func set(
        _ index: Int,
        _ weightKg: Double?,
        _ reps: Int?
    ) -> DeloadGuidance.WorkingSet {
        .init(
            setIndex: index,
            weightKg: weightKg,
            reps: reps,
            isWarmupSet: false
        )
    }

    private func date(dayOffset: Int) -> Date {
        let base = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026,
                month: 8,
                day: 3,
                hour: 18
            )
        )!
        return calendar.date(byAdding: .day, value: dayOffset, to: base)!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
