import CoreModels
import Foundation
import TrainingKit
import XCTest

final class PersonalRecordPresentationTests: XCTestCase {
    private let sessionID = UUID(uuidString: "00000000-0000-4000-8000-000000000b01")!
    private let exerciseID = UUID(uuidString: "00000000-0000-4000-8000-000000000b02")!
    private let dayID = UUID(uuidString: "00000000-0000-4000-8000-000000000b03")!

    func testFirstValidSetIsSilentBaselineAndTrueWeightedRecordMapsOnce() {
        let plan = makePlan(measurementKind: .weightReps)
        let baselineOnly = PersonalRecordPresentationMapper.make(
            plan: plan,
            currentSetLogs: [set(1, weightKg: 20, reps: 10)],
            priorHistoryByExerciseID: [:]
        )
        XCTAssertTrue(baselineOnly.records.isEmpty)
        XCTAssertFalse(baselineOnly.shouldEmitSuccessFeedback)

        let prior = history(
            sessionOffset: 1,
            logs: [set(10, weightKg: 20, reps: 10, sessionOffset: 1)]
        )
        let presentation = PersonalRecordPresentationMapper.make(
            plan: plan,
            currentSetLogs: [
                set(20, weightKg: 100, reps: 1, isWarmup: true),
                set(21, weightKg: 20, reps: 11),
                set(22, weightKg: 20, reps: 12),
            ],
            priorHistoryByExerciseID: [exerciseID: [prior]]
        )

        XCTAssertEqual(
            presentation.records,
            [
                SessionPersonalRecordSummary(
                    exerciseID: exerciseID,
                    exerciseName: "Test hareketi",
                    kind: .weightedEstimatedOneRepMax,
                    previousBest: 26.666_666_666_666_664,
                    newBest: 28
                )
            ]
        )
        XCTAssertTrue(presentation.shouldEmitSuccessFeedback)
    }

    func testTieAndDifferentBodyweightVariantDoNotMapAsRecords() {
        let plan = makePlan(measurementKind: .reps)
        let prior = history(
            sessionOffset: 1,
            logs: [
                set(
                    10,
                    reps: 12,
                    variant: "Push-up",
                    sessionOffset: 1
                )
            ]
        )

        let tie = PersonalRecordPresentationMapper.make(
            plan: plan,
            currentSetLogs: [set(20, reps: 12, variant: "Push-up")],
            priorHistoryByExerciseID: [exerciseID: [prior]]
        )
        let differentVariant = PersonalRecordPresentationMapper.make(
            plan: plan,
            currentSetLogs: [set(21, reps: 30, variant: "Incline Push-up")],
            priorHistoryByExerciseID: [exerciseID: [prior]]
        )

        XCTAssertTrue(tie.records.isEmpty)
        XCTAssertTrue(differentVariant.records.isEmpty)
        XCTAssertFalse(tie.shouldEmitSuccessFeedback)
        XCTAssertFalse(differentVariant.shouldEmitSuccessFeedback)
    }

    func testDurationAndStepsMapToTheirExactRestrainedKinds() {
        let durationExerciseID = exerciseID
        let stepsExerciseID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000b04"
        )!
        let plan = SessionWorkoutPlanSnapshot(
            workoutDayID: dayID,
            name: "Gün A",
            focus: "Test",
            warmupItems: [],
            exercises: [
                exercise(id: durationExerciseID, name: "Plank", kind: .duration),
                exercise(id: stepsExerciseID, name: "Carry", kind: .steps),
            ],
            cooldownItems: []
        )
        let durationPrior = history(
            sessionOffset: 1,
            logs: [
                set(
                    10,
                    exerciseID: durationExerciseID,
                    duration: 30,
                    variant: "Plank",
                    sessionOffset: 1
                )
            ]
        )
        let stepsPrior = history(
            sessionOffset: 1,
            logs: [
                set(
                    11,
                    exerciseID: stepsExerciseID,
                    weightKg: 10,
                    steps: 100,
                    sessionOffset: 1
                )
            ]
        )

        let presentation = PersonalRecordPresentationMapper.make(
            plan: plan,
            currentSetLogs: [
                set(
                    20,
                    exerciseID: durationExerciseID,
                    duration: 31,
                    variant: "Plank"
                ),
                set(
                    21,
                    exerciseID: stepsExerciseID,
                    weightKg: 10,
                    steps: 101
                ),
            ],
            priorHistoryByExerciseID: [
                durationExerciseID: [durationPrior],
                stepsExerciseID: [stepsPrior],
            ]
        )

        XCTAssertEqual(presentation.records.map(\.kind), [.duration, .steps])
        XCTAssertEqual(presentation.records.map(\.newBest), [31, 101])
        XCTAssertTrue(presentation.shouldEmitSuccessFeedback)
    }

    func testMappingRecalculatesAfterPriorHistoryEditOrDelete() {
        let plan = makePlan(measurementKind: .reps)
        let baseline = history(
            sessionOffset: 1,
            logs: [set(10, reps: 10, variant: "Push-up", sessionOffset: 1)]
        )
        let deletedRecord = history(
            sessionOffset: 2,
            logs: [set(11, reps: 12, variant: "Push-up", sessionOffset: 2)]
        )
        let current = [set(20, reps: 11, variant: "Push-up")]

        let beforeDelete = PersonalRecordPresentationMapper.make(
            plan: plan,
            currentSetLogs: current,
            priorHistoryByExerciseID: [exerciseID: [deletedRecord, baseline]]
        )
        XCTAssertTrue(beforeDelete.records.isEmpty)

        let afterDelete = PersonalRecordPresentationMapper.make(
            plan: plan,
            currentSetLogs: current,
            priorHistoryByExerciseID: [exerciseID: [baseline]]
        )
        XCTAssertEqual(afterDelete.records.first?.previousBest, 10)
        XCTAssertEqual(afterDelete.records.first?.newBest, 11)

        let editedBaseline = history(
            sessionOffset: 1,
            logs: [set(10, reps: 13, variant: "Push-up", sessionOffset: 1)]
        )
        let afterEdit = PersonalRecordPresentationMapper.make(
            plan: plan,
            currentSetLogs: current,
            priorHistoryByExerciseID: [exerciseID: [editedBaseline]]
        )
        XCTAssertTrue(afterEdit.records.isEmpty)
        XCTAssertFalse(afterEdit.shouldEmitSuccessFeedback)
    }

    private func makePlan(
        measurementKind: ExerciseMeasurementKind
    ) -> SessionWorkoutPlanSnapshot {
        SessionWorkoutPlanSnapshot(
            workoutDayID: dayID,
            name: "Gün A",
            focus: "Test",
            warmupItems: [],
            exercises: [
                exercise(
                    id: exerciseID,
                    name: "Test hareketi",
                    kind: measurementKind
                )
            ],
            cooldownItems: []
        )
    }

    private func exercise(
        id: UUID,
        name: String,
        kind: ExerciseMeasurementKind
    ) -> SessionExerciseSnapshot {
        SessionExerciseSnapshot(
            id: id,
            name: name,
            orderIndex: 1,
            targetSets: 3,
            measurementKind: kind
        )
    }

    private func history(
        sessionOffset: Int,
        logs: [SetLogSnapshot]
    ) -> CompletedExerciseHistorySnapshot {
        CompletedExerciseHistorySnapshot(
            session: WorkoutSessionSnapshot(
                id: UUID(
                    uuidString: String(
                        format: "00000000-0000-4000-8001-%012d",
                        sessionOffset
                    )
                )!,
                date: Date(timeIntervalSinceReferenceDate: Double(sessionOffset)),
                status: .completed,
                workoutDayTemplateID: dayID
            ),
            setLogs: logs
        )
    }

    private func set(
        _ offset: Int,
        exerciseID: UUID? = nil,
        weightKg: Double? = nil,
        reps: Int? = nil,
        duration: Int? = nil,
        steps: Int? = nil,
        variant: String? = nil,
        isWarmup: Bool = false,
        sessionOffset: Int = 100
    ) -> SetLogSnapshot {
        let timestamp = Date(timeIntervalSinceReferenceDate: Double(sessionOffset))
        return SetLogSnapshot(
            id: UUID(
                uuidString: String(
                    format: "00000000-0000-4000-8002-%012d",
                    offset
                )
            )!,
            createdAt: timestamp,
            updatedAt: timestamp,
            workoutSessionID: sessionOffset == 100
                ? sessionID
                : UUID(
                    uuidString: String(
                        format: "00000000-0000-4000-8001-%012d",
                        sessionOffset
                    )
                )!,
            exerciseTemplateID: exerciseID ?? self.exerciseID,
            setIndex: offset,
            measurement: SetMeasurementInput(
                weightKg: weightKg,
                reps: reps,
                durationSec: duration,
                distanceSteps: steps,
                performedVariant: variant
            ),
            isWarmupSet: isWarmup,
            completedAt: timestamp
        )
    }
}
