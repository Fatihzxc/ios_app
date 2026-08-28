import Foundation

public enum BloodworkRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateResultIDs(id: UUID, count: Int)
    case resultIDCollision(id: UUID)
    case invalidPersistedResult(id: UUID)
}

public enum BloodworkRepositoryMutationError: Error, Equatable, Sendable {
    case resultNotFound(id: UUID)
    case staleResult(
        id: UUID,
        expectedUpdatedAt: Date,
        actualUpdatedAt: Date
    )
}

public enum BloodworkRepositoryOperationError: Error, Equatable, Sendable {
    case loadFailed
    case saveFailed
}

@MainActor
public protocol BloodworkRepository: AnyObject {
    func fetchResults() async throws -> [BloodworkResultSnapshot]

    func createResult(
        _ input: BloodworkResultInput
    ) async throws -> BloodworkCreationMutation

    func updateResult(
        id: UUID,
        expectedUpdatedAt: Date,
        input: BloodworkResultInput
    ) async throws -> BloodworkResultSnapshot

    func deleteResult(id: UUID, expectedUpdatedAt: Date) async throws

    func undoResultCreation(_ token: BloodworkCreationUndoToken) async throws
}
