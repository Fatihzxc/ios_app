import Foundation
@testable import GuidanceKit
import XCTest

final class DoubleProgressionTests: XCTestCase {
    func testEveryStrictConditionProducesExactLoadIncreaseAndRepReset() {
        let input = makeInput(
            sets: [
                set(index: 1, weightKg: 10, reps: 12, rir: 1),
                set(index: 2, weightKg: 10, reps: 12, rir: 0),
                set(index: 3, weightKg: 10, reps: 12, rir: 1),
            ]
        )
        let snapshot = input

        XCTAssertEqual(
            DoubleProgression.suggest(input),
            .init(
                proposedMeasurement: .init(weightKg: 12.5, reps: 8),
                reason: .increase
            )
        )
        XCTAssertEqual(input, snapshot, "Guidance must never mutate its history input.")
    }

    func testEachMissingConditionReturnsItsSpecificHoldReason() {
        let qualifying = [
            set(index: 1, weightKg: 10, reps: 12, rir: 1),
            set(index: 2, weightKg: 10, reps: 12, rir: 0),
        ]

        XCTAssertEqual(
            DoubleProgression.suggest(
                makeInput(repHigh: nil, sets: qualifying)
            ),
            hold(weightKg: 10, reps: 12, reason: .missingRepCeiling)
        )
        XCTAssertEqual(
            DoubleProgression.suggest(
                makeInput(
                    sets: [
                        qualifying[0],
                        set(index: 2, weightKg: 10, reps: 11, rir: 0),
                    ]
                )
            ),
            hold(weightKg: 10, reps: 12, reason: .repetitionsBelowCeiling)
        )
        XCTAssertEqual(
            DoubleProgression.suggest(
                makeInput(
                    sets: [
                        qualifying[0],
                        set(index: 2, weightKg: 10, reps: 12, rir: nil),
                    ]
                )
            ),
            hold(weightKg: 10, reps: 12, reason: .missingRIR)
        )
        XCTAssertEqual(
            DoubleProgression.suggest(
                makeInput(
                    sets: [
                        qualifying[0],
                        set(index: 2, weightKg: 10, reps: 12, rir: 2),
                    ]
                )
            ),
            hold(weightKg: 10, reps: 12, reason: .rirAboveThreshold)
        )
        XCTAssertEqual(
            DoubleProgression.suggest(
                makeInput(
                    sets: [
                        qualifying[0],
                        set(index: 2, weightKg: nil, reps: 12, rir: 0),
                    ]
                )
            ),
            hold(weightKg: nil, reps: 12, reason: .missingExternalWeight)
        )
    }

    func testMixedWeightsUseTheLastSetIndexWithoutInventingAnEqualityRule() {
        let suggestion = DoubleProgression.suggest(
            makeInput(
                sets: [
                    set(index: 3, weightKg: 12.5, reps: 12, rir: 0),
                    set(index: 1, weightKg: 8, reps: 12, rir: 1),
                    set(index: 2, weightKg: 10, reps: 12, rir: 1),
                ]
            )
        )

        XCTAssertEqual(
            suggestion,
            .init(
                proposedMeasurement: .init(weightKg: 15, reps: 8),
                reason: .increase
            )
        )
    }

    func testWarmupsAreExcludedFromEveryStrictPredicate() {
        let suggestion = DoubleProgression.suggest(
            makeInput(
                sets: [
                    set(
                        index: 0,
                        weightKg: nil,
                        reps: 1,
                        rir: nil,
                        isWarmupSet: true
                    ),
                    set(index: 1, weightKg: 10, reps: 12, rir: 1),
                    set(index: 2, weightKg: 10, reps: 12, rir: 0),
                ]
            )
        )

        XCTAssertEqual(suggestion.reason, .increase)
        XCTAssertEqual(suggestion.proposedMeasurement.weightKg, 12.5)
    }

    func testNilCeilingAndEmptyWorkingSetsNeverIncrease() {
        XCTAssertEqual(
            DoubleProgression.suggest(
                makeInput(
                    repHigh: nil,
                    sets: [set(index: 1, weightKg: 10, reps: 10, rir: 0)]
                )
            ),
            hold(weightKg: 10, reps: 10, reason: .missingRepCeiling)
        )
        XCTAssertEqual(
            DoubleProgression.suggest(
                makeInput(
                    sets: [
                        set(
                            index: 0,
                            weightKg: nil,
                            reps: nil,
                            rir: nil,
                            isWarmupSet: true
                        ),
                    ]
                )
            ),
            hold(weightKg: nil, reps: nil, reason: .noWorkingSets)
        )
    }

    func testZeroWeightIsNotRealExternalLoad() {
        XCTAssertEqual(
            DoubleProgression.suggest(
                makeInput(
                    sets: [set(index: 1, weightKg: 0, reps: 12, rir: 0)]
                )
            ),
            hold(weightKg: nil, reps: 12, reason: .missingExternalWeight)
        )
    }

    func testPublicValuesAreEquatableAndSendable() {
        assertEquatableSendable(DoubleProgression.WorkingSet.self)
        assertEquatableSendable(DoubleProgression.Input.self)
        assertEquatableSendable(DoubleProgression.ProposedMeasurement.self)
        assertEquatableSendable(DoubleProgression.HoldReason.self)
        assertEquatableSendable(DoubleProgression.Reason.self)
        assertEquatableSendable(DoubleProgression.Suggestion.self)
    }

    private func makeInput(
        repHigh: Int? = 12,
        sets: [DoubleProgression.WorkingSet]
    ) -> DoubleProgression.Input {
        .init(repLow: 8, repHigh: repHigh, rirLow: 1, sets: sets)
    }

    private func set(
        index: Int,
        weightKg: Double?,
        reps: Int?,
        rir: Int?,
        isWarmupSet: Bool = false
    ) -> DoubleProgression.WorkingSet {
        .init(
            setIndex: index,
            weightKg: weightKg,
            reps: reps,
            rir: rir,
            isWarmupSet: isWarmupSet
        )
    }

    private func hold(
        weightKg: Double?,
        reps: Int?,
        reason: DoubleProgression.HoldReason
    ) -> DoubleProgression.Suggestion {
        .init(
            proposedMeasurement: .init(weightKg: weightKg, reps: reps),
            reason: .hold(reason)
        )
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
