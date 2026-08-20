import CoreModels
import Foundation
import SwiftData
import TrainingKit

public enum TrainingRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateUserProfiles(count: Int)
    case duplicateActivePrograms(count: Int)
    case duplicateProgramStates(programID: UUID, count: Int)
    case missingWorkoutSession(id: UUID)
    case duplicateWorkoutSessions(id: UUID, count: Int)
    case missingExerciseTemplate(id: UUID)
    case duplicateExerciseTemplates(id: UUID, count: Int)
    case duplicateSetIndex(
        workoutSessionID: UUID,
        exerciseTemplateID: UUID,
        setIndex: Int
    )
    case transactionDidNotProduceSetSnapshot
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

    public func saveSet(_ request: SetLogSaveRequest) async throws -> SetLogSnapshot {
        var savedSnapshot: SetLogSnapshot?

        try modelContext.transaction {
            let matchingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .filter { $0.id == request.workoutSessionID }
            guard !matchingSessions.isEmpty else {
                throw TrainingRepositoryIntegrityError.missingWorkoutSession(
                    id: request.workoutSessionID
                )
            }
            guard matchingSessions.count == 1, let session = matchingSessions.first else {
                throw TrainingRepositoryIntegrityError.duplicateWorkoutSessions(
                    id: request.workoutSessionID,
                    count: matchingSessions.count
                )
            }

            let matchingExercises = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
                .filter { $0.id == request.exerciseTemplateID }
            guard !matchingExercises.isEmpty else {
                throw TrainingRepositoryIntegrityError.missingExerciseTemplate(
                    id: request.exerciseTemplateID
                )
            }
            guard matchingExercises.count == 1, let exercise = matchingExercises.first else {
                throw TrainingRepositoryIntegrityError.duplicateExerciseTemplates(
                    id: request.exerciseTemplateID,
                    count: matchingExercises.count
                )
            }

            try SetMeasurementValidator.validate(
                request.measurement,
                for: exercise.measurementKind
            )

            let duplicateCount = try modelContext.fetch(FetchDescriptor<SetLog>())
                .filter {
                    $0.workoutSession?.id == request.workoutSessionID &&
                        $0.exerciseTemplateId == request.exerciseTemplateID &&
                        $0.setIndex == request.setIndex
                }
                .count
            guard duplicateCount == 0 else {
                throw TrainingRepositoryIntegrityError.duplicateSetIndex(
                    workoutSessionID: request.workoutSessionID,
                    exerciseTemplateID: request.exerciseTemplateID,
                    setIndex: request.setIndex
                )
            }

            let setLog = SetLog(
                id: request.id,
                createdAt: request.completedAt,
                updatedAt: request.completedAt,
                exerciseTemplateId: request.exerciseTemplateID,
                setIndex: request.setIndex,
                weightKg: request.measurement.weightKg,
                reps: request.measurement.reps,
                durationSec: request.measurement.durationSec,
                distanceSteps: request.measurement.distanceSteps,
                performedVariant: request.measurement.performedVariant,
                rir: request.measurement.rir,
                isWarmupSet: request.isWarmupSet,
                completedAt: request.completedAt,
                workoutSession: session
            )
            modelContext.insert(setLog)
            try modelContext.save()
            savedSnapshot = Self.snapshot(setLog, workoutSessionID: request.workoutSessionID)
        }

        guard let savedSnapshot else {
            throw TrainingRepositoryIntegrityError.transactionDidNotProduceSetSnapshot
        }
        return savedSnapshot
    }

    private static func snapshot(
        _ setLog: SetLog,
        workoutSessionID: UUID
    ) -> SetLogSnapshot {
        SetLogSnapshot(
            id: setLog.id,
            createdAt: setLog.createdAt,
            updatedAt: setLog.updatedAt,
            workoutSessionID: workoutSessionID,
            exerciseTemplateID: setLog.exerciseTemplateId,
            setIndex: setLog.setIndex,
            measurement: setLog.measurementInput,
            isWarmupSet: setLog.isWarmupSet,
            completedAt: setLog.completedAt
        )
    }
}
