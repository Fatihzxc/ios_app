import CoreModels
import Foundation
import MetricsKit
import NutritionKit
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
    case duplicateNutritionLogIDs(id: UUID, count: Int)
    case invalidNutritionLog(id: UUID)
    case duplicateNutritionDay(localDay: Date, nutritionLogIDs: [UUID])
    case duplicateMealEntryIDs(id: UUID, count: Int)
    case mealEntryMissingNutritionLog(id: UUID)
    case mealEntryReferencesMissingNutritionLog(mealEntryID: UUID, nutritionLogID: UUID)
    case invalidMealEntry(id: UUID)
    case nonFiniteProteinTotal(nutritionLogID: UUID)
    case duplicateUserProfileIDs(id: UUID, count: Int)
    case ambiguousUserProfiles(profileIDs: [UUID])
}

@MainActor
public final class SwiftDataReportsRepository: ReportsRepository {
    private let modelContext: ModelContext
    private let calendar: Calendar

    public init(modelContext: ModelContext, calendar: Calendar) {
        self.modelContext = modelContext
        self.calendar = calendar
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
        let nutritionDayRecords = try nutritionDayRecords(in: interval)

        return ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: bodyMetricRecords.map(\.date)
                    + exerciseSetRecords.map(\.sessionDate)
                    + nutritionDayRecords.map(\.date)
            ),
            bodyMetricRecords: bodyMetricRecords,
            exerciseSetRecords: exerciseSetRecords,
            nutritionDayRecords: nutritionDayRecords
        )
    }

    private func nutritionDayRecords(
        in interval: ReportDateInterval
    ) throws -> [ReportNutritionDayRecord] {
        let allLogs = try modelContext.fetch(FetchDescriptor<DailyNutritionLog>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let selectedLogs = allLogs.filter { interval.contains($0.date) }
        let selectedLogIDs = Set(selectedLogs.map(\.id))
        try rejectDuplicateIDs(
            allLogs.filter { selectedLogIDs.contains($0.id) },
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateNutritionLogIDs
        )

        if let invalidLog = selectedLogs
            .filter({ !Self.validDate($0.date) || !Self.validDate($0.createdAt) })
            .min(by: { $0.id.uuidString < $1.id.uuidString }) {
            throw ReportsRepositoryIntegrityError.invalidNutritionLog(id: invalidLog.id)
        }
        try rejectDuplicateNutritionDays(selectedLogs)

        let allEntries = try modelContext.fetch(FetchDescriptor<MealEntry>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        if let orphan = allEntries
            .filter({ entry in
                entry.dailyNutritionLog == nil
                    && Self.validDate(entry.loggedAt)
                    && interval.contains(entry.loggedAt)
            })
            .min(by: { $0.id.uuidString < $1.id.uuidString }) {
            throw ReportsRepositoryIntegrityError.mealEntryMissingNutritionLog(id: orphan.id)
        }

        var selectedEntries: [MealEntry] = []
        for entry in allEntries {
            guard let relatedLog = entry.dailyNutritionLog,
                  selectedLogIDs.contains(relatedLog.id) else {
                continue
            }
            guard selectedLogs.contains(where: { $0 === relatedLog }) else {
                throw ReportsRepositoryIntegrityError.mealEntryReferencesMissingNutritionLog(
                    mealEntryID: entry.id,
                    nutritionLogID: relatedLog.id
                )
            }
            selectedEntries.append(entry)
        }

        let selectedEntryIDs = Set(selectedEntries.map(\.id))
        try rejectDuplicateIDs(
            allEntries.filter { selectedEntryIDs.contains($0.id) },
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateMealEntryIDs
        )
        for entry in selectedEntries {
            try validateMealEntry(entry)
        }

        var projected: [ReportNutritionDayRecord] = []
        for log in selectedLogs.sorted(by: nutritionLogOrderedBefore) {
            let entries = selectedEntries.filter { $0.dailyNutritionLog === log }
            guard !entries.isEmpty else { continue }
            var proteinTotalG = 0.0
            for entry in entries {
                let accumulated = proteinTotalG + entry.proteinResolved
                guard accumulated.isFinite else {
                    throw ReportsRepositoryIntegrityError.nonFiniteProteinTotal(
                        nutritionLogID: log.id
                    )
                }
                proteinTotalG = accumulated
            }
            projected.append(ReportNutritionDayRecord(
                id: log.id,
                date: calendar.startOfDay(for: log.date),
                createdAt: log.createdAt,
                entryCount: entries.count,
                proteinTotalG: proteinTotalG,
                proteinTargetG: nil
            ))
        }

        guard !projected.isEmpty else { return [] }
        let proteinTargetG = try currentProteinTarget()
        return projected.map { day in
            ReportNutritionDayRecord(
                id: day.id,
                date: day.date,
                createdAt: day.createdAt,
                entryCount: day.entryCount,
                proteinTotalG: day.proteinTotalG,
                proteinTargetG: proteinTargetG
            )
        }
        .sorted(by: nutritionDayOrderedBefore)
    }

    private func rejectDuplicateNutritionDays(
        _ logs: [DailyNutritionLog]
    ) throws {
        let grouped = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.date) }
        guard let duplicate = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key < $1.key })
            .first else {
            return
        }
        throw ReportsRepositoryIntegrityError.duplicateNutritionDay(
            localDay: duplicate.key,
            nutritionLogIDs: duplicate.value
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func validateMealEntry(_ entry: MealEntry) throws {
        do {
            guard Self.validDate(entry.createdAt), Self.validDate(entry.loggedAt) else {
                throw ReportsRepositoryIntegrityError.invalidMealEntry(id: entry.id)
            }
            let values = [
                entry.quantity,
                entry.caloriesResolved,
                entry.proteinResolved,
                entry.carbResolved,
                entry.fatResolved,
            ]
            guard values.allSatisfy(\.isFinite) else {
                throw ReportsRepositoryIntegrityError.invalidMealEntry(id: entry.id)
            }
            _ = try NutritionQuantity(Decimal(entry.quantity))
            _ = try NutritionMacros(
                calories: Decimal(entry.caloriesResolved),
                proteinG: Decimal(entry.proteinResolved),
                carbG: Decimal(entry.carbResolved),
                fatG: Decimal(entry.fatResolved)
            )
            _ = try MealCategory(
                kind: entry.category.kind,
                customName: entry.category.customName
            )
            let sourceCount = [
                entry.recipeId != nil,
                entry.foodId != nil,
                entry.adhocName != nil,
            ].filter { $0 }.count
            guard sourceCount == 1 else {
                throw ReportsRepositoryIntegrityError.invalidMealEntry(id: entry.id)
            }
            if let adhocName = entry.adhocName {
                let normalized = adhocName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty, normalized == adhocName else {
                    throw ReportsRepositoryIntegrityError.invalidMealEntry(id: entry.id)
                }
            }
        } catch let error as ReportsRepositoryIntegrityError {
            throw error
        } catch {
            throw ReportsRepositoryIntegrityError.invalidMealEntry(id: entry.id)
        }
    }

    private func currentProteinTarget() throws -> Double? {
        let profiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        try rejectDuplicateIDs(
            profiles,
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateUserProfileIDs
        )
        guard profiles.count <= 1 else {
            throw ReportsRepositoryIntegrityError.ambiguousUserProfiles(
                profileIDs: profiles.map(\.id)
            )
        }
        guard let target = profiles.first?.proteinTargetG,
              target.isFinite,
              target > 0 else {
            return nil
        }
        return target
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

    private func nutritionLogOrderedBefore(
        _ lhs: DailyNutritionLog,
        _ rhs: DailyNutritionLog
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func nutritionDayOrderedBefore(
        _ lhs: ReportNutritionDayRecord,
        _ rhs: ReportNutritionDayRecord
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private struct PersistedLogicalSetKey: Hashable {
    let sessionID: UUID
    let exerciseTemplateID: UUID
    let setIndex: Int
}
