import CoreModels
import Foundation
import TrainingKit
import XCTest

@MainActor
final class SetDraftTests: XCTestCase {
    func testPrefillUsesGuidanceThenSameSessionThenPriorSessionThenSeed() {
        let guidance = SetMeasurementInput(weightKg: 20, reps: 6, rir: 3)
        let sameSession = SetMeasurementInput(weightKg: 17.5, reps: 7, rir: 2)
        let priorSession = SetMeasurementInput(weightKg: 15, reps: 8, rir: 1)
        let seed = SetMeasurementInput(weightKg: 10, reps: 10)

        assertPrefill(
            guidance,
            source: .guidance,
            guidance: guidance,
            sameSession: sameSession,
            priorSession: priorSession,
            seed: seed
        )
        assertPrefill(
            sameSession,
            source: .sameSessionPrevious,
            guidance: nil,
            sameSession: sameSession,
            priorSession: priorSession,
            seed: seed
        )
        assertPrefill(
            priorSession,
            source: .priorSessionSameIndex,
            guidance: nil,
            sameSession: nil,
            priorSession: priorSession,
            seed: seed
        )
        assertPrefill(
            seed,
            source: .seed,
            guidance: nil,
            sameSession: nil,
            priorSession: nil,
            seed: seed
        )
    }

    func testNoPrefillStartsWithEmptyMeasurementAndNoSource() {
        let draft = makeDraft(kind: .quality)

        XCTAssertEqual(draft.measurement, SetMeasurementInput())
        XCTAssertNil(draft.prefillSource)
    }

    func testEnabledFieldsFollowMeasurementKindWithoutPersistenceTypes() {
        let cases: [(ExerciseMeasurementKind, Set<SetDraft.Field>)] = [
            (.weightReps, [.weightKg, .reps, .performedVariant, .rir]),
            (.reps, [.weightKg, .reps, .performedVariant, .rir]),
            (.duration, [.durationSec, .performedVariant, .rir]),
            (.steps, [.weightKg, .distanceSteps, .performedVariant, .rir]),
            (.quality, [.reps, .durationSec, .performedVariant, .rir])
        ]

        for (kind, expected) in cases {
            XCTAssertEqual(makeDraft(kind: kind).enabledFields, expected)
        }
    }

    func testDashRIRSelectionIsNilRatherThanZeroInSaveRequest() throws {
        let draft = makeDraft(
            kind: .reps,
            seed: SetMeasurementInput(reps: 8, rir: 0)
        )

        draft.selectRIR(nil)
        let request = try draft.makeSaveRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            completedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )

        XCTAssertNil(draft.measurement.rir)
        XCTAssertNil(request.measurement.rir)
    }

    func testSaveRequestDelegatesFinalValidationToCoreModels() {
        let missingWeight = makeDraft(kind: .weightReps, seed: .init(reps: 8))
        XCTAssertThrowsError(try missingWeight.makeSaveRequest(completedAt: .now)) { error in
            XCTAssertEqual(
                error as? SetMeasurementValidationError,
                .requiredMeasurementMissing
            )
        }

        let ambiguousQuality = makeDraft(
            kind: .quality,
            seed: .init(reps: 8, durationSec: 30)
        )
        XCTAssertThrowsError(try ambiguousQuality.makeSaveRequest(completedAt: .now)) { error in
            XCTAssertEqual(error as? SetMeasurementValidationError, .ambiguousMeasurement)
        }
    }

    func testSaveRequestPreservesUserOverrideAndImmutableIdentity() throws {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let setID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let completedAt = Date(timeIntervalSinceReferenceDate: 3_000)
        let draft = SetDraft(
            workoutSessionID: sessionID,
            exerciseTemplateID: exerciseID,
            setIndex: 2,
            measurementKind: .weightReps,
            isWarmupSet: false,
            guidance: .init(weightKg: 20, reps: 6, rir: 3)
        )

        draft.measurement.weightKg = 17.5
        draft.measurement.reps = 8
        draft.selectRIR(2)
        let request = try draft.makeSaveRequest(id: setID, completedAt: completedAt)

        XCTAssertEqual(request.id, setID)
        XCTAssertEqual(request.workoutSessionID, sessionID)
        XCTAssertEqual(request.exerciseTemplateID, exerciseID)
        XCTAssertEqual(request.setIndex, 2)
        XCTAssertEqual(request.measurement, .init(weightKg: 17.5, reps: 8, rir: 2))
        XCTAssertFalse(request.isWarmupSet)
        XCTAssertEqual(request.completedAt, completedAt)
        assertEquatableSendable(request)
    }

    private func assertPrefill(
        _ expected: SetMeasurementInput,
        source: SetDraft.PrefillSource,
        guidance: SetMeasurementInput?,
        sameSession: SetMeasurementInput?,
        priorSession: SetMeasurementInput?,
        seed: SetMeasurementInput?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let draft = makeDraft(
            kind: .weightReps,
            guidance: guidance,
            sameSession: sameSession,
            priorSession: priorSession,
            seed: seed
        )

        XCTAssertEqual(draft.measurement, expected, file: file, line: line)
        XCTAssertEqual(draft.prefillSource, source, file: file, line: line)
    }

    private func makeDraft(
        kind: ExerciseMeasurementKind,
        guidance: SetMeasurementInput? = nil,
        sameSession: SetMeasurementInput? = nil,
        priorSession: SetMeasurementInput? = nil,
        seed: SetMeasurementInput? = nil
    ) -> SetDraft {
        SetDraft(
            workoutSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            exerciseTemplateID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            setIndex: 1,
            measurementKind: kind,
            isWarmupSet: false,
            guidance: guidance,
            sameSessionPrevious: sameSession,
            priorSessionSameIndex: priorSession,
            seed: seed
        )
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
