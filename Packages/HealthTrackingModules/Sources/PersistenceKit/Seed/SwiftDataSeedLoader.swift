import CoreModels
import Foundation
import SwiftData

@MainActor
public final class SwiftDataSeedLoader: SeedLoading {
    private static let markerKey = "seed.catalog.version"
    private static let markerValue = "2"

    private let modelContext: ModelContext
    private let saveOperation: @MainActor () throws -> Void
    private let rollbackOperation: @MainActor () -> Void

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        saveOperation = { try modelContext.save() }
        rollbackOperation = { modelContext.rollback() }
    }

    init(
        modelContext: ModelContext,
        save: @escaping @MainActor () throws -> Void,
        rollback: @escaping @MainActor () -> Void
    ) {
        self.modelContext = modelContext
        saveOperation = save
        rollbackOperation = rollback
    }

    public func seedIfNeeded(installedAt: Date) throws {
        do {
            let settings = try modelContext.fetch(FetchDescriptor<AppSetting>())
            let markers = settings.filter { $0.key == Self.markerKey }
            guard markers.count <= 1 else {
                throw SeedLoadingError.duplicateMarkers(count: markers.count)
            }
            guard !markers.contains(where: Self.isValidMarker) else {
                return
            }

            let isVersionOneUpgrade = markers.first?.value == "1"
            let payload = M0SeedCatalog.make(installedAt: installedAt)
            try TrainingModelValidator.validateWeeklyWorkoutTarget(payload.profile.weeklyWorkoutTarget)

            var foundationProfile: UserProfile?
            var foundationProgram: Program?
            var phasesByID: [UUID: ProgramPhase] = [:]
            var workoutDaysByID: [UUID: WorkoutDayTemplate] = [:]

            if isVersionOneUpgrade {
                foundationProfile = try modelContext.fetch(FetchDescriptor<UserProfile>())
                    .first(where: { $0.id == payload.profile.id })
                foundationProgram = try modelContext.fetch(FetchDescriptor<Program>())
                    .first(where: { $0.id == payload.program.id })

                let phaseIDs = Set(payload.phases.map(\.id))
                for phase in try modelContext.fetch(FetchDescriptor<ProgramPhase>())
                where phaseIDs.contains(phase.id) {
                    phasesByID[phase.id] = phase
                }

                let workoutDayIDs = Set(payload.workoutDays.map(\.id))
                for day in try modelContext.fetch(FetchDescriptor<WorkoutDayTemplate>())
                where workoutDayIDs.contains(day.id) {
                    workoutDaysByID[day.id] = day
                }
            } else {
                let existingProfiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
                let existingPrograms = try modelContext.fetch(FetchDescriptor<Program>())
                let existingPhases = try modelContext.fetch(FetchDescriptor<ProgramPhase>())
                let existingWorkoutDays = try modelContext.fetch(
                    FetchDescriptor<WorkoutDayTemplate>()
                )
                let seededProfile = profile(for: payload.profile, existing: existingProfiles)
                let seededProgram = program(for: payload.program, existing: existingPrograms)
                foundationProfile = seededProfile
                foundationProgram = seededProgram

                for phasePayload in payload.phases {
                    let phase = phase(for: phasePayload, existing: existingPhases)
                    if phase.program?.id != seededProgram.id {
                        phase.program = seededProgram
                    }
                    phasesByID[phase.id] = phase
                }

                for dayPayload in payload.workoutDays {
                    let day = workoutDay(for: dayPayload, existing: existingWorkoutDays)
                    if day.program?.id != seededProgram.id {
                        day.program = seededProgram
                    }
                    workoutDaysByID[day.id] = day
                }
            }

            let m1Payload = M1SeedCatalog.make(
                installedAt: foundationProfile?.createdAt ?? installedAt,
                programStartDate: foundationProfile?.programStartDate ?? installedAt
            )
            try TrainingModelValidator.validateTrainingWeekIndex(
                m1Payload.programState.trainingWeekIndex
            )

            let existingExercises = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
            for exercisePayload in m1Payload.exercises {
                guard let day = workoutDaysByID[exercisePayload.workoutDayID] else {
                    guard !isVersionOneUpgrade else { continue }
                    throw SeedLoadingError.missingRequiredWorkoutDay(
                        id: exercisePayload.workoutDayID
                    )
                }
                let exercise = exercise(for: exercisePayload, existing: existingExercises)
                if exercise.workoutDayTemplate?.id != day.id {
                    exercise.workoutDayTemplate = day
                }
            }

            let existingWarmups = try modelContext.fetch(FetchDescriptor<WarmupItem>())
            for warmupPayload in m1Payload.warmups {
                guard let day = workoutDaysByID[warmupPayload.workoutDayID] else {
                    guard !isVersionOneUpgrade else { continue }
                    throw SeedLoadingError.missingRequiredWorkoutDay(
                        id: warmupPayload.workoutDayID
                    )
                }
                let warmup = warmup(for: warmupPayload, existing: existingWarmups)
                if warmup.workoutDayTemplate?.id != day.id {
                    warmup.workoutDayTemplate = day
                }
            }

            let existingCooldowns = try modelContext.fetch(FetchDescriptor<CooldownItem>())
            for cooldownPayload in m1Payload.cooldowns {
                guard let day = workoutDaysByID[cooldownPayload.workoutDayID] else {
                    guard !isVersionOneUpgrade else { continue }
                    throw SeedLoadingError.missingRequiredWorkoutDay(
                        id: cooldownPayload.workoutDayID
                    )
                }
                let cooldown = cooldown(for: cooldownPayload, existing: existingCooldowns)
                if cooldown.workoutDayTemplate?.id != day.id {
                    cooldown.workoutDayTemplate = day
                }
            }

            let existingReminders = try modelContext.fetch(FetchDescriptor<HealthCheckReminder>())
            for reminderPayload in m1Payload.reminders {
                _ = reminder(for: reminderPayload, existing: existingReminders)
            }

            let canCreateProgramState = !isVersionOneUpgrade
                || (
                    foundationProgram?.id == m1Payload.programState.programID
                        && phasesByID[m1Payload.programState.currentPhaseID]?.program?.id
                            == m1Payload.programState.programID
                )
            if canCreateProgramState {
                let existingProgramStates = try modelContext.fetch(FetchDescriptor<ProgramState>())
                _ = programState(for: m1Payload.programState, existing: existingProgramStates)
            }

            if let existingMarker = markers.first {
                existingMarker.value = Self.markerValue
            } else {
                modelContext.insert(AppSetting(key: Self.markerKey, value: Self.markerValue))
            }
            try saveOperation()
        } catch let error as SeedLoadingError {
            rollbackOperation()
            throw error
        } catch {
            rollbackOperation()
            throw SeedLoadingError.saveFailed
        }
    }

    private static func isValidMarker(_ setting: AppSetting) -> Bool {
        setting.key == markerKey && setting.value == markerValue
    }

    private func profile(
        for payload: M0SeedPayload.Profile,
        existing: [UserProfile]
    ) -> UserProfile {
        if let match = existing.first(where: { $0.id == payload.id }) {
            return match
        }

        let profile = UserProfile(
            id: payload.id,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            displayName: payload.displayName,
            heightCm: payload.heightCm,
            startWeightKg: payload.startWeightKg,
            targetWeightKg: payload.targetWeightKg,
            unitsSystem: payload.unitsSystem,
            proteinTargetG: payload.proteinTargetG,
            calorieTarget: payload.calorieTarget,
            carbTargetG: payload.carbTargetG,
            fatTargetG: payload.fatTargetG,
            programStartDate: payload.programStartDate,
            weeklyWorkoutTarget: payload.weeklyWorkoutTarget
        )
        modelContext.insert(profile)
        return profile
    }

    private func program(
        for payload: M0SeedPayload.Program,
        existing: [Program]
    ) -> Program {
        if let match = existing.first(where: { $0.id == payload.id }) {
            return match
        }

        let program = Program(
            id: payload.id,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            name: payload.name,
            descriptionText: payload.descriptionText,
            isActive: payload.isActive
        )
        modelContext.insert(program)
        return program
    }

    private func phase(
        for payload: M0SeedPayload.Phase,
        existing: [ProgramPhase]
    ) -> ProgramPhase {
        if let match = existing.first(where: { $0.id == payload.id }) {
            return match
        }

        let phase = ProgramPhase(
            id: payload.id,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            name: payload.name,
            orderIndex: payload.orderIndex,
            monthStart: payload.monthStart,
            monthEnd: payload.monthEnd,
            trainingFocus: payload.trainingFocus,
            nutritionFocus: payload.nutritionFocus,
            milestone: payload.milestone,
            entryCriteria: payload.entryCriteria
        )
        modelContext.insert(phase)
        return phase
    }

    private func workoutDay(
        for payload: M0SeedPayload.WorkoutDay,
        existing: [WorkoutDayTemplate]
    ) -> WorkoutDayTemplate {
        if let match = existing.first(where: { $0.id == payload.id }) {
            return match
        }

        let day = WorkoutDayTemplate(
            id: payload.id,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            name: payload.name,
            orderIndex: payload.orderIndex,
            focus: payload.focus
        )
        modelContext.insert(day)
        return day
    }

    private func exercise(
        for payload: M1SeedPayload.Exercise,
        existing: [ExerciseTemplate]
    ) -> ExerciseTemplate {
        if let match = existing.first(where: { $0.id == payload.id }) {
            return match
        }

        let exercise = ExerciseTemplate(
            id: payload.id,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            name: payload.name,
            orderIndex: payload.orderIndex,
            targetSets: payload.targetSets,
            repLow: payload.repLow,
            repHigh: payload.repHigh,
            rirLow: payload.rirLow,
            rirHigh: payload.rirHigh,
            category: payload.category,
            allowFailure: payload.allowFailure,
            cues: payload.cues,
            safetyNote: payload.safetyNote,
            startingWeightKg: payload.startingWeightKg,
            progressionRule: payload.progressionRule,
            measurementKind: payload.measurementKind,
            supersetGroupId: payload.supersetGroupID,
            supersetOrder: payload.supersetOrder
        )
        modelContext.insert(exercise)
        return exercise
    }

    private func warmup(
        for payload: M1SeedPayload.Warmup,
        existing: [WarmupItem]
    ) -> WarmupItem {
        if let match = existing.first(where: { $0.id == payload.id }) {
            return match
        }

        let warmup = WarmupItem(
            id: payload.id,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            phase: payload.phase,
            movement: payload.movement,
            dose: payload.dose,
            orderIndex: payload.orderIndex
        )
        modelContext.insert(warmup)
        return warmup
    }

    private func cooldown(
        for payload: M1SeedPayload.Cooldown,
        existing: [CooldownItem]
    ) -> CooldownItem {
        if let match = existing.first(where: { $0.id == payload.id }) {
            return match
        }

        let cooldown = CooldownItem(
            id: payload.id,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            movement: payload.movement,
            dose: payload.dose,
            note: payload.note,
            orderIndex: payload.orderIndex
        )
        modelContext.insert(cooldown)
        return cooldown
    }

    private func reminder(
        for payload: M1SeedPayload.Reminder,
        existing: [HealthCheckReminder]
    ) -> HealthCheckReminder {
        if let match = existing.first(where: { $0.id == payload.id }) {
            return match
        }

        let reminder = HealthCheckReminder(
            id: payload.id,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            name: payload.name,
            dueDate: payload.dueDate,
            recurrence: payload.recurrence,
            status: payload.status
        )
        modelContext.insert(reminder)
        return reminder
    }

    private func programState(
        for payload: M1SeedPayload.State,
        existing: [ProgramState]
    ) -> ProgramState {
        if let match = existing.first(where: { $0.id == payload.id }) {
            return match
        }

        let state = ProgramState(
            id: payload.id,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            programId: payload.programID,
            currentPhaseId: payload.currentPhaseID,
            phaseStartedAt: payload.phaseStartedAt,
            trainingWeekIndex: payload.trainingWeekIndex,
            deloadStatus: payload.deloadStatus,
            deloadReason: payload.deloadReason,
            deloadUpdatedAt: payload.deloadUpdatedAt,
            lastDeloadSkippedAt: payload.lastDeloadSkippedAt,
            lastDeloadAction: payload.lastDeloadAction
        )
        modelContext.insert(state)
        return state
    }
}
