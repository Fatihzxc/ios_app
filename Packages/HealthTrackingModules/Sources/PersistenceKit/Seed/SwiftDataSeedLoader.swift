import CoreModels
import Foundation
import SwiftData

@MainActor
public final class SwiftDataSeedLoader: SeedLoading {
    private static let markerKey = "seed.catalog.version"
    private static let markerValue = "1"

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

            let payload = M0SeedCatalog.make(installedAt: installedAt)
            try TrainingModelValidator.validateWeeklyWorkoutTarget(payload.profile.weeklyWorkoutTarget)
            _ = try profile(for: payload.profile)
            let program = try program(for: payload.program)

            for phasePayload in payload.phases {
                let phase = try phase(for: phasePayload)
                if phase.program?.id != program.id {
                    phase.program = program
                }
            }

            for dayPayload in payload.workoutDays {
                let day = try workoutDay(for: dayPayload)
                if day.program?.id != program.id {
                    day.program = program
                }
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

    private func profile(for payload: M0SeedPayload.Profile) throws -> UserProfile {
        if let existing = try modelContext.fetch(FetchDescriptor<UserProfile>()).first(where: { $0.id == payload.id }) {
            return existing
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

    private func program(for payload: M0SeedPayload.Program) throws -> Program {
        if let existing = try modelContext.fetch(FetchDescriptor<Program>()).first(where: { $0.id == payload.id }) {
            return existing
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

    private func phase(for payload: M0SeedPayload.Phase) throws -> ProgramPhase {
        if let existing = try modelContext.fetch(FetchDescriptor<ProgramPhase>()).first(where: { $0.id == payload.id }) {
            return existing
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

    private func workoutDay(for payload: M0SeedPayload.WorkoutDay) throws -> WorkoutDayTemplate {
        if let existing = try modelContext.fetch(FetchDescriptor<WorkoutDayTemplate>()).first(where: { $0.id == payload.id }) {
            return existing
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
}
