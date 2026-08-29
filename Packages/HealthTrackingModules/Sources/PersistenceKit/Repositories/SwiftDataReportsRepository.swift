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
    case duplicateSleepLogIDs(id: UUID, count: Int)
    case duplicateSleepLocalDay(localDay: Date, recordIDs: [UUID])
    case invalidSleepLog(id: UUID)
    case duplicateMoodLogIDs(id: UUID, count: Int)
    case duplicateMoodLocalDay(localDay: Date, recordIDs: [UUID])
    case invalidMoodLog(id: UUID)
    case duplicatePostureMetricIDs(id: UUID, count: Int)
    case duplicatePostureLocalDay(localDay: Date, recordIDs: [UUID])
    case invalidPostureMetric(id: UUID)
    case duplicateActiveProgramIDs(id: UUID, count: Int)
    case ambiguousActivePrograms(programIDs: [UUID])
    case duplicateReportProgramPhaseIDs(id: UUID, count: Int)
    case invalidReportProgramPhase(id: UUID)
    case duplicateReportProgramStates(programID: UUID, count: Int)
    case invalidReportProgramState(programID: UUID)
    case duplicatePhaseTransitionSettings(programID: UUID, count: Int)
    case invalidPhaseTransitionLedger(programID: UUID, PhaseTransitionLedgerError)
    case phaseTransitionStateMismatch(programID: UUID)
}

public enum ReportsExportProgressFieldV1: String, Equatable, Sendable {
    case completedWarmupItemIDs
    case completedCooldownItemIDs
}

public enum ReportsExportProgressReferenceIssueV1: Equatable, Sendable {
    case missing
    case wrongRecordType(ExportRecordTypeV1)
    case missingWorkoutDay
    case wrongWorkoutDay(expected: UUID, actual: UUID)
}

public enum ReportsExportTrainingExerciseReferenceIssueV1: Equatable, Sendable {
    case missingWorkoutDay
    case wrongWorkoutDay(expected: UUID, actual: UUID)
}

public enum ReportsExportRepositoryError: Error, Equatable, Sendable {
    case duplicateRecord(recordType: ExportRecordTypeV1, id: UUID, count: Int)
    case missingReference(
        sourceType: ExportRecordTypeV1,
        sourceID: UUID,
        targetType: ExportRecordTypeV1,
        targetID: UUID?
    )
    case ambiguousReferencedUserProfiles([UUID])
    case invalidWorkoutSessionProgress(
        id: UUID,
        field: ReportsExportProgressFieldV1,
        reason: WorkoutSessionProgressCodecError
    )
    case invalidWorkoutSessionProgressReference(
        id: UUID,
        field: ReportsExportProgressFieldV1,
        targetID: UUID,
        reason: ReportsExportProgressReferenceIssueV1
    )
    case programStatePhaseProgramMismatch(
        stateID: UUID,
        programID: UUID,
        phaseID: UUID,
        phaseProgramID: UUID?
    )
    case invalidTrainingExerciseReference(
        sourceType: ExportRecordTypeV1,
        sourceID: UUID,
        exerciseTemplateID: UUID,
        reason: ReportsExportTrainingExerciseReferenceIssueV1
    )
    case nonFiniteValue(recordType: ExportRecordTypeV1, id: UUID, column: String)
    case invalidStringArray(recordType: ExportRecordTypeV1, id: UUID, column: String)
    case projectionMismatch(recordType: ExportRecordTypeV1)
}

private struct ExportReferenceProvenanceV1 {
    let sourceType: ExportRecordTypeV1
    let sourceID: UUID
}

public enum ReportsExportModelInventoryV1 {
    public static let modelTypes: [any PersistentModel.Type] = [
        UserProfile.self,
        Program.self,
        ProgramPhase.self,
        ProgramState.self,
        WorkoutDayTemplate.self,
        ExerciseTemplate.self,
        WarmupItem.self,
        CooldownItem.self,
        WorkoutSession.self,
        SetLog.self,
        WorkoutSessionProgress.self,
        Food.self,
        Recipe.self,
        DailyNutritionLog.self,
        MealEntry.self,
        BodyMetric.self,
        PostureMetric.self,
        SleepLog.self,
        MoodLog.self,
        HealthCheckReminder.self,
        BloodworkResult.self,
        ProgressPhoto.self,
        AppReminder.self,
        AppSetting.self,
    ]
}

@MainActor
extension SwiftDataReportsRepository: ReportsExportRepository {
    public func fetchExportSnapshot(
        in interval: ReportDateInterval,
        modules: Set<ExportModuleV1>
    ) async throws -> ExportSnapshotV1 {
        let selectedModules = modules
        if selectedModules.isEmpty {
            return try ExportSnapshotV1(
                interval: interval,
                selectedModules: [],
                tables: []
            )
        }

        let profiles = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<UserProfile>()), id: \.id
        )
        let programs = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<Program>()), id: \.id
        )
        let phases = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<ProgramPhase>()), id: \.id
        )
        let states = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<ProgramState>()), id: \.id
        )
        let days = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<WorkoutDayTemplate>()), id: \.id
        )
        let exercises = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<ExerciseTemplate>()), id: \.id
        )
        let warmups = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<WarmupItem>()), id: \.id
        )
        let cooldowns = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<CooldownItem>()), id: \.id
        )
        let sessions = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<WorkoutSession>()), id: \.id
        )
        let sets = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<SetLog>()), id: \.id
        )
        let progressRecords = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<WorkoutSessionProgress>()), id: \.id
        )
        let foods = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<Food>()), id: \.id
        )
        let recipes = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<Recipe>()), id: \.id
        )
        let nutritionDays = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<DailyNutritionLog>()), id: \.id
        )
        let meals = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<MealEntry>()), id: \.id
        )
        let bodyMetrics = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<BodyMetric>()), id: \.id
        )
        let postureMetrics = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<PostureMetric>()), id: \.id
        )
        let sleepLogs = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<SleepLog>()), id: \.id
        )
        let moodLogs = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<MoodLog>()), id: \.id
        )
        let healthReminders = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<HealthCheckReminder>()), id: \.id
        )
        let bloodwork = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<BloodworkResult>()), id: \.id
        )
        let photos = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<ProgressPhoto>()), id: \.id
        )
        let reminders = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<AppReminder>()), id: \.id
        )
        let settings = canonicalExportRecords(
            try modelContext.fetch(FetchDescriptor<AppSetting>()), id: \.id
        )

        var rowsByModule: [ExportModuleV1: [ExportRowV1]] = Dictionary(
            uniqueKeysWithValues: selectedModules.map { ($0, []) }
        )
        var referencedWorkoutDayTemplateSources = [UUID: ExportReferenceProvenanceV1]()
        var referencedExerciseTemplateSources = [UUID: ExportReferenceProvenanceV1]()
        var referencedProgramIDs = Set<UUID>()
        var needsReferencedProfile = false

        if selectedModules.contains(.training) {
            let selectedSessions = sessions.filter { interval.contains($0.date) }
            let selectedSets = sets.filter { interval.contains($0.completedAt) }
            let selectedProgress = progressRecords.filter { record in
                interval.contains(record.updatedAt)
            }
            needsReferencedProfile = !selectedSessions.isEmpty
                || !selectedSets.isEmpty
                || !selectedProgress.isEmpty
            try rejectExportDuplicateIDs(selectedSessions, type: .workoutSession, id: \.id)
            try rejectExportDuplicateIDs(selectedSets, type: .setLog, id: \.id)
            try rejectExportDuplicateIDs(
                selectedProgress,
                type: .workoutSessionProgress,
                id: \.id
            )

            for session in selectedSessions {
                recordExportReference(
                    targetID: session.workoutDayTemplateId,
                    sourceType: .workoutSession,
                    sourceID: session.id,
                    in: &referencedWorkoutDayTemplateSources
                )
                rowsByModule[.training, default: []].append(try exportRow(session))
            }
            for set in selectedSets {
                recordExportReference(
                    targetID: set.exerciseTemplateId,
                    sourceType: .setLog,
                    sourceID: set.id,
                    in: &referencedExerciseTemplateSources
                )
                guard let relatedSession = set.workoutSession else {
                    throw ReportsExportRepositoryError.missingReference(
                        sourceType: .setLog,
                        sourceID: set.id,
                        targetType: .workoutSession,
                        targetID: nil
                    )
                }
                let session = try resolveExportReference(
                    relatedSession.id,
                    in: sessions,
                    sourceType: .setLog,
                    sourceID: set.id,
                    targetType: .workoutSession,
                    id: \.id
                )
                _ = try resolveExportReference(
                    session.workoutDayTemplateId,
                    in: days,
                    sourceType: .workoutSession,
                    sourceID: session.id,
                    targetType: .workoutDayTemplate,
                    id: \.id
                )
                let exercise = try resolveExportReference(
                    set.exerciseTemplateId,
                    in: exercises,
                    sourceType: .setLog,
                    sourceID: set.id,
                    targetType: .exerciseTemplate,
                    id: \.id
                )
                try validateExportTrainingExerciseReference(
                    exercise,
                    session: session,
                    sourceType: .setLog,
                    sourceID: set.id
                )
                recordExportReference(
                    targetID: session.workoutDayTemplateId,
                    sourceType: .workoutSession,
                    sourceID: session.id,
                    in: &referencedWorkoutDayTemplateSources
                )
                rowsByModule[.training, default: []].append(try exportRow(set))
            }
            for progress in selectedProgress {
                let row = try exportRow(progress)
                let session = try resolveExportReference(
                    progress.workoutSessionId,
                    in: sessions,
                    sourceType: .workoutSessionProgress,
                    sourceID: progress.id,
                    targetType: .workoutSession,
                    id: \.id
                )
                _ = try resolveExportReference(
                    session.workoutDayTemplateId,
                    in: days,
                    sourceType: .workoutSession,
                    sourceID: session.id,
                    targetType: .workoutDayTemplate,
                    id: \.id
                )
                try validateExportProgressChecklistReferences(
                    progress,
                    session: session,
                    warmups: warmups,
                    cooldowns: cooldowns
                )
                recordExportReference(
                    targetID: session.workoutDayTemplateId,
                    sourceType: .workoutSession,
                    sourceID: session.id,
                    in: &referencedWorkoutDayTemplateSources
                )
                if let exerciseID = progress.currentExerciseTemplateId {
                    let exercise = try resolveExportReference(
                        exerciseID,
                        in: exercises,
                        sourceType: .workoutSessionProgress,
                        sourceID: progress.id,
                        targetType: .exerciseTemplate,
                        id: \.id
                    )
                    try validateExportTrainingExerciseReference(
                        exercise,
                        session: session,
                        sourceType: .workoutSessionProgress,
                        sourceID: progress.id
                    )
                    recordExportReference(
                        targetID: exerciseID,
                        sourceType: .workoutSessionProgress,
                        sourceID: progress.id,
                        in: &referencedExerciseTemplateSources
                    )
                }
                rowsByModule[.training, default: []].append(row)
            }

            for (exerciseID, source) in referencedExerciseTemplateSources.sorted(
                by: { uuidOrderedBefore($0.key, $1.key) }
            ) {
                let exercise = try resolveExportReference(
                    exerciseID,
                    in: exercises,
                    sourceType: source.sourceType,
                    sourceID: source.sourceID,
                    targetType: .exerciseTemplate,
                    id: \.id
                )
                guard let day = exercise.workoutDayTemplate else {
                    throw ReportsExportRepositoryError.missingReference(
                        sourceType: .exerciseTemplate,
                        sourceID: exercise.id,
                        targetType: .workoutDayTemplate,
                        targetID: nil
                    )
                }
                recordExportReference(
                    targetID: day.id,
                    sourceType: .exerciseTemplate,
                    sourceID: exercise.id,
                    in: &referencedWorkoutDayTemplateSources
                )
            }

            let referencedDays = try referencedWorkoutDayTemplateSources
                .sorted(by: { uuidOrderedBefore($0.key, $1.key) })
                .map { dayID, source in
                    try resolveExportReference(
                        dayID,
                        in: days,
                        sourceType: source.sourceType,
                        sourceID: source.sourceID,
                        targetType: .workoutDayTemplate,
                        id: \.id
                    )
                }
            for day in referencedDays {
                if let programID = day.program?.id { referencedProgramIDs.insert(programID) }
            }
            for exercise in exercises {
                guard let dayID = exercise.workoutDayTemplate?.id,
                      referencedWorkoutDayTemplateSources[dayID] != nil else {
                    continue
                }
                recordExportReference(
                    targetID: exercise.id,
                    sourceType: .exerciseTemplate,
                    sourceID: exercise.id,
                    in: &referencedExerciseTemplateSources
                )
            }
        }

        if selectedModules.contains(.nutrition) {
            let selectedDays = nutritionDays.filter { interval.contains($0.date) }
            let selectedMeals = meals.filter { interval.contains($0.loggedAt) }
            needsReferencedProfile = needsReferencedProfile
                || !selectedDays.isEmpty
                || !selectedMeals.isEmpty
            try rejectExportDuplicateIDs(selectedDays, type: .dailyNutritionLog, id: \.id)
            try rejectExportDuplicateIDs(selectedMeals, type: .mealEntry, id: \.id)
            try rejectExportDuplicateIDs(foods, type: .food, id: \.id)
            try rejectExportDuplicateIDs(recipes, type: .recipe, id: \.id)
            rowsByModule[.nutrition, default: []].append(
                contentsOf: try foods.map { try exportRow($0, configScope: .selected) }
            )
            rowsByModule[.nutrition, default: []].append(
                contentsOf: try recipes.map { try exportRow($0, configScope: .selected) }
            )
            for day in selectedDays {
                rowsByModule[.nutrition, default: []].append(try exportRow(day))
            }

            for meal in selectedMeals {
                guard let relatedDay = meal.dailyNutritionLog else {
                    throw ReportsExportRepositoryError.missingReference(
                        sourceType: .mealEntry,
                        sourceID: meal.id,
                        targetType: .dailyNutritionLog,
                        targetID: nil
                    )
                }
                _ = try resolveExportReference(
                    relatedDay.id,
                    in: nutritionDays,
                    sourceType: .mealEntry,
                    sourceID: meal.id,
                    targetType: .dailyNutritionLog,
                    id: \.id
                )
                if let foodID = meal.foodId {
                    _ = try resolveExportReference(
                        foodID,
                        in: foods,
                        sourceType: .mealEntry,
                        sourceID: meal.id,
                        targetType: .food,
                        id: \.id
                    )
                }
                if let recipeID = meal.recipeId {
                    _ = try resolveExportReference(
                        recipeID,
                        in: recipes,
                        sourceType: .mealEntry,
                        sourceID: meal.id,
                        targetType: .recipe,
                        id: \.id
                    )
                }
                rowsByModule[.nutrition, default: []].append(try exportRow(meal))
            }
        }

        if selectedModules.contains(.metrics) {
            let selectedBody = bodyMetrics.filter { interval.contains($0.date) }
            let selectedPosture = postureMetrics.filter { interval.contains($0.date) }
            needsReferencedProfile = needsReferencedProfile
                || !selectedBody.isEmpty
                || !selectedPosture.isEmpty
            try rejectExportDuplicateIDs(selectedBody, type: .bodyMetric, id: \.id)
            try rejectExportDuplicateIDs(selectedPosture, type: .postureMetric, id: \.id)
            rowsByModule[.metrics, default: []].append(
                contentsOf: try selectedBody.map { try exportRow($0) }
            )
            rowsByModule[.metrics, default: []].append(
                contentsOf: try selectedPosture.map { try exportRow($0) }
            )
        }

        if selectedModules.contains(.lifestyle) {
            let selectedSleep = sleepLogs.filter { interval.contains($0.date) }
            let selectedMood = moodLogs.filter { interval.contains($0.date) }
            try rejectExportDuplicateIDs(selectedSleep, type: .sleepLog, id: \.id)
            try rejectExportDuplicateIDs(selectedMood, type: .moodLog, id: \.id)
            rowsByModule[.lifestyle, default: []].append(
                contentsOf: try selectedSleep.map { try exportRow($0) }
            )
            rowsByModule[.lifestyle, default: []].append(
                contentsOf: try selectedMood.map { try exportRow($0) }
            )
        }

        if selectedModules.contains(.health) {
            let selectedReminders = healthReminders.filter { interval.contains($0.dueDate) }
            let selectedBloodwork = bloodwork.filter { interval.contains($0.date) }
            try rejectExportDuplicateIDs(
                selectedReminders,
                type: .healthCheckReminder,
                id: \.id
            )
            try rejectExportDuplicateIDs(selectedBloodwork, type: .bloodworkResult, id: \.id)
            rowsByModule[.health, default: []].append(
                contentsOf: try selectedReminders.map { try exportRow($0) }
            )
            rowsByModule[.health, default: []].append(
                contentsOf: try selectedBloodwork.map { try exportRow($0) }
            )
        }

        if selectedModules.contains(.photos) {
            let selectedPhotos = photos.filter { interval.contains($0.date) }
            try rejectExportDuplicateIDs(selectedPhotos, type: .progressPhoto, id: \.id)
            rowsByModule[.photos, default: []].append(
                contentsOf: try selectedPhotos.map { try exportRow($0) }
            )
        }

        if selectedModules.contains(.profileProgram) {
            try appendSelectedProfileProgramRows(
                profiles: profiles,
                programs: programs,
                phases: phases,
                states: states,
                days: days,
                exercises: exercises,
                warmups: warmups,
                cooldowns: cooldowns,
                rowsByModule: &rowsByModule
            )
        } else {
            if needsReferencedProfile {
                try rejectExportDuplicateIDs(profiles, type: .userProfile, id: \.id)
                guard profiles.count <= 1 else {
                    throw ReportsExportRepositoryError.ambiguousReferencedUserProfiles(
                        profiles.map(\.id).sorted(by: uuidOrderedBefore)
                    )
                }
                if let profile = profiles.first {
                    rowsByModule[.profileProgram, default: []].append(
                        try exportRow(profile, configScope: .referenced)
                    )
                }
            }
            try appendReferencedTrainingConfiguration(
                referencedProgramIDs: referencedProgramIDs,
                referencedWorkoutDayTemplateIDs: Set(
                    referencedWorkoutDayTemplateSources.keys
                ),
                programs: programs,
                phases: phases,
                states: states,
                days: days,
                exercises: exercises,
                warmups: warmups,
                cooldowns: cooldowns,
                rowsByModule: &rowsByModule
            )
        }

        if selectedModules.contains(.system) {
            try rejectExportDuplicateIDs(reminders, type: .appReminder, id: \.id)
            try rejectExportDuplicateIDs(settings, type: .appSetting, id: \.id)
            rowsByModule[.system, default: []].append(
                contentsOf: try reminders.map { try exportRow($0, configScope: .selected) }
            )
            rowsByModule[.system, default: []].append(
                contentsOf: try settings.map { try exportRow($0, configScope: .selected) }
            )
        }

        let tables = try ExportModuleV1.allCases.compactMap { module -> ExportTableV1? in
            let rows = rowsByModule[module] ?? []
            guard selectedModules.contains(module) || !rows.isEmpty else { return nil }
            return try ExportTableV1(
                module: module,
                columns: ExportSchemaV1.columns(for: module),
                rows: rows
            )
        }
        return try ExportSnapshotV1(
            interval: interval,
            selectedModules: selectedModules,
            tables: tables
        )
    }
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
        let sleepRecords = try sleepRecords(in: interval)
        let moodRecords = try moodRecords(in: interval)
        let postureRecords = try postureRecords(in: interval)
        let phaseProjection = try phaseProjection()

        return ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: bodyMetricRecords.map(\.date)
                    + exerciseSetRecords.map(\.sessionDate)
                    + nutritionDayRecords.map(\.date)
                    + sleepRecords.map(\.date)
                    + moodRecords.map(\.date)
                    + postureRecords.map(\.date)
            ),
            bodyMetricRecords: bodyMetricRecords,
            exerciseSetRecords: exerciseSetRecords,
            nutritionDayRecords: nutritionDayRecords,
            sleepRecords: sleepRecords,
            moodRecords: moodRecords,
            postureRecords: postureRecords,
            programPhases: phaseProjection.phases,
            currentPhaseState: phaseProjection.state,
            phaseTransitions: phaseProjection.transitions
        )
    }

    private func sleepRecords(in interval: ReportDateInterval) throws -> [ReportSleepRecord] {
        let all = try modelContext.fetch(FetchDescriptor<SleepLog>())
        let selected = all.filter { interval.contains($0.date) }
        let selectedIDs = Set(selected.map(\.id))
        try rejectDuplicateIDs(
            all.filter { selectedIDs.contains($0.id) },
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateSleepLogIDs
        )
        try rejectDuplicateLocalDays(
            selected,
            id: \.id,
            date: \.date,
            makeError: ReportsRepositoryIntegrityError.duplicateSleepLocalDay
        )
        if let invalid = selected.filter({ !validSleep($0) })
            .min(by: { $0.id.uuidString < $1.id.uuidString }) {
            throw ReportsRepositoryIntegrityError.invalidSleepLog(id: invalid.id)
        }
        return selected.map {
            ReportSleepRecord(
                id: $0.id,
                date: $0.date,
                createdAt: $0.createdAt,
                durationHours: $0.durationHours,
                quality: $0.quality
            )
        }.sorted(by: lifestyleRecordOrder)
    }

    private func moodRecords(in interval: ReportDateInterval) throws -> [ReportMoodRecord] {
        let all = try modelContext.fetch(FetchDescriptor<MoodLog>())
        let selected = all.filter { interval.contains($0.date) }
        let selectedIDs = Set(selected.map(\.id))
        try rejectDuplicateIDs(
            all.filter { selectedIDs.contains($0.id) },
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateMoodLogIDs
        )
        try rejectDuplicateLocalDays(
            selected,
            id: \.id,
            date: \.date,
            makeError: ReportsRepositoryIntegrityError.duplicateMoodLocalDay
        )
        if let invalid = selected.filter({ !validMood($0) })
            .min(by: { $0.id.uuidString < $1.id.uuidString }) {
            throw ReportsRepositoryIntegrityError.invalidMoodLog(id: invalid.id)
        }
        return selected.map {
            ReportMoodRecord(
                id: $0.id,
                date: $0.date,
                createdAt: $0.createdAt,
                score: $0.moodScore,
                energy: $0.energy
            )
        }.sorted(by: lifestyleRecordOrder)
    }

    private func postureRecords(in interval: ReportDateInterval) throws -> [ReportPostureRecord] {
        let all = try modelContext.fetch(FetchDescriptor<PostureMetric>())
        let selected = all.filter { interval.contains($0.date) }
        let selectedIDs = Set(selected.map(\.id))
        try rejectDuplicateIDs(
            all.filter { selectedIDs.contains($0.id) },
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicatePostureMetricIDs
        )
        try rejectDuplicateLocalDays(
            selected,
            id: \.id,
            date: \.date,
            makeError: ReportsRepositoryIntegrityError.duplicatePostureLocalDay
        )
        if let invalid = selected.filter({ !validPosture($0) })
            .min(by: { $0.id.uuidString < $1.id.uuidString }) {
            throw ReportsRepositoryIntegrityError.invalidPostureMetric(id: invalid.id)
        }
        return selected.map {
            ReportPostureRecord(
                id: $0.id,
                date: $0.date,
                createdAt: $0.createdAt,
                symptomScore: $0.symptomScore,
                wallTestPass: $0.wallTestPass
            )
        }.sorted(by: lifestyleRecordOrder)
    }

    private func phaseProjection() throws -> (
        phases: [ReportProgramPhaseRecord],
        state: ReportCurrentPhaseStateRecord?,
        transitions: [ReportPhaseTransitionRecord]
    ) {
        let allPrograms = try modelContext.fetch(FetchDescriptor<Program>())
        let active = allPrograms.filter { $0.isActive }
        let activeIDs = Set(active.map(\.id))
        try rejectDuplicateIDs(
            allPrograms.filter { activeIDs.contains($0.id) },
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateActiveProgramIDs
        )
        guard active.count <= 1 else {
            throw ReportsRepositoryIntegrityError.ambiguousActivePrograms(
                programIDs: active.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
        }
        guard let program = active.first else { return ([], nil, []) }

        let allPhases = try modelContext.fetch(FetchDescriptor<ProgramPhase>())
        let phases = allPhases.filter { $0.program?.id == program.id }
        try rejectDuplicateIDs(
            phases,
            id: \.id,
            makeError: ReportsRepositoryIntegrityError.duplicateReportProgramPhaseIDs
        )
        if let invalid = phases.filter({
            let name = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty || name != $0.name || $0.orderIndex < 0
                || !Self.validDate($0.createdAt) || !Self.validDate($0.updatedAt)
        }).min(by: { $0.id.uuidString < $1.id.uuidString }) {
            throw ReportsRepositoryIntegrityError.invalidReportProgramPhase(id: invalid.id)
        }
        let projectedPhases = phases.map {
            ReportProgramPhaseRecord(id: $0.id, name: $0.name, orderIndex: $0.orderIndex)
        }.sorted {
            if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
            return $0.id.uuidString < $1.id.uuidString
        }
        let phaseIDs = Set(projectedPhases.map(\.id))

        let states = try modelContext.fetch(FetchDescriptor<ProgramState>())
            .filter { $0.programId == program.id }
        guard states.count <= 1 else {
            throw ReportsRepositoryIntegrityError.duplicateReportProgramStates(
                programID: program.id,
                count: states.count
            )
        }

        let key = PhaseTransitionLedgerV1.key(for: program.id)
        let settings = try modelContext.fetch(FetchDescriptor<AppSetting>())
            .filter { $0.key == key }
        guard settings.count <= 1 else {
            throw ReportsRepositoryIntegrityError.duplicatePhaseTransitionSettings(
                programID: program.id,
                count: settings.count
            )
        }
        let ledger: PhaseTransitionLedgerV1?
        if let setting = settings.first {
            do {
                ledger = try PhaseTransitionLedgerV1.decode(setting.value, for: program.id)
            } catch let error as PhaseTransitionLedgerError {
                throw ReportsRepositoryIntegrityError.invalidPhaseTransitionLedger(
                    programID: program.id,
                    error
                )
            }
        } else {
            ledger = nil
        }

        guard let state = states.first else {
            guard ledger == nil else {
                throw ReportsRepositoryIntegrityError.phaseTransitionStateMismatch(
                    programID: program.id
                )
            }
            return (projectedPhases, nil, [])
        }
        guard phaseIDs.contains(state.currentPhaseId),
              Self.validDate(state.phaseStartedAt) else {
            throw ReportsRepositoryIntegrityError.invalidReportProgramState(programID: program.id)
        }
        let projectedState = ReportCurrentPhaseStateRecord(
            programID: program.id,
            phaseID: state.currentPhaseId,
            phaseStartedAt: state.phaseStartedAt
        )
        guard let ledger else {
            return (projectedPhases, projectedState, [])
        }
        guard ledger.records.allSatisfy({
            phaseIDs.contains($0.fromPhaseID) && phaseIDs.contains($0.toPhaseID)
        }) else {
            throw ReportsRepositoryIntegrityError.invalidReportProgramState(programID: program.id)
        }
        if let last = ledger.records.last {
            guard last.toPhaseID == state.currentPhaseId,
                  last.transitionedAt == state.phaseStartedAt else {
                throw ReportsRepositoryIntegrityError.phaseTransitionStateMismatch(
                    programID: program.id
                )
            }
        }
        return (
            projectedPhases,
            projectedState,
            ledger.records.map {
                ReportPhaseTransitionRecord(
                    id: $0.id,
                    programID: $0.programID,
                    fromPhaseID: $0.fromPhaseID,
                    toPhaseID: $0.toPhaseID,
                    fromStartedAt: $0.fromStartedAt,
                    transitionedAt: $0.transitionedAt
                )
            }
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

    private func rejectDuplicateLocalDays<Model>(
        _ models: [Model],
        id: KeyPath<Model, UUID>,
        date: KeyPath<Model, Date>,
        makeError: (Date, [UUID]) -> ReportsRepositoryIntegrityError
    ) throws {
        let grouped = Dictionary(grouping: models) {
            calendar.startOfDay(for: $0[keyPath: date])
        }
        guard let duplicate = grouped.filter({ $0.value.count > 1 })
            .sorted(by: { $0.key < $1.key }).first else { return }
        throw makeError(
            duplicate.key,
            duplicate.value.map { $0[keyPath: id] }.sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func validSleep(_ model: SleepLog) -> Bool {
        Self.validDate(model.date) && Self.validDate(model.createdAt)
            && model.durationHours.isFinite
            && model.durationHours > 0 && model.durationHours <= 24
            && (1...10).contains(model.quality)
            && canonicalOptionalText(model.note)
    }

    private func validMood(_ model: MoodLog) -> Bool {
        guard Self.validDate(model.date), Self.validDate(model.createdAt),
              model.moodScore.map({ (0...10).contains($0) }) != false,
              model.energy.map({ (0...10).contains($0) }) != false,
              canonicalOptionalText(model.note) else { return false }
        let normalized = model.moodTags.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard normalized == model.moodTags, normalized.allSatisfy({ !$0.isEmpty }) else {
            return false
        }
        let locale = Locale(identifier: "tr_TR")
        return Set(normalized.map { $0.lowercased(with: locale) }).count == normalized.count
            && (model.moodScore != nil || !normalized.isEmpty)
    }

    private func validPosture(_ model: PostureMetric) -> Bool {
        guard Self.validDate(model.date), Self.validDate(model.createdAt),
              model.symptomScore.map({ (0...10).contains($0) }) != false,
              canonicalOptionalText(model.region),
              canonicalOptionalText(model.note) else { return false }
        return model.wallTestPass != nil || model.symptomScore != nil
            || model.region != nil || model.note != nil
    }

    private func canonicalOptionalText(_ value: String?) -> Bool {
        guard let value else { return true }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == value
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

    private func lifestyleRecordOrder(
        _ lhs: ReportSleepRecord,
        _ rhs: ReportSleepRecord
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func lifestyleRecordOrder(
        _ lhs: ReportMoodRecord,
        _ rhs: ReportMoodRecord
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func lifestyleRecordOrder(
        _ lhs: ReportPostureRecord,
        _ rhs: ReportPostureRecord
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
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

@MainActor
private extension SwiftDataReportsRepository {
    func canonicalExportRecords<Record>(
        _ records: [Record],
        id: KeyPath<Record, UUID>
    ) -> [Record] {
        records.sorted {
            uuidOrderedBefore($0[keyPath: id], $1[keyPath: id])
        }
    }

    func rejectExportDuplicateIDs<Record>(
        _ records: [Record],
        type: ExportRecordTypeV1,
        id: KeyPath<Record, UUID>
    ) throws {
        let groups = Dictionary(grouping: records, by: { $0[keyPath: id] })
        if let duplicate = groups
            .filter({ $0.value.count > 1 })
            .sorted(by: { uuidOrderedBefore($0.key, $1.key) })
            .first {
            throw ReportsExportRepositoryError.duplicateRecord(
                recordType: type,
                id: duplicate.key,
                count: duplicate.value.count
            )
        }
    }

    func resolveExportReference<Record>(
        _ targetID: UUID,
        in records: [Record],
        sourceType: ExportRecordTypeV1,
        sourceID: UUID,
        targetType: ExportRecordTypeV1,
        id: KeyPath<Record, UUID>
    ) throws -> Record {
        let matches = records.filter { $0[keyPath: id] == targetID }
        guard matches.count == 1 else {
            if matches.count > 1 {
                throw ReportsExportRepositoryError.duplicateRecord(
                    recordType: targetType,
                    id: targetID,
                    count: matches.count
                )
            }
            throw ReportsExportRepositoryError.missingReference(
                sourceType: sourceType,
                sourceID: sourceID,
                targetType: targetType,
                targetID: targetID
            )
        }
        return matches[0]
    }

    func recordExportReference(
        targetID: UUID,
        sourceType: ExportRecordTypeV1,
        sourceID: UUID,
        in references: inout [UUID: ExportReferenceProvenanceV1]
    ) {
        let candidate = ExportReferenceProvenanceV1(
            sourceType: sourceType,
            sourceID: sourceID
        )
        guard let current = references[targetID] else {
            references[targetID] = candidate
            return
        }
        if candidate.sourceType.rawValue != current.sourceType.rawValue {
            if candidate.sourceType.rawValue < current.sourceType.rawValue {
                references[targetID] = candidate
            }
        } else if uuidOrderedBefore(candidate.sourceID, current.sourceID) {
            references[targetID] = candidate
        }
    }

    func validateExportProgressChecklistReferences(
        _ progress: WorkoutSessionProgress,
        session: WorkoutSession,
        warmups: [WarmupItem],
        cooldowns: [CooldownItem]
    ) throws {
        let completedWarmupIDs: Set<UUID>
        do {
            completedWarmupIDs = try WorkoutSessionProgressCodec.decode(
                progress.completedWarmupItemIdsData
            )
        } catch let error as WorkoutSessionProgressCodecError {
            throw ReportsExportRepositoryError.invalidWorkoutSessionProgress(
                id: progress.id,
                field: .completedWarmupItemIDs,
                reason: error
            )
        }
        let completedCooldownIDs: Set<UUID>
        do {
            completedCooldownIDs = try WorkoutSessionProgressCodec.decode(
                progress.completedCooldownItemIdsData
            )
        } catch let error as WorkoutSessionProgressCodecError {
            throw ReportsExportRepositoryError.invalidWorkoutSessionProgress(
                id: progress.id,
                field: .completedCooldownItemIDs,
                reason: error
            )
        }

        for targetID in completedWarmupIDs.sorted(by: uuidOrderedBefore) {
            try validateExportProgressReference(
                progressID: progress.id,
                field: .completedWarmupItemIDs,
                targetID: targetID,
                expectedWorkoutDayID: session.workoutDayTemplateId,
                expectedRecords: warmups,
                expectedType: .warmupItem,
                wrongTypeRecords: cooldowns,
                wrongType: .cooldownItem,
                id: \.id,
                wrongTypeID: \.id,
                workoutDay: \.workoutDayTemplate
            )
        }
        for targetID in completedCooldownIDs.sorted(by: uuidOrderedBefore) {
            try validateExportProgressReference(
                progressID: progress.id,
                field: .completedCooldownItemIDs,
                targetID: targetID,
                expectedWorkoutDayID: session.workoutDayTemplateId,
                expectedRecords: cooldowns,
                expectedType: .cooldownItem,
                wrongTypeRecords: warmups,
                wrongType: .warmupItem,
                id: \.id,
                wrongTypeID: \.id,
                workoutDay: \.workoutDayTemplate
            )
        }
    }

    func validateExportProgressReference<ExpectedRecord, WrongTypeRecord>(
        progressID: UUID,
        field: ReportsExportProgressFieldV1,
        targetID: UUID,
        expectedWorkoutDayID: UUID,
        expectedRecords: [ExpectedRecord],
        expectedType: ExportRecordTypeV1,
        wrongTypeRecords: [WrongTypeRecord],
        wrongType: ExportRecordTypeV1,
        id: KeyPath<ExpectedRecord, UUID>,
        wrongTypeID: KeyPath<WrongTypeRecord, UUID>,
        workoutDay: KeyPath<ExpectedRecord, WorkoutDayTemplate?>
    ) throws {
        let matches = expectedRecords.filter { $0[keyPath: id] == targetID }
        if matches.count > 1 {
            throw ReportsExportRepositoryError.duplicateRecord(
                recordType: expectedType,
                id: targetID,
                count: matches.count
            )
        }
        guard let record = matches.first else {
            let wrongMatches = wrongTypeRecords.filter {
                $0[keyPath: wrongTypeID] == targetID
            }
            if wrongMatches.count > 1 {
                throw ReportsExportRepositoryError.duplicateRecord(
                    recordType: wrongType,
                    id: targetID,
                    count: wrongMatches.count
                )
            }
            throw ReportsExportRepositoryError.invalidWorkoutSessionProgressReference(
                id: progressID,
                field: field,
                targetID: targetID,
                reason: wrongMatches.isEmpty ? .missing : .wrongRecordType(wrongType)
            )
        }
        guard let actualWorkoutDayID = record[keyPath: workoutDay]?.id else {
            throw ReportsExportRepositoryError.invalidWorkoutSessionProgressReference(
                id: progressID,
                field: field,
                targetID: targetID,
                reason: .missingWorkoutDay
            )
        }
        guard actualWorkoutDayID == expectedWorkoutDayID else {
            throw ReportsExportRepositoryError.invalidWorkoutSessionProgressReference(
                id: progressID,
                field: field,
                targetID: targetID,
                reason: .wrongWorkoutDay(
                    expected: expectedWorkoutDayID,
                    actual: actualWorkoutDayID
                )
            )
        }
    }

    func validateExportTrainingExerciseReference(
        _ exercise: ExerciseTemplate,
        session: WorkoutSession,
        sourceType: ExportRecordTypeV1,
        sourceID: UUID
    ) throws {
        guard let actualWorkoutDayID = exercise.workoutDayTemplate?.id else {
            throw ReportsExportRepositoryError.invalidTrainingExerciseReference(
                sourceType: sourceType,
                sourceID: sourceID,
                exerciseTemplateID: exercise.id,
                reason: .missingWorkoutDay
            )
        }
        guard actualWorkoutDayID == session.workoutDayTemplateId else {
            throw ReportsExportRepositoryError.invalidTrainingExerciseReference(
                sourceType: sourceType,
                sourceID: sourceID,
                exerciseTemplateID: exercise.id,
                reason: .wrongWorkoutDay(
                    expected: session.workoutDayTemplateId,
                    actual: actualWorkoutDayID
                )
            )
        }
    }

    func validateExportProgramStateReferences(
        _ states: [ProgramState],
        programs: [Program],
        phases: [ProgramPhase]
    ) throws {
        for state in states.sorted(by: { uuidOrderedBefore($0.id, $1.id) }) {
            _ = try resolveExportReference(
                state.programId,
                in: programs,
                sourceType: .programState,
                sourceID: state.id,
                targetType: .program,
                id: \.id
            )
            let phase = try resolveExportReference(
                state.currentPhaseId,
                in: phases,
                sourceType: .programState,
                sourceID: state.id,
                targetType: .programPhase,
                id: \.id
            )
            let phaseProgramID = phase.program?.id
            guard phaseProgramID == state.programId else {
                throw ReportsExportRepositoryError.programStatePhaseProgramMismatch(
                    stateID: state.id,
                    programID: state.programId,
                    phaseID: phase.id,
                    phaseProgramID: phaseProgramID
                )
            }
        }
    }

    func appendSelectedProfileProgramRows(
        profiles: [UserProfile],
        programs: [Program],
        phases: [ProgramPhase],
        states: [ProgramState],
        days: [WorkoutDayTemplate],
        exercises: [ExerciseTemplate],
        warmups: [WarmupItem],
        cooldowns: [CooldownItem],
        rowsByModule: inout [ExportModuleV1: [ExportRowV1]]
    ) throws {
        try rejectExportDuplicateIDs(profiles, type: .userProfile, id: \.id)
        try rejectExportDuplicateIDs(programs, type: .program, id: \.id)
        try rejectExportDuplicateIDs(phases, type: .programPhase, id: \.id)
        try rejectExportDuplicateIDs(states, type: .programState, id: \.id)
        try rejectExportDuplicateIDs(days, type: .workoutDayTemplate, id: \.id)
        try rejectExportDuplicateIDs(exercises, type: .exerciseTemplate, id: \.id)
        try rejectExportDuplicateIDs(warmups, type: .warmupItem, id: \.id)
        try rejectExportDuplicateIDs(cooldowns, type: .cooldownItem, id: \.id)
        try validateExportProgramStateReferences(
            states,
            programs: programs,
            phases: phases
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try profiles.map { try exportRow($0, configScope: .selected) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try programs.map { try exportRow($0, configScope: .selected) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try phases.map { try exportRow($0, configScope: .selected) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try states.map { try exportRow($0, configScope: .selected) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try days.map { try exportRow($0, configScope: .selected) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try exercises.map { try exportRow($0, configScope: .selected) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try warmups.map { try exportRow($0, configScope: .selected) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try cooldowns.map { try exportRow($0, configScope: .selected) }
        )
    }

    func appendReferencedTrainingConfiguration(
        referencedProgramIDs: Set<UUID>,
        referencedWorkoutDayTemplateIDs: Set<UUID>,
        programs: [Program],
        phases: [ProgramPhase],
        states: [ProgramState],
        days: [WorkoutDayTemplate],
        exercises: [ExerciseTemplate],
        warmups: [WarmupItem],
        cooldowns: [CooldownItem],
        rowsByModule: inout [ExportModuleV1: [ExportRowV1]]
    ) throws {
        let selectedPrograms = programs.filter { referencedProgramIDs.contains($0.id) }
        let selectedPhases = phases.filter {
            guard let programID = $0.program?.id else { return false }
            return referencedProgramIDs.contains(programID)
        }
        let selectedStates = states.filter { referencedProgramIDs.contains($0.programId) }
        let selectedDays = days.filter { referencedWorkoutDayTemplateIDs.contains($0.id) }
        let selectedExercises = exercises.filter {
            guard let dayID = $0.workoutDayTemplate?.id else { return false }
            return referencedWorkoutDayTemplateIDs.contains(dayID)
        }
        let selectedWarmups = warmups.filter {
            guard let dayID = $0.workoutDayTemplate?.id else { return false }
            return referencedWorkoutDayTemplateIDs.contains(dayID)
        }
        let selectedCooldowns = cooldowns.filter {
            guard let dayID = $0.workoutDayTemplate?.id else { return false }
            return referencedWorkoutDayTemplateIDs.contains(dayID)
        }
        try rejectExportDuplicateIDs(selectedPrograms, type: .program, id: \.id)
        try rejectExportDuplicateIDs(selectedPhases, type: .programPhase, id: \.id)
        try rejectExportDuplicateIDs(selectedStates, type: .programState, id: \.id)
        try rejectExportDuplicateIDs(selectedDays, type: .workoutDayTemplate, id: \.id)
        try rejectExportDuplicateIDs(selectedExercises, type: .exerciseTemplate, id: \.id)
        try rejectExportDuplicateIDs(selectedWarmups, type: .warmupItem, id: \.id)
        try rejectExportDuplicateIDs(selectedCooldowns, type: .cooldownItem, id: \.id)
        try validateExportProgramStateReferences(
            selectedStates,
            programs: programs,
            phases: phases
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try selectedPrograms.map { try exportRow($0, configScope: .referenced) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try selectedPhases.map { try exportRow($0, configScope: .referenced) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try selectedStates.map { try exportRow($0, configScope: .referenced) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try selectedDays.map { try exportRow($0, configScope: .referenced) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try selectedExercises.map { try exportRow($0, configScope: .referenced) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try selectedWarmups.map { try exportRow($0, configScope: .referenced) }
        )
        rowsByModule[.profileProgram, default: []].append(
            contentsOf: try selectedCooldowns.map { try exportRow($0, configScope: .referenced) }
        )
    }

    func makeExportRow(
        recordType: ExportRecordTypeV1,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        primaryTimestamp: Date,
        configScope: ExportConfigScopeV1?,
        values: [String: ExportCellV1]
    ) throws -> ExportRowV1 {
        let definition = ExportSchemaV1.definition(for: recordType)
        let expectedNames = Set(definition.fields.dropFirst().map(\.name))
        guard Set(values.keys) == expectedNames else {
            throw ReportsExportRepositoryError.projectionMismatch(recordType: recordType)
        }
        var cells: [ExportNamedCellV1] = []
        for column in ExportSchemaV1.columns(for: recordType.module) {
            let value: ExportCellV1
            switch column.name {
            case "record_type": value = .text(recordType.rawValue)
            case "id": value = .uuid(id)
            case "created_at": value = .timestamp(createdAt)
            case "updated_at": value = .timestamp(updatedAt)
            case "config_scope": value = configScope.map { .text($0.rawValue) } ?? .null
            default: value = values[column.name] ?? .null
            }
            switch value {
            case let .decimal(decimal) where !decimal.isFinite:
                throw ReportsExportRepositoryError.nonFiniteValue(
                    recordType: recordType,
                    id: id,
                    column: column.name
                )
            case let .timestamp(timestamp)
                where !timestamp.timeIntervalSinceReferenceDate.isFinite:
                throw ReportsExportRepositoryError.nonFiniteValue(
                    recordType: recordType,
                    id: id,
                    column: column.name
                )
            default:
                break
            }
            cells.append(ExportNamedCellV1(columnName: column.name, value: value))
        }
        return try ExportRowV1(primaryTimestamp: primaryTimestamp, cells: cells)
    }

    func canonicalUUIDArray(_ identifiers: Set<UUID>) -> String {
        "[" + identifiers.map { "\"\($0.uuidString.lowercased())\"" }
            .sorted().joined(separator: ",") + "]"
    }

    func canonicalStringArray(
        _ values: [String],
        recordType: ExportRecordTypeV1,
        id: UUID,
        column: String
    ) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let data = try encoder.encode(values)
            guard let value = String(data: data, encoding: .utf8) else {
                throw ReportsExportRepositoryError.invalidStringArray(
                    recordType: recordType,
                    id: id,
                    column: column
                )
            }
            return value
        } catch let error as ReportsExportRepositoryError {
            throw error
        } catch {
            throw ReportsExportRepositoryError.invalidStringArray(
                recordType: recordType,
                id: id,
                column: column
            )
        }
    }

    func uuidOrderedBefore(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }

    func optionalText(_ value: String?) -> ExportCellV1 {
        value.map(ExportCellV1.text) ?? .null
    }

    func optionalInteger(_ value: Int?) -> ExportCellV1 {
        value.map { .integer(Int64($0)) } ?? .null
    }

    func optionalDecimal(_ value: Double?) -> ExportCellV1 {
        value.map(ExportCellV1.decimal) ?? .null
    }

    func optionalBoolean(_ value: Bool?) -> ExportCellV1 {
        value.map(ExportCellV1.boolean) ?? .null
    }

    func optionalTimestamp(_ value: Date?) -> ExportCellV1 {
        value.map(ExportCellV1.timestamp) ?? .null
    }

    func optionalUUID(_ value: UUID?) -> ExportCellV1 {
        value.map(ExportCellV1.uuid) ?? .null
    }
}

@MainActor
private extension SwiftDataReportsRepository {
    func exportRow(
        _ profile: UserProfile,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .userProfile,
            id: profile.id,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt,
            primaryTimestamp: profile.programStartDate,
            configScope: configScope,
            values: [
                "user_profile_display_name": .text(profile.displayName),
                "user_profile_height_cm": .decimal(profile.heightCm),
                "user_profile_start_weight_kg": .decimal(profile.startWeightKg),
                "user_profile_target_weight_kg": .decimal(profile.targetWeightKg),
                "user_profile_birth_year": optionalInteger(profile.birthYear),
                "user_profile_units_system": .text(profile.unitsSystem.rawValue),
                "user_profile_protein_target_g": .decimal(profile.proteinTargetG),
                "user_profile_calorie_target": optionalDecimal(profile.calorieTarget),
                "user_profile_carb_target_g": optionalDecimal(profile.carbTargetG),
                "user_profile_fat_target_g": optionalDecimal(profile.fatTargetG),
                "user_profile_program_start_date": .timestamp(profile.programStartDate),
                "user_profile_weekly_workout_target": .integer(
                    Int64(profile.weeklyWorkoutTarget)
                ),
            ]
        )
    }

    func exportRow(
        _ program: Program,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .program,
            id: program.id,
            createdAt: program.createdAt,
            updatedAt: program.updatedAt,
            primaryTimestamp: program.createdAt,
            configScope: configScope,
            values: [
                "program_name": .text(program.name),
                "program_description_text": .text(program.descriptionText),
                "program_is_active": .boolean(program.isActive),
            ]
        )
    }

    func exportRow(
        _ phase: ProgramPhase,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .programPhase,
            id: phase.id,
            createdAt: phase.createdAt,
            updatedAt: phase.updatedAt,
            primaryTimestamp: phase.createdAt,
            configScope: configScope,
            values: [
                "program_phase_name": .text(phase.name),
                "program_phase_order_index": .integer(Int64(phase.orderIndex)),
                "program_phase_month_start": .integer(Int64(phase.monthStart)),
                "program_phase_month_end": .integer(Int64(phase.monthEnd)),
                "program_phase_training_focus": .text(phase.trainingFocus),
                "program_phase_nutrition_focus": .text(phase.nutritionFocus),
                "program_phase_milestone": .text(phase.milestone),
                "program_phase_entry_criteria": .text(phase.entryCriteria),
                "program_phase_program_id": optionalUUID(phase.program?.id),
            ]
        )
    }

    func exportRow(
        _ state: ProgramState,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .programState,
            id: state.id,
            createdAt: state.createdAt,
            updatedAt: state.updatedAt,
            primaryTimestamp: state.phaseStartedAt,
            configScope: configScope,
            values: [
                "program_state_program_id": .uuid(state.programId),
                "program_state_current_phase_id": .uuid(state.currentPhaseId),
                "program_state_phase_started_at": .timestamp(state.phaseStartedAt),
                "program_state_training_week_index": .integer(
                    Int64(state.trainingWeekIndex)
                ),
                "program_state_deload_status": .text(state.deloadStatus.rawValue),
                "program_state_deload_reason": optionalText(state.deloadReason?.rawValue),
                "program_state_deload_updated_at": optionalTimestamp(state.deloadUpdatedAt),
                "program_state_last_deload_skipped_at": optionalTimestamp(
                    state.lastDeloadSkippedAt
                ),
                "program_state_last_deload_action": optionalText(
                    state.lastDeloadAction?.rawValue
                ),
            ]
        )
    }

    func exportRow(
        _ day: WorkoutDayTemplate,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .workoutDayTemplate,
            id: day.id,
            createdAt: day.createdAt,
            updatedAt: day.updatedAt,
            primaryTimestamp: day.createdAt,
            configScope: configScope,
            values: [
                "workout_day_template_name": .text(day.name),
                "workout_day_template_order_index": .integer(Int64(day.orderIndex)),
                "workout_day_template_focus": .text(day.focus),
                "workout_day_template_program_id": optionalUUID(day.program?.id),
            ]
        )
    }

    func exportRow(
        _ exercise: ExerciseTemplate,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .exerciseTemplate,
            id: exercise.id,
            createdAt: exercise.createdAt,
            updatedAt: exercise.updatedAt,
            primaryTimestamp: exercise.createdAt,
            configScope: configScope,
            values: [
                "exercise_template_name": .text(exercise.name),
                "exercise_template_order_index": .integer(Int64(exercise.orderIndex)),
                "exercise_template_target_sets": .integer(Int64(exercise.targetSets)),
                "exercise_template_rep_low": optionalInteger(exercise.repLow),
                "exercise_template_rep_high": optionalInteger(exercise.repHigh),
                "exercise_template_rir_low": .integer(Int64(exercise.rirLow)),
                "exercise_template_rir_high": .integer(Int64(exercise.rirHigh)),
                "exercise_template_category": .text(exercise.category.rawValue),
                "exercise_template_allow_failure": .boolean(exercise.allowFailure),
                "exercise_template_cues": .text(exercise.cues),
                "exercise_template_safety_note": optionalText(exercise.safetyNote),
                "exercise_template_starting_weight_kg": optionalDecimal(
                    exercise.startingWeightKg
                ),
                "exercise_template_progression_rule": .text(
                    exercise.progressionRule.rawValue
                ),
                "exercise_template_measurement_kind": .text(
                    exercise.measurementKind.rawValue
                ),
                "exercise_template_superset_group_id": optionalUUID(
                    exercise.supersetGroupId
                ),
                "exercise_template_superset_order": optionalInteger(exercise.supersetOrder),
                "exercise_template_workout_day_template_id": optionalUUID(
                    exercise.workoutDayTemplate?.id
                ),
            ]
        )
    }

    func exportRow(
        _ warmup: WarmupItem,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .warmupItem,
            id: warmup.id,
            createdAt: warmup.createdAt,
            updatedAt: warmup.updatedAt,
            primaryTimestamp: warmup.createdAt,
            configScope: configScope,
            values: [
                "warmup_item_phase": .text(warmup.phase.rawValue),
                "warmup_item_movement": .text(warmup.movement),
                "warmup_item_dose": .text(warmup.dose),
                "warmup_item_order_index": .integer(Int64(warmup.orderIndex)),
                "warmup_item_workout_day_template_id": optionalUUID(
                    warmup.workoutDayTemplate?.id
                ),
            ]
        )
    }

    func exportRow(
        _ cooldown: CooldownItem,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .cooldownItem,
            id: cooldown.id,
            createdAt: cooldown.createdAt,
            updatedAt: cooldown.updatedAt,
            primaryTimestamp: cooldown.createdAt,
            configScope: configScope,
            values: [
                "cooldown_item_movement": .text(cooldown.movement),
                "cooldown_item_dose": .text(cooldown.dose),
                "cooldown_item_note": optionalText(cooldown.note),
                "cooldown_item_order_index": .integer(Int64(cooldown.orderIndex)),
                "cooldown_item_workout_day_template_id": optionalUUID(
                    cooldown.workoutDayTemplate?.id
                ),
            ]
        )
    }

    func exportRow(_ session: WorkoutSession) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .workoutSession,
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            primaryTimestamp: session.date,
            configScope: nil,
            values: [
                "workout_session_date": .timestamp(session.date),
                "workout_session_status": .text(session.status.rawValue),
                "workout_session_workout_day_template_id": .uuid(
                    session.workoutDayTemplateId
                ),
                "workout_session_perceived_recovery": optionalInteger(
                    session.perceivedRecovery
                ),
                "workout_session_note": optionalText(session.note),
                "workout_session_ohp_symptom_response": .text(
                    session.ohpSymptomResponse.rawValue
                ),
                "workout_session_ohp_symptom_checked_at": optionalTimestamp(
                    session.ohpSymptomCheckedAt
                ),
            ]
        )
    }

    func exportRow(_ set: SetLog) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .setLog,
            id: set.id,
            createdAt: set.createdAt,
            updatedAt: set.updatedAt,
            primaryTimestamp: set.completedAt,
            configScope: nil,
            values: [
                "set_log_exercise_template_id": .uuid(set.exerciseTemplateId),
                "set_log_set_index": .integer(Int64(set.setIndex)),
                "set_log_weight_kg": optionalDecimal(set.weightKg),
                "set_log_reps": optionalInteger(set.reps),
                "set_log_duration_sec": optionalInteger(set.durationSec),
                "set_log_distance_steps": optionalInteger(set.distanceSteps),
                "set_log_performed_variant": optionalText(set.performedVariant),
                "set_log_rir": optionalInteger(set.rir),
                "set_log_is_warmup_set": .boolean(set.isWarmupSet),
                "set_log_completed_at": .timestamp(set.completedAt),
                "set_log_workout_session_id": optionalUUID(set.workoutSession?.id),
            ]
        )
    }

    func exportRow(_ progress: WorkoutSessionProgress) throws -> ExportRowV1 {
        let warmupIDs: Set<UUID>
        do {
            warmupIDs = try WorkoutSessionProgressCodec.decode(progress.completedWarmupItemIdsData)
        } catch let error as WorkoutSessionProgressCodecError {
            throw ReportsExportRepositoryError.invalidWorkoutSessionProgress(
                id: progress.id,
                field: .completedWarmupItemIDs,
                reason: error
            )
        }
        let cooldownIDs: Set<UUID>
        do {
            cooldownIDs = try WorkoutSessionProgressCodec.decode(progress.completedCooldownItemIdsData)
        } catch let error as WorkoutSessionProgressCodecError {
            throw ReportsExportRepositoryError.invalidWorkoutSessionProgress(
                id: progress.id,
                field: .completedCooldownItemIDs,
                reason: error
            )
        }
        return try makeExportRow(
            recordType: .workoutSessionProgress,
            id: progress.id,
            createdAt: progress.createdAt,
            updatedAt: progress.updatedAt,
            primaryTimestamp: progress.updatedAt,
            configScope: nil,
            values: [
                "workout_session_progress_workout_session_id": .uuid(
                    progress.workoutSessionId
                ),
                "workout_session_progress_stage": .text(progress.stage.rawValue),
                "workout_session_progress_current_exercise_template_id": optionalUUID(
                    progress.currentExerciseTemplateId
                ),
                "workout_session_progress_completed_warmup_item_ids_json": .text(
                    canonicalUUIDArray(warmupIDs)
                ),
                "workout_session_progress_completed_cooldown_item_ids_json": .text(
                    canonicalUUIDArray(cooldownIDs)
                ),
                "workout_session_progress_warmup_disposition": .text(
                    progress.warmupDisposition.rawValue
                ),
                "workout_session_progress_cooldown_disposition": .text(
                    progress.cooldownDisposition.rawValue
                ),
            ]
        )
    }
}

@MainActor
private extension SwiftDataReportsRepository {
    func exportRow(
        _ food: Food,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .food,
            id: food.id,
            createdAt: food.createdAt,
            updatedAt: food.updatedAt,
            primaryTimestamp: food.createdAt,
            configScope: configScope,
            values: [
                "food_name": .text(food.name),
                "food_brand": optionalText(food.brand),
                "food_serving_size": .decimal(food.servingSize),
                "food_serving_unit": .text(food.servingUnit),
                "food_calories_per_serving": .decimal(food.caloriesPerServing),
                "food_protein_g": .decimal(food.proteinG),
                "food_carb_g": .decimal(food.carbG),
                "food_fat_g": .decimal(food.fatG),
                "food_fiber_g": optionalDecimal(food.fiberG),
                "food_source": .text(food.source.rawValue),
            ]
        )
    }

    func exportRow(
        _ recipe: Recipe,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .recipe,
            id: recipe.id,
            createdAt: recipe.createdAt,
            updatedAt: recipe.updatedAt,
            primaryTimestamp: recipe.createdAt,
            configScope: configScope,
            values: [
                "recipe_name": .text(recipe.name),
                "recipe_category": .text(recipe.category.kind.rawValue),
                "recipe_category_custom_name": optionalText(recipe.category.customName),
                "recipe_servings": .decimal(recipe.servings),
                "recipe_is_direct_macros": .boolean(recipe.isDirectMacros),
                "recipe_calories_total": .decimal(recipe.caloriesTotal),
                "recipe_protein_total_g": .decimal(recipe.proteinTotalG),
                "recipe_carb_total_g": .decimal(recipe.carbTotalG),
                "recipe_fat_total_g": .decimal(recipe.fatTotalG),
                "recipe_note": optionalText(recipe.note),
            ]
        )
    }

    func exportRow(_ day: DailyNutritionLog) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .dailyNutritionLog,
            id: day.id,
            createdAt: day.createdAt,
            updatedAt: day.updatedAt,
            primaryTimestamp: day.date,
            configScope: nil,
            values: ["daily_nutrition_log_date": .timestamp(day.date)]
        )
    }

    func exportRow(_ meal: MealEntry) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .mealEntry,
            id: meal.id,
            createdAt: meal.createdAt,
            updatedAt: meal.updatedAt,
            primaryTimestamp: meal.loggedAt,
            configScope: nil,
            values: [
                "meal_entry_category": .text(meal.category.kind.rawValue),
                "meal_entry_category_custom_name": optionalText(meal.category.customName),
                "meal_entry_recipe_id": optionalUUID(meal.recipeId),
                "meal_entry_food_id": optionalUUID(meal.foodId),
                "meal_entry_adhoc_name": optionalText(meal.adhocName),
                "meal_entry_quantity": .decimal(meal.quantity),
                "meal_entry_calories_resolved": .decimal(meal.caloriesResolved),
                "meal_entry_protein_resolved": .decimal(meal.proteinResolved),
                "meal_entry_carb_resolved": .decimal(meal.carbResolved),
                "meal_entry_fat_resolved": .decimal(meal.fatResolved),
                "meal_entry_logged_at": .timestamp(meal.loggedAt),
                "meal_entry_daily_nutrition_log_id": optionalUUID(
                    meal.dailyNutritionLog?.id
                ),
            ]
        )
    }

    func exportRow(_ metric: BodyMetric) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .bodyMetric,
            id: metric.id,
            createdAt: metric.createdAt,
            updatedAt: metric.updatedAt,
            primaryTimestamp: metric.date,
            configScope: nil,
            values: [
                "body_metric_date": .timestamp(metric.date),
                "body_metric_type": .text(metric.type.rawValue),
                "body_metric_custom_name": optionalText(metric.customName),
                "body_metric_value": .decimal(metric.value),
                "body_metric_unit": .text(metric.unit),
            ]
        )
    }

    func exportRow(_ metric: PostureMetric) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .postureMetric,
            id: metric.id,
            createdAt: metric.createdAt,
            updatedAt: metric.updatedAt,
            primaryTimestamp: metric.date,
            configScope: nil,
            values: [
                "posture_metric_date": .timestamp(metric.date),
                "posture_metric_wall_test_pass": optionalBoolean(metric.wallTestPass),
                "posture_metric_symptom_score": optionalInteger(metric.symptomScore),
                "posture_metric_region": optionalText(metric.region),
                "posture_metric_note": optionalText(metric.note),
            ]
        )
    }

    func exportRow(_ sleep: SleepLog) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .sleepLog,
            id: sleep.id,
            createdAt: sleep.createdAt,
            updatedAt: sleep.updatedAt,
            primaryTimestamp: sleep.date,
            configScope: nil,
            values: [
                "sleep_log_date": .timestamp(sleep.date),
                "sleep_log_duration_hours": .decimal(sleep.durationHours),
                "sleep_log_quality": .integer(Int64(sleep.quality)),
                "sleep_log_note": optionalText(sleep.note),
            ]
        )
    }

    func exportRow(_ mood: MoodLog) throws -> ExportRowV1 {
        let tagsColumn = "mood_log_mood_tags_json"
        return try makeExportRow(
            recordType: .moodLog,
            id: mood.id,
            createdAt: mood.createdAt,
            updatedAt: mood.updatedAt,
            primaryTimestamp: mood.date,
            configScope: nil,
            values: [
                "mood_log_date": .timestamp(mood.date),
                "mood_log_mood_score": optionalInteger(mood.moodScore),
                tagsColumn: .text(try canonicalStringArray(
                    mood.moodTags,
                    recordType: .moodLog,
                    id: mood.id,
                    column: tagsColumn
                )),
                "mood_log_energy": optionalInteger(mood.energy),
                "mood_log_note": optionalText(mood.note),
            ]
        )
    }

    func exportRow(_ reminder: HealthCheckReminder) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .healthCheckReminder,
            id: reminder.id,
            createdAt: reminder.createdAt,
            updatedAt: reminder.updatedAt,
            primaryTimestamp: reminder.dueDate,
            configScope: nil,
            values: [
                "health_check_reminder_name": .text(reminder.name),
                "health_check_reminder_due_date": .timestamp(reminder.dueDate),
                "health_check_reminder_recurrence": .text(reminder.recurrence.rawValue),
                "health_check_reminder_status": .text(reminder.status.rawValue),
            ]
        )
    }

    func exportRow(_ result: BloodworkResult) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .bloodworkResult,
            id: result.id,
            createdAt: result.createdAt,
            updatedAt: result.updatedAt,
            primaryTimestamp: result.date,
            configScope: nil,
            values: [
                "bloodwork_result_date": .timestamp(result.date),
                "bloodwork_result_marker": .text(result.marker),
                "bloodwork_result_value": .decimal(result.value),
                "bloodwork_result_unit": .text(result.unit),
                "bloodwork_result_note": optionalText(result.note),
            ]
        )
    }

    func exportRow(_ photo: ProgressPhoto) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .progressPhoto,
            id: photo.id,
            createdAt: photo.createdAt,
            updatedAt: photo.updatedAt,
            primaryTimestamp: photo.date,
            configScope: nil,
            values: [
                "progress_photo_date": .timestamp(photo.date),
                "progress_photo_image_available": .boolean(!photo.imageRef.isEmpty),
                "progress_photo_pose": .text(photo.pose.rawValue),
                "progress_photo_note": optionalText(photo.note),
            ]
        )
    }

    func exportRow(
        _ reminder: AppReminder,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .appReminder,
            id: reminder.id,
            createdAt: reminder.createdAt,
            updatedAt: reminder.updatedAt,
            primaryTimestamp: reminder.createdAt,
            configScope: configScope,
            values: [
                "app_reminder_type": .text(reminder.type.rawValue),
                "app_reminder_schedule": .text(reminder.schedule),
                "app_reminder_message": .text(reminder.message),
                "app_reminder_is_enabled": .boolean(reminder.isEnabled),
            ]
        )
    }

    func exportRow(
        _ setting: AppSetting,
        configScope: ExportConfigScopeV1
    ) throws -> ExportRowV1 {
        try makeExportRow(
            recordType: .appSetting,
            id: setting.id,
            createdAt: setting.createdAt,
            updatedAt: setting.updatedAt,
            primaryTimestamp: setting.createdAt,
            configScope: configScope,
            values: [
                "app_setting_key": .text(setting.key),
                "app_setting_value": .text(setting.value),
            ]
        )
    }
}
