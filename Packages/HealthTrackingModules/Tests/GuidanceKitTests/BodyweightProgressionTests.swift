import Foundation
@testable import GuidanceKit
import XCTest

final class BodyweightProgressionTests: XCTestCase {
    func testBelowCeilingKeepsOneRealVariantAndTargetsTheExistingCeiling() {
        let input = makeInput(
            sets: [
                set(index: 1, reps: 8, variant: "bant-yesil"),
                set(index: 2, reps: 10, variant: "bant-yesil"),
            ]
        )
        let snapshot = input

        XCTAssertEqual(
            BodyweightProgression.suggest(input),
            .init(
                proposedMeasurement: .init(
                    weightKg: nil,
                    reps: 12,
                    performedVariant: "bant-yesil"
                ),
                reason: .buildRepetitions
            )
        )
        XCTAssertEqual(input, snapshot)
    }

    func testCeilingAdvancesOnlyToAnExplicitHarderVariantAndResetsToRepLow() {
        XCTAssertEqual(
            BodyweightProgression.suggest(
                makeInput(
                    harderVariant: "bantsiz",
                    sets: [
                        set(index: 1, reps: 12, variant: "bant-yesil"),
                        set(index: 2, reps: 12, variant: "bant-yesil"),
                    ]
                )
            ),
            .init(
                proposedMeasurement: .init(
                    weightKg: nil,
                    reps: 6,
                    performedVariant: "bantsiz"
                ),
                reason: .advanceToDefinedVariant
            )
        )
    }

    func testCeilingWithoutDefinedHarderVariantRequestsProgramAdjustment() {
        XCTAssertEqual(
            BodyweightProgression.suggest(
                makeInput(
                    sets: [
                        set(index: 1, reps: 12, variant: "bant-yesil"),
                        set(index: 2, reps: 12, variant: "bant-yesil"),
                    ]
                )
            ),
            .init(
                proposedMeasurement: .init(
                    weightKg: nil,
                    reps: 12,
                    performedVariant: "bant-yesil"
                ),
                reason: .programAdjustmentRequired
            )
        )
    }

    func testNilCeilingPreservesRealityWithoutInventingRepsOrAVariant() {
        XCTAssertEqual(
            BodyweightProgression.suggest(
                makeInput(
                    repHigh: nil,
                    harderVariant: "bantsiz",
                    sets: [set(index: 1, reps: 7, variant: "bant-sari")]
                )
            ),
            .init(
                proposedMeasurement: .init(
                    weightKg: nil,
                    reps: 7,
                    performedVariant: "bant-sari"
                ),
                reason: .missingRepCeiling
            )
        )
    }

    func testMixedVariantsAreNeverCombinedToClaimTheCeiling() {
        XCTAssertEqual(
            BodyweightProgression.suggest(
                makeInput(
                    harderVariant: "bantsiz",
                    sets: [
                        set(index: 1, reps: 12, variant: "bant-yesil"),
                        set(index: 2, reps: 12, variant: "bant-kirmizi"),
                    ]
                )
            ),
            .init(
                proposedMeasurement: .init(
                    weightKg: nil,
                    reps: 12,
                    performedVariant: "bant-kirmizi"
                ),
                reason: .inconsistentVariants
            )
        )
    }

    func testOptionalExternalWeightIsPreservedExactlyAndNeverAutoIncremented() {
        XCTAssertEqual(
            BodyweightProgression.suggest(
                makeInput(
                    sets: [
                        set(index: 1, weightKg: 5, reps: 10, variant: "chin-up"),
                    ]
                )
            ),
            .init(
                proposedMeasurement: .init(
                    weightKg: 5,
                    reps: 12,
                    performedVariant: "chin-up"
                ),
                reason: .buildRepetitions
            )
        )
    }

    func testWarmupsAreIgnoredAndAnEmptyWorkingHistoryIsExplicit() {
        XCTAssertEqual(
            BodyweightProgression.suggest(
                makeInput(
                    sets: [
                        set(
                            index: 0,
                            reps: 1,
                            variant: "isinma",
                            isWarmupSet: true
                        ),
                        set(index: 1, reps: 9, variant: "push-up"),
                    ]
                )
            ).reason,
            .buildRepetitions
        )
        XCTAssertEqual(
            BodyweightProgression.suggest(
                makeInput(
                    sets: [
                        set(
                            index: 0,
                            reps: 5,
                            variant: nil,
                            isWarmupSet: true
                        ),
                    ]
                )
            ),
            .init(
                proposedMeasurement: .init(
                    weightKg: nil,
                    reps: nil,
                    performedVariant: nil
                ),
                reason: .noWorkingSets
            )
        )
    }

    func testPublicValuesAreEquatableAndSendable() {
        assertEquatableSendable(BodyweightProgression.WorkingSet.self)
        assertEquatableSendable(BodyweightProgression.Input.self)
        assertEquatableSendable(BodyweightProgression.ProposedMeasurement.self)
        assertEquatableSendable(BodyweightProgression.Reason.self)
        assertEquatableSendable(BodyweightProgression.Suggestion.self)
    }

    private func makeInput(
        repHigh: Int? = 12,
        harderVariant: String? = nil,
        sets: [BodyweightProgression.WorkingSet]
    ) -> BodyweightProgression.Input {
        .init(
            repLow: 6,
            repHigh: repHigh,
            definedHarderVariant: harderVariant,
            sets: sets
        )
    }

    private func set(
        index: Int,
        weightKg: Double? = nil,
        reps: Int?,
        variant: String?,
        isWarmupSet: Bool = false
    ) -> BodyweightProgression.WorkingSet {
        .init(
            setIndex: index,
            weightKg: weightKg,
            reps: reps,
            performedVariant: variant,
            isWarmupSet: isWarmupSet
        )
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
