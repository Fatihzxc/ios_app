import CoreModels
import Foundation
import GuidanceKit

public enum PersonalRecordPresentationMapper {
    public static func make(
        plan: SessionWorkoutPlanSnapshot,
        currentSetLogs: [SetLogSnapshot],
        priorHistoryByExerciseID: [UUID: [CompletedExerciseHistorySnapshot]]
    ) -> SessionPersonalRecordPresentation {
        let records = plan.exercises.compactMap { exercise in
            recordSummary(
                for: exercise,
                currentSetLogs: currentSetLogs.filter {
                    $0.exerciseTemplateID == exercise.id
                },
                priorHistory: priorHistoryByExerciseID[exercise.id, default: []]
            )
        }
        return SessionPersonalRecordPresentation(
            records: records,
            shouldEmitSuccessFeedback: !records.isEmpty
        )
    }

    private static func recordSummary(
        for exercise: SessionExerciseSnapshot,
        currentSetLogs: [SetLogSnapshot],
        priorHistory: [CompletedExerciseHistorySnapshot]
    ) -> SessionPersonalRecordSummary? {
        guard let recordKind = recordKind(for: exercise.measurementKind) else {
            return nil
        }

        let priorAttempts = priorHistory
            .flatMap(\.setLogs)
            .compactMap { attempt(from: $0, kind: exercise.measurementKind) }
        let currentAttempts = currentSetLogs
            .compactMap { attempt(from: $0, kind: exercise.measurementKind) }
        let currentAttemptIDs = Set(currentAttempts.map(\.id))
        let results = PersonalRecordDetector.evaluate(priorAttempts + currentAttempts)

        var previousBest: Double?
        var newBest: Double?
        for result in results where currentAttemptIDs.contains(result.attemptID) {
            guard case let .newRecord(value, previous) = result.outcome else {
                continue
            }
            if previousBest == nil {
                previousBest = previous
            }
            newBest = value
        }
        guard let previousBest, let newBest else { return nil }

        return SessionPersonalRecordSummary(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            kind: recordKind,
            previousBest: previousBest,
            newBest: newBest
        )
    }

    private static func attempt(
        from setLog: SetLogSnapshot,
        kind: ExerciseMeasurementKind
    ) -> PersonalRecordDetector.Attempt? {
        guard let measurement = measurement(from: setLog.measurement, kind: kind) else {
            return nil
        }
        return PersonalRecordDetector.Attempt(
            id: setLog.id,
            completedAt: setLog.completedAt,
            measurement: measurement,
            isWarmupSet: setLog.isWarmupSet
        )
    }

    private static func measurement(
        from input: SetMeasurementInput,
        kind: ExerciseMeasurementKind
    ) -> PersonalRecordDetector.Measurement? {
        switch kind {
        case .weightReps:
            .weightedReps(weightKg: input.weightKg, reps: input.reps)
        case .reps:
            .bodyweightReps(
                reps: input.reps,
                performedVariant: input.performedVariant
            )
        case .duration:
            .duration(
                seconds: input.durationSec,
                performedVariant: input.performedVariant
            )
        case .steps:
            .steps(count: input.distanceSteps, loadKg: input.weightKg)
        case .quality:
            nil
        }
    }

    private static func recordKind(
        for kind: ExerciseMeasurementKind
    ) -> SessionPersonalRecordKind? {
        switch kind {
        case .weightReps:
            .weightedEstimatedOneRepMax
        case .reps:
            .repetitions
        case .duration:
            .duration
        case .steps:
            .steps
        case .quality:
            nil
        }
    }
}
