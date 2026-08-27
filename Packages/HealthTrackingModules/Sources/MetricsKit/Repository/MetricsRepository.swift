import Foundation

public enum MetricsRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateBodyMetricIDs(id: UUID, count: Int)
    case bodyMetricIDCollision(id: UUID)
    case invalidPersistedBodyMetric(id: UUID)
    case duplicatePostureMetricIDs(id: UUID, count: Int)
    case postureMetricIDCollision(id: UUID)
    case postureMetricUpsertCollision(id: UUID)
    case invalidPersistedPostureMetric(id: UUID)
}

public enum MetricsRepositoryMutationError: Error, Equatable, Sendable {
    case bodyMetricNotFound(id: UUID)
    case staleBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        actualUpdatedAt: Date
    )
    case postureMetricNotFound(id: UUID)
    case stalePostureMetric(
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
    func fetchPostureMetrics() async throws -> [PostureMetricSnapshot]

    func createPostureMetric(
        _ input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot

    func updatePostureMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot

    func deletePostureMetric(id: UUID, expectedUpdatedAt: Date) async throws

    func upsertPostureMetric(
        id: UUID,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot

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
