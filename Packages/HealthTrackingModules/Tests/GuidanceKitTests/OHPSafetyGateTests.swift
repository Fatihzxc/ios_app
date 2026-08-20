import Foundation
@testable import GuidanceKit
import XCTest

final class OHPSafetyGateTests: XCTestCase {
    private let previousSessionID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000801"
    )!

    func testFirstSessionUsesWeekVariantAndNeverAllowsALoadIncrease() {
        let expectedVariants: [(week: Int, variant: OHPSafetyGate.EntryVariant)] = [
            (1, .seatedNeutral),
            (2, .seatedNeutral),
            (3, .standingNeutral),
            (4, .standingNeutral),
            (5, .standingStandard),
            (12, .standingStandard),
        ]

        for expectation in expectedVariants {
            XCTAssertEqual(
                OHPSafetyGate.resolve(
                    .init(
                        trainingWeekIndex: expectation.week,
                        previousSession: nil,
                        currentSymptomsPresent: false
                    )
                ),
                .decision(
                    .init(
                        entryVariant: expectation.variant,
                        loadIncreasePolicy: .blocked(.firstSession),
                        priorSessionQuestion: nil,
                        safetyStop: nil
                    )
                )
            )
        }
    }

    func testUnansweredPreviousSessionRequiresOneQuestionAndBlocksIncrease() {
        let input = makeInput(previousResponse: .notAsked)
        let snapshot = input

        XCTAssertEqual(
            OHPSafetyGate.resolve(input),
            .decision(
                .init(
                    entryVariant: .standingNeutral,
                    loadIncreasePolicy: .blocked(.previousResponseRequired),
                    priorSessionQuestion: .init(sessionID: previousSessionID),
                    safetyStop: nil
                )
            )
        )
        XCTAssertEqual(input, snapshot)
    }

    func testOnlyExplicitSymptomFreeResponseAllowsLoadIncrease() {
        let expectations: [
            (OHPSafetyGate.SymptomResponse, OHPSafetyGate.LoadIncreasePolicy)
        ] = [
            (.symptomFree, .allowed),
            (.symptomsPresent, .blocked(.previousSymptomsPresent)),
            (.uncertain, .blocked(.previousResponseUncertain)),
        ]

        for (response, policy) in expectations {
            guard case let .decision(decision) = OHPSafetyGate.resolve(
                makeInput(previousResponse: response)
            ) else {
                return XCTFail("A valid training week must produce an OHP decision.")
            }
            XCTAssertEqual(decision.entryVariant, .standingNeutral)
            XCTAssertEqual(decision.loadIncreasePolicy, policy)
            XCTAssertNil(decision.priorSessionQuestion)
            XCTAssertNil(decision.safetyStop)
        }
    }

    func testCurrentSymptomsTakePrecedenceAndRouteToTheExistingAlternative() {
        XCTAssertEqual(
            OHPSafetyGate.resolve(
                .init(
                    trainingWeekIndex: 7,
                    previousSession: .init(
                        id: previousSessionID,
                        response: .symptomFree
                    ),
                    currentSymptomsPresent: true
                )
            ),
            .decision(
                .init(
                    entryVariant: .standingStandard,
                    loadIncreasePolicy: .blocked(.currentSymptomsPresent),
                    priorSessionQuestion: nil,
                    safetyStop: .init(alternative: .halfKneelingDBPress)
                )
            )
        )
    }

    func testInvalidTrainingWeekIsExplicitInsteadOfInventingAVariant() {
        XCTAssertEqual(
            OHPSafetyGate.resolve(
                .init(
                    trainingWeekIndex: 0,
                    previousSession: nil,
                    currentSymptomsPresent: false
                )
            ),
            .invalid(.trainingWeekIndexOutOfRange)
        )
    }

    func testStorageValuesAndPublicTypesAreStable() {
        XCTAssertEqual(OHPSafetyGate.EntryVariant.seatedNeutral.rawValue, "seated-neutral")
        XCTAssertEqual(OHPSafetyGate.EntryVariant.standingNeutral.rawValue, "standing-neutral")
        XCTAssertEqual(OHPSafetyGate.EntryVariant.standingStandard.rawValue, "standing-standard")
        XCTAssertEqual(
            OHPSafetyGate.Alternative.halfKneelingDBPress.rawValue,
            "half-kneeling-db-press"
        )
        assertEquatableSendable(OHPSafetyGate.SymptomResponse.self)
        assertEquatableSendable(OHPSafetyGate.EntryVariant.self)
        assertEquatableSendable(OHPSafetyGate.Alternative.self)
        assertEquatableSendable(OHPSafetyGate.PreviousSession.self)
        assertEquatableSendable(OHPSafetyGate.Input.self)
        assertEquatableSendable(OHPSafetyGate.LoadIncreaseBlockReason.self)
        assertEquatableSendable(OHPSafetyGate.LoadIncreasePolicy.self)
        assertEquatableSendable(OHPSafetyGate.PriorSessionQuestion.self)
        assertEquatableSendable(OHPSafetyGate.SafetyStop.self)
        assertEquatableSendable(OHPSafetyGate.Decision.self)
        assertEquatableSendable(OHPSafetyGate.DataError.self)
        assertEquatableSendable(OHPSafetyGate.Outcome.self)
    }

    private func makeInput(
        previousResponse: OHPSafetyGate.SymptomResponse
    ) -> OHPSafetyGate.Input {
        .init(
            trainingWeekIndex: 3,
            previousSession: .init(
                id: previousSessionID,
                response: previousResponse
            ),
            currentSymptomsPresent: false
        )
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
