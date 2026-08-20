@testable import GuidanceKit
import XCTest

final class PhaseTrainingFocusTests: XCTestCase {
    func testPhasesOneAndTwoKeepTheBaseSuggestionEvenForBoneFocus() {
        for phase in [1, 2] {
            XCTAssertEqual(
                PhaseTrainingFocus.resolve(
                    .init(
                        phaseOrderIndex: phase,
                        exerciseFocus: .boneFocusHeavy,
                        templateRepLow: 8,
                        baseSuggestedReps: 12
                    )
                ),
                .init(suggestedReps: 12, reason: .baseSuggestion)
            )
        }
    }

    func testPhasesThreeAndFourUseOnlyTheExistingLowerBoundForBoneFocus() {
        for phase in [3, 4] {
            XCTAssertEqual(
                PhaseTrainingFocus.resolve(
                    .init(
                        phaseOrderIndex: phase,
                        exerciseFocus: .boneFocusHeavy,
                        templateRepLow: 8,
                        baseSuggestedReps: 12
                    )
                ),
                .init(suggestedReps: 8, reason: .boneFocusLowerBound)
            )
        }
    }

    func testStandardExercisesNeverReceiveBoneFocusAtAnyPhase() {
        for phase in 1...4 {
            XCTAssertEqual(
                PhaseTrainingFocus.resolve(
                    .init(
                        phaseOrderIndex: phase,
                        exerciseFocus: .standard,
                        templateRepLow: 8,
                        baseSuggestedReps: 12
                    )
                ),
                .init(suggestedReps: 12, reason: .baseSuggestion)
            )
        }
    }

    func testMissingTemplateLowerBoundNeverCreatesANewRepTarget() {
        XCTAssertEqual(
            PhaseTrainingFocus.resolve(
                .init(
                    phaseOrderIndex: 3,
                    exerciseFocus: .boneFocusHeavy,
                    templateRepLow: nil,
                    baseSuggestedReps: 12
                )
            ),
            .init(suggestedReps: 12, reason: .baseSuggestion)
        )
    }

    func testResolutionIsImmutableAndPublicValuesAreEquatableAndSendable() {
        let input = PhaseTrainingFocus.Input(
            phaseOrderIndex: 3,
            exerciseFocus: .boneFocusHeavy,
            templateRepLow: 6,
            baseSuggestedReps: 10
        )
        let snapshot = input

        _ = PhaseTrainingFocus.resolve(input)

        XCTAssertEqual(input, snapshot, "Guidance must not mutate its input.")
        assertEquatableSendable(PhaseTrainingFocus.ExerciseFocus.self)
        assertEquatableSendable(PhaseTrainingFocus.Reason.self)
        assertEquatableSendable(PhaseTrainingFocus.Input.self)
        assertEquatableSendable(PhaseTrainingFocus.Decision.self)
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
