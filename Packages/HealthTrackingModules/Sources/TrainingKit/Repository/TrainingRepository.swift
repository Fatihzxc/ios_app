import CoreModels
import Foundation

@MainActor
public protocol TrainingRepository: AnyObject {
    func fetchUserProfile() async throws -> UserProfile?
    func fetchActiveProgram() async throws -> Program?
    func fetchProgramPhases(programID: UUID) async throws -> [ProgramPhase]
    func fetchWorkoutDays(programID: UUID) async throws -> [WorkoutDayTemplate]
    func fetchExerciseTemplates(workoutDayID: UUID) async throws -> [ExerciseTemplate]
    func fetchWarmupItems(workoutDayID: UUID) async throws -> [WarmupItem]
    func fetchCooldownItems(workoutDayID: UUID) async throws -> [CooldownItem]
    func fetchHealthCheckReminders() async throws -> [HealthCheckReminder]
    func fetchProgramState(programID: UUID) async throws -> ProgramState?
    func recalculateProgramStateTrainingWeek(
        programID: UUID,
        programStartDate: Date,
        at date: Date
    ) async throws -> ProgramState
    func applyDeloadAction(
        programID: UUID,
        reason: DeloadReason,
        action: DeloadAction,
        at date: Date
    ) async throws -> ProgramState
    func setActiveProgramPhase(
        programID: UUID,
        phaseID: UUID,
        at date: Date
    ) async throws -> ProgramState
    func saveSet(_ request: SetLogSaveRequest) async throws -> SetLogSnapshot
    func createWorkoutSession(
        _ request: WorkoutSessionCreateRequest
    ) async throws -> WorkoutSessionSnapshot
    func fetchInProgressWorkoutSession() async throws -> WorkoutSessionSnapshot?
    func transitionWorkoutSession(
        id: UUID,
        to status: WorkoutSessionStatus,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot
    func fetchWorkoutSessionProgress(
        sessionID: UUID
    ) async throws -> WorkoutSessionProgressSnapshot?
    func saveWorkoutSessionProgress(
        _ update: WorkoutSessionProgressUpdate
    ) async throws -> WorkoutSessionProgressSnapshot
    func fetchSessionExercises(workoutDayID: UUID) async throws -> [SessionExerciseSnapshot]
    func fetchSessionPlan(
        workoutDayID: UUID
    ) async throws -> SessionWorkoutPlanSnapshot?
    func fetchSetLogs(workoutSessionID: UUID) async throws -> [SetLogSnapshot]
    func fetchCompletedExerciseHistory(
        exerciseTemplateID: UUID
    ) async throws -> [CompletedExerciseHistorySnapshot]
    func fetchWeeklyPallofHistory() async throws -> WeeklyPallofHistorySnapshot
    func fetchOHPSafeAlternative() async throws -> SessionExerciseSnapshot
    func updateWorkoutSessionOHPSymptomResponse(
        id: UUID,
        response: OHPSymptomResponse,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot
    func updateWorkoutSessionSummary(
        id: UUID,
        perceivedRecovery: Int?,
        note: String?,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot
    func deleteWorkoutSession(id: UUID) async throws
}

public enum TrainingRepositoryCapabilityError: Error, Equatable, Sendable {
    case programStateMutationUnavailable
}

public extension TrainingRepository {
    func recalculateProgramStateTrainingWeek(
        programID _: UUID,
        programStartDate _: Date,
        at _: Date
    ) async throws -> ProgramState {
        throw TrainingRepositoryCapabilityError.programStateMutationUnavailable
    }

    func applyDeloadAction(
        programID _: UUID,
        reason _: DeloadReason,
        action _: DeloadAction,
        at _: Date
    ) async throws -> ProgramState {
        throw TrainingRepositoryCapabilityError.programStateMutationUnavailable
    }

    func setActiveProgramPhase(
        programID _: UUID,
        phaseID _: UUID,
        at _: Date
    ) async throws -> ProgramState {
        throw TrainingRepositoryCapabilityError.programStateMutationUnavailable
    }
}
