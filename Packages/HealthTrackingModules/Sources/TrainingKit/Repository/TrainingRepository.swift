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
    func fetchSetLogs(workoutSessionID: UUID) async throws -> [SetLogSnapshot]
    func deleteWorkoutSession(id: UUID) async throws
}
