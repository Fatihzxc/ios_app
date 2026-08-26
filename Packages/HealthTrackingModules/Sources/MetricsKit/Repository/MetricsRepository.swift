import Foundation

public enum MetricsRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateBodyMetricIDs(id: UUID, count: Int)
    case bodyMetricIDCollision(id: UUID)
    case invalidPersistedBodyMetric(id: UUID)
}

public enum MetricsRepositoryMutationError: Error, Equatable, Sendable {
    case bodyMetricNotFound(id: UUID)
    case staleBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        actualUpdatedAt: Date
    )
}

public enum MetricsRepositoryOperationError: Error, Equatable, Sendable {
    case loadFailed
    case saveFailed
}

@MainActor
public protocol MetricsRepository: AnyObject {
    func fetchBodyMetrics() async throws -> [BodyMetricSnapshot]

    func createBodyMetrics(
        _ input: BodyMetricBatchInput
    ) async throws -> BodyMetricCreationMutation

    func updateBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        date: Date,
        value: BodyMetricValueInput
    ) async throws -> BodyMetricSnapshot

    func deleteBodyMetric(id: UUID, expectedUpdatedAt: Date) async throws

    func undoBodyMetricCreation(_ token: BodyMetricCreationUndoToken) async throws
}
