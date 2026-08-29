import CoreModels
import Foundation
import MetricsKit
import ReportsKit
import SwiftData

public enum ReportsRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateBodyMetricIDs(id: UUID, count: Int)
    case invalidBodyMetric(id: UUID)
    case duplicateWorkoutSessionIDs(id: UUID, count: Int)
    case invalidWorkoutSession(id: UUID)
    case duplicateSetLogIDs(id: UUID, count: Int)
    case duplicateSetIndex(
        sessionID: UUID,
        exerciseTemplateID: UUID,
        setIndex: Int,
        setLogIDs: [UUID]
    )
    case setLogMissingWorkoutSession(id: UUID)
    case setLogReferencesMissingWorkoutSession(setLogID: UUID, workoutSessionID: UUID)
    case duplicateExerciseTemplateIDs(id: UUID, count: Int)
    case invalidExerciseTemplate(id: UUID)
    case missingExerciseTemplate(setLogID: UUID, exerciseTemplateID: UUID)
    case invalidExerciseSet(id: UUID)
    case invalidExerciseRepetitionRange(id: UUID, reps: Int)
}

@MainActor
public final class SwiftDataReportsRepository: ReportsRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchDashboardSource(
        in interval: ReportDateInterval
    ) async throws -> ReportsDashboardSource {
        // Integrity is enforced for the selected half-open interval. Persisted rows
        // outside it are unrelated to this report and cannot poison its projection.
        let bodyMetrics = try modelContext.fetch(FetchDescriptor<BodyMetric>())
            .filter { interval.contains($0.date) }
        try rejectDuplicateIDs(
            bodyMetrics,
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateBodyMetricIDs
        )
        let bodyMetricRecords = try bodyMetrics
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map(validatedBodyMetricRecord)
            .sorted(by: bodyMetricOrderedBefore)

        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        let selectedSessions = sessions
            .filter { $0.status == .completed && interval.contains($0.date) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let selectedSessionIDs = Set(selectedSessions.map(\.id))
        try rejectDuplicateIDs(
            sessions.filter { selectedSessionIDs.contains($0.id) },
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateWorkoutSessionIDs
        )
        let invalidSessions: [WorkoutSession] = selectedSessions.filter {
            !Self.validDate($0.date) || !Self.validDate($0.createdAt)
        }
        if let invalidSession = invalidSessions.min(
            by: { $0.id.uuidString < $1.id.uuidString }
        ) {
            throw ReportsRepositoryIntegrityError.invalidWorkoutSession(id: invalidSession.id)
        }
        let selectedSessionsByID = Dictionary(
            uniqueKeysWithValues: selectedSessions.map { ($0.id, $0) }
        )

        let setLogs = try modelContext.fetch(FetchDescriptor<SetLog>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        var selectedSetLogs: [(setLog: SetLog, session: WorkoutSession)] = []
        for setLog in setLogs {
            guard let relatedSession = setLog.workoutSession else {
                guard Self.validDate(setLog.completedAt) else {
                    throw ReportsRepositoryIntegrityError.invalidExerciseSet(id: setLog.id)
                }
                guard interval.contains(setLog.completedAt) else { continue }
                throw ReportsRepositoryIntegrityError.setLogMissingWorkoutSession(id: setLog.id)
            }
            if let selectedSession = selectedSessionsByID[relatedSession.id] {
                guard relatedSession === selectedSession else {
                    throw ReportsRepositoryIntegrityError.setLogReferencesMissingWorkoutSession(
                        setLogID: setLog.id,
                        workoutSessionID: relatedSession.id
                    )
                }
                selectedSetLogs.append((setLog, relatedSession))
                continue
            }
            guard relatedSession.status == .completed,
                  interval.contains(relatedSession.date) else {
                continue
            }
            throw ReportsRepositoryIntegrityError.setLogReferencesMissingWorkoutSession(
                setLogID: setLog.id,
                workoutSessionID: relatedSession.id
            )
        }
        selectedSetLogs.sort { $0.setLog.id.uuidString < $1.setLog.id.uuidString }

        try rejectDuplicateIDs(
            selectedSetLogs.map { $0.setLog },
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateSetLogIDs
        )
        try rejectLogicalDuplicateSets(selectedSetLogs)

        let referencedExerciseIDs = Set(selectedSetLogs.map { $0.setLog.exerciseTemplateId })
        let exercises = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
            .filter { referencedExerciseIDs.contains($0.id) }
        try rejectDuplicateIDs(
            exercises,
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateExerciseTemplateIDs
        )
        for exercise in exercises.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            try validateExerciseTemplate(exercise)
        }
        let exercisesByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        var exerciseSetRecords: [ReportExerciseSetRecord] = []
        for (setLog, session) in selectedSetLogs {
            guard let exercise = exercisesByID[setLog.exerciseTemplateId] else {
                throw ReportsRepositoryIntegrityError.missingExerciseTemplate(
                    setLogID: setLog.id,
                    exerciseTemplateID: setLog.exerciseTemplateId
                )
            }
            exerciseSetRecords.append(
                try validatedExerciseSetRecord(
                    from: setLog,
                    session: session,
                    exercise: exercise
                )
            )
        }
        exerciseSetRecords.sort(by: exerciseSetOrderedBefore)

        return ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: bodyMetricRecords.map(\.date)
                    + exerciseSetRecords.map(\.sessionDate)
            ),
            bodyMetricRecords: bodyMetricRecords,
            exerciseSetRecords: exerciseSetRecords
        )
    }

    private func validatedBodyMetricRecord(
        from model: BodyMetric
    ) throws -> ReportBodyMetricRecord {
        guard Self.validDate(model.date), Self.validDate(model.createdAt) else {
            throw ReportsRepositoryIntegrityError.invalidBodyMetric(id: model.id)
        }
        let value: BodyMetricValueInput
        do {
            value = try BodyMetricValueInput(
                type: model.type,
                customName: model.customName,
                value: model.value,
                unit: model.unit
            )
        } catch {
            throw ReportsRepositoryIntegrityError.invalidBodyMetric(id: model.id)
        }
        guard value.customName == model.customName, value.unit == model.unit else {
            throw ReportsRepositoryIntegrityError.invalidBodyMetric(id: model.id)
        }

        let kind: ReportBodyMetricKind
        switch value.type {
        case .weight:
            kind = .weight
        case .waist:
            kind = .waist
        case .custom:
            kind = .custom
        }
        return ReportBodyMetricRecord(
            id: model.id,
            date: model.date,
            createdAt: model.createdAt,
            kind: kind,
            customName: value.customName,
            value: value.value,
            unit: value.unit
        )
    }

    private func validatedExerciseSetRecord(
        from setLog: SetLog,
        session: WorkoutSession,
        exercise: ExerciseTemplate
    ) throws -> ReportExerciseSetRecord {
        guard setLog.setIndex >= 0,
              Self.validDate(setLog.createdAt),
              Self.validDate(setLog.completedAt) else {
            throw ReportsRepositoryIntegrityError.invalidExerciseSet(id: setLog.id)
        }
        if exercise.measurementKind == .weightReps,
           let reps = setLog.reps,
           reps > Int.max - 30 {
            throw ReportsRepositoryIntegrityError.invalidExerciseRepetitionRange(
                id: setLog.id,
                reps: reps
            )
        }
        do {
            try SetMeasurementValidator.validate(
                setLog.measurementInput,
                for: exercise.measurementKind
            )
        } catch {
            throw ReportsRepositoryIntegrityError.invalidExerciseSet(id: setLog.id)
        }

        let measurement: ReportExerciseMeasurement
        switch exercise.measurementKind {
        case .weightReps:
            measurement = .weightedRepetitions
        case .reps:
            measurement = .repetitions
        case .duration:
            measurement = .duration
        case .steps:
            measurement = .steps
        case .quality:
            measurement = .quality
        }

        return ReportExerciseSetRecord(
            id: setLog.id,
            createdAt: setLog.createdAt,
            sessionID: session.id,
            sessionDate: session.date,
            sessionCreatedAt: session.createdAt,
            exerciseTemplateID: exercise.id,
            exerciseName: exercise.name,
            setIndex: setLog.setIndex,
            sessionCompleted: session.status == .completed,
            isWarmup: setLog.isWarmupSet,
            measurement: measurement,
            weightKg: setLog.weightKg,
            reps: setLog.reps,
            durationSec: setLog.durationSec,
            distanceSteps: setLog.distanceSteps
        )
    }

    private func validateExerciseTemplate(_ exercise: ExerciseTemplate) throws {
        let normalizedName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName == exercise.name else {
            throw ReportsRepositoryIntegrityError.invalidExerciseTemplate(id: exercise.id)
        }
    }

    private func rejectDuplicateIDs<Model>(
        _ models: [Model],
        id: KeyPath<Model, UUID>,
        makeError: (UUID, Int) -> ReportsRepositoryIntegrityError
    ) throws {
        let grouped = Dictionary(grouping: models) { $0[keyPath: id] }
        guard let duplicate = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key.uuidString < $1.key.uuidString })
            .first else {
            return
        }
        throw makeError(duplicate.key, duplicate.value.count)
    }

    private func rejectLogicalDuplicateSets(
        _ records: [(setLog: SetLog, session: WorkoutSession)]
    ) throws {
        let grouped = Dictionary(grouping: records) {
            PersistedLogicalSetKey(
                sessionID: $0.session.id,
                exerciseTemplateID: $0.setLog.exerciseTemplateId,
                setIndex: $0.setLog.setIndex
            )
        }
        guard let duplicate = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { persistedSetKeyOrderedBefore($0.key, $1.key) })
            .first else {
            return
        }
        throw ReportsRepositoryIntegrityError.duplicateSetIndex(
            sessionID: duplicate.key.sessionID,
            exerciseTemplateID: duplicate.key.exerciseTemplateID,
            setIndex: duplicate.key.setIndex,
            setLogIDs: duplicate.value
                .map { $0.setLog.id }
                .sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func persistedSetKeyOrderedBefore(
        _ lhs: PersistedLogicalSetKey,
        _ rhs: PersistedLogicalSetKey
    ) -> Bool {
        if lhs.sessionID != rhs.sessionID {
            return lhs.sessionID.uuidString < rhs.sessionID.uuidString
        }
        if lhs.exerciseTemplateID != rhs.exerciseTemplateID {
            return lhs.exerciseTemplateID.uuidString < rhs.exerciseTemplateID.uuidString
        }
        return lhs.setIndex < rhs.setIndex
    }

    private static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private func bodyMetricOrderedBefore(
        _ lhs: ReportBodyMetricRecord,
        _ rhs: ReportBodyMetricRecord
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func exerciseSetOrderedBefore(
        _ lhs: ReportExerciseSetRecord,
        _ rhs: ReportExerciseSetRecord
    ) -> Bool {
        if lhs.sessionDate != rhs.sessionDate { return lhs.sessionDate < rhs.sessionDate }
        if lhs.sessionCreatedAt != rhs.sessionCreatedAt {
            return lhs.sessionCreatedAt < rhs.sessionCreatedAt
        }
        if lhs.sessionID != rhs.sessionID {
            return lhs.sessionID.uuidString < rhs.sessionID.uuidString
        }
        if lhs.exerciseTemplateID != rhs.exerciseTemplateID {
            return lhs.exerciseTemplateID.uuidString < rhs.exerciseTemplateID.uuidString
        }
        if lhs.setIndex != rhs.setIndex { return lhs.setIndex < rhs.setIndex }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private struct PersistedLogicalSetKey: Hashable {
    let sessionID: UUID
    let exerciseTemplateID: UUID
    let setIndex: Int
}
