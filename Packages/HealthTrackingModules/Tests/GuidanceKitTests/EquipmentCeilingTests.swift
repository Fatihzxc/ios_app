@testable import GuidanceKit
import XCTest

final class EquipmentCeilingTests: XCTestCase {
    func testBelowCeilingPreservesTheExactSuggestionWithoutCeilingAdvice() {
        let input = EquipmentCeiling.Input(
            suggestedWeightKg: 17.5,
            suggestedReps: 12
        )
        let snapshot = input

        XCTAssertEqual(
            EquipmentCeiling.apply(input),
            .init(
                suggestedWeightKg: 17.5,
                suggestedReps: 12,
                reason: .belowCeiling,
                orderedNextSteps: [],
                definedTempo: nil,
                definedUnilateralVariant: nil,
                showsInvestmentInformation: false
            )
        )
        XCTAssertEqual(input, snapshot, "Guidance must not mutate its input.")
    }

    func testAtCeilingKeepsTwentyAndOrdersRepetitionsTempoThenUnilateral() {
        XCTAssertEqual(
            EquipmentCeiling.apply(
                .init(suggestedWeightKg: 20, suggestedReps: 12)
            ),
            .init(
                suggestedWeightKg: 20,
                suggestedReps: 12,
                reason: .atCeiling,
                orderedNextSteps: [.repetitions, .tempo, .unilateral],
                definedTempo: nil,
                definedUnilateralVariant: nil,
                showsInvestmentInformation: true
            )
        )
    }

    func testAboveCeilingClampsToExactlyTwentyWithoutChangingRepetitions() {
        XCTAssertEqual(
            EquipmentCeiling.apply(
                .init(suggestedWeightKg: 22.5, suggestedReps: 8)
            ),
            .init(
                suggestedWeightKg: 20,
                suggestedReps: 8,
                reason: .atCeiling,
                orderedNextSteps: [.repetitions, .tempo, .unilateral],
                definedTempo: nil,
                definedUnilateralVariant: nil,
                showsInvestmentInformation: true
            )
        )
    }

    func testCeilingForwardsOnlyDefinedTempoAndUnilateralValues() {
        let defined = EquipmentCeiling.apply(
            .init(
                suggestedWeightKg: 20,
                suggestedReps: 10,
                definedTempo: "kontrollü eksantrik",
                definedUnilateralVariant: "tek kol"
            )
        )
        let absent = EquipmentCeiling.apply(
            .init(suggestedWeightKg: 20, suggestedReps: 10)
        )

        XCTAssertEqual(defined.definedTempo, "kontrollü eksantrik")
        XCTAssertEqual(defined.definedUnilateralVariant, "tek kol")
        XCTAssertNil(absent.definedTempo, "The engine must not invent a tempo value.")
        XCTAssertNil(
            absent.definedUnilateralVariant,
            "The engine must not invent a unilateral variant."
        )
    }

    func testMissingWeightNeverBecomesARealLoad() {
        XCTAssertEqual(
            EquipmentCeiling.apply(
                .init(suggestedWeightKg: nil, suggestedReps: 8)
            ),
            .init(
                suggestedWeightKg: nil,
                suggestedReps: 8,
                reason: .belowCeiling,
                orderedNextSteps: [],
                definedTempo: nil,
                definedUnilateralVariant: nil,
                showsInvestmentInformation: false
            )
        )
    }

    func testPublicValuesAreEquatableAndSendable() {
        assertEquatableSendable(EquipmentCeiling.NextStep.self)
        assertEquatableSendable(EquipmentCeiling.Reason.self)
        assertEquatableSendable(EquipmentCeiling.Input.self)
        assertEquatableSendable(EquipmentCeiling.Decision.self)
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
