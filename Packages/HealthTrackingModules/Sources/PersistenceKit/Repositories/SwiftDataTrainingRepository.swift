import CoreModels
import Foundation
import SwiftData
import TrainingKit

public enum TrainingRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateUserProfiles(count: Int)
    case duplicateActivePrograms(count: Int)
    case duplicateProgramStates(programID: UUID, count: Int)
}

@MainActor
public final class SwiftDataTrainingRepository: TrainingRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchUserProfile() async throws -> UserProfile? {
        let profiles = try modelContext.fetch(
            FetchDescriptor<UserProfile>(
                sortBy: [SortDescriptor(\UserProfile.updatedAt, order: .reverse)]
            )
        )

        guard profiles.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateUserProfiles(count: profiles.count)
        }
        return profiles.first
    }

    public func fetchActiveProgram() async throws -> Program? {
        let programs = Self.sortActivePrograms(
            try modelContext.fetch(
                FetchDescriptor<Program>(
                    predicate: #Predicate { $0.isActive },
                    sortBy: [SortDescriptor(\Program.updatedAt, order: .reverse)]
                )
            )
        )

        guard programs.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateActivePrograms(count: programs.count)
        }
        return programs.first
    }

    static func sortActivePrograms(_ programs: [Program]) -> [Program] {
        programs.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func fetchProgramPhases(programID: UUID) async throws -> [ProgramPhase] {
        let phases = try modelContext.fetch(
            FetchDescriptor<ProgramPhase>(
                sortBy: [SortDescriptor(\ProgramPhase.orderIndex, order: .forward)]
            )
        )

        return phases
            .filter { $0.program?.id == programID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func fetchWorkoutDays(programID: UUID) async throws -> [WorkoutDayTemplate] {
        let days = try modelContext.fetch(
            FetchDescriptor<WorkoutDayTemplate>(
                sortBy: [SortDescriptor(\WorkoutDayTemplate.orderIndex, order: .forward)]
            )
        )

        return days
            .filter { $0.program?.id == programID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func fetchExerciseTemplates(workoutDayID: UUID) async throws -> [ExerciseTemplate] {
        let exercises = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())

        return exercises
            .filter { $0.workoutDayTemplate?.id == workoutDayID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func fetchWarmupItems(workoutDayID: UUID) async throws -> [WarmupItem] {
        let warmups = try modelContext.fetch(FetchDescriptor<WarmupItem>())

        return warmups
            .filter { $0.workoutDayTemplate?.id == workoutDayID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func fetchCooldownItems(workoutDayID: UUID) async throws -> [CooldownItem] {
        let cooldowns = try modelContext.fetch(FetchDescriptor<CooldownItem>())

        return cooldowns
            .filter { $0.workoutDayTemplate?.id == workoutDayID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func fetchHealthCheckReminders() async throws -> [HealthCheckReminder] {
        let reminders = try modelContext.fetch(FetchDescriptor<HealthCheckReminder>())

        return reminders.sorted { lhs, rhs in
            if lhs.dueDate != rhs.dueDate {
                return lhs.dueDate < rhs.dueDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func fetchProgramState(programID: UUID) async throws -> ProgramState? {
        let states = try modelContext.fetch(FetchDescriptor<ProgramState>())
            .filter { $0.programId == programID }

        guard states.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateProgramStates(
                programID: programID,
                count: states.count
            )
        }
        return states.first
    }
}
