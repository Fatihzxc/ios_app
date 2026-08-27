import Foundation

public enum LifestyleRepositoryIntegrityError: Error, Equatable, Sendable {
    case multipleSleepLogs(dayStart: Date, count: Int)
    case multipleMoodLogs(dayStart: Date, count: Int)
    case invalidPersistedSleepLog(id: UUID)
    case invalidPersistedMoodLog(id: UUID)
    case generatedIDCollision(id: UUID)
}

public enum LifestyleRepositoryMutationError: Error, Equatable, Sendable {
    case dayMismatch(expectedDayStart: Date, inputDayStart: Date)
    case staleSleep(expectedUpdatedAt: Date?, actualUpdatedAt: Date?)
    case staleMood(expectedUpdatedAt: Date?, actualUpdatedAt: Date?)
}

public enum LifestyleRepositoryOperationError: Error, Equatable, Sendable {
    case loadFailed
    case saveFailed
}

@MainActor
public protocol LifestyleRepository: AnyObject {
    func fetchLifestyleDay(containing date: Date) async throws -> LifestyleDaySnapshot

    func upsertLifestyleDay(
        _ input: LifestyleDayInput,
        expected: LifestyleDaySnapshot
    ) async throws -> LifestyleDaySnapshot
}
