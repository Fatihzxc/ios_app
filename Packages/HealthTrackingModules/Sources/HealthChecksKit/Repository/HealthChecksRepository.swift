import CoreModels
import Foundation

public enum HealthChecksRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateReminderIDs(id: UUID, count: Int)
    case invalidPersistedReminder(id: UUID)
    case reminderIDCollision(id: UUID)
    case duplicateSuccessorLinks(predecessorID: UUID, count: Int)
    case invalidSuccessorLink(predecessorID: UUID)
}

public enum HealthChecksRepositoryMutationError: Error, Equatable, Sendable {
    case reminderNotFound(id: UUID)
    case completionRequiresPending(id: UUID, actualStatus: HealthCheckStatus)
    case staleReminder(
        id: UUID,
        expectedUpdatedAt: Date,
        actualUpdatedAt: Date
    )
}

public enum HealthChecksRepositoryOperationError: Error, Equatable, Sendable {
    case saveFailed
}

@MainActor
public protocol HealthChecksRepository: AnyObject {
    func fetchReminders() async throws -> [HealthCheckReminderSnapshot]
    func createReminder(
        _ input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot
    func updateReminder(
        id: UUID,
        expectedUpdatedAt: Date,
        input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot
    func deleteReminder(id: UUID, expectedUpdatedAt: Date) async throws
    func completeReminder(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws -> HealthCheckCompletionMutation
    func undoCompletion(
        _ token: HealthCheckCompletionUndoToken
    ) async throws -> HealthCheckReminderSnapshot
}
