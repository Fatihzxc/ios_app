import CoreModels
import Foundation

@MainActor
public protocol TrainingRepository: AnyObject {
    func fetchUserProfile() async throws -> UserProfile?
    func fetchActiveProgram() async throws -> Program?
    func fetchProgramPhases(programID: UUID) async throws -> [ProgramPhase]
    func fetchWorkoutDays(programID: UUID) async throws -> [WorkoutDayTemplate]
}
