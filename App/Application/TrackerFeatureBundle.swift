import Foundation
import MetricsKit
import PersistenceKit
import SwiftData
import SwiftUI

@MainActor
final class TrackerFeatureBundle: TrackerFeatureRouting {
    let repository: any MetricsRepository
    let bodyMetricViewModel: BodyMetricViewModel

    init(repository: any MetricsRepository) {
        self.repository = repository
        bodyMetricViewModel = BodyMetricViewModel(repository: repository)
    }

    func makeBodyMetricEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        AnyView(
            BodyMetricEntryView(
                viewModel: bodyMetricViewModel,
                onClose: onClose
            )
        )
    }

    func makeProgressView() -> AnyView {
        AnyView(BodyMetricProgressView(viewModel: bodyMetricViewModel))
    }
}

@MainActor
enum DefaultTrackerFeatureFactory {
    static func make(
        environment: AppEnvironment,
        modelContext: ModelContext
    ) -> any TrackerFeatureRouting {
        let repository = SwiftDataMetricsRepository(modelContext: modelContext)
        #if DEBUG
        if environment == .uiTesting,
           AppUITestLaunchConfiguration.resolve()?.scenario == .m3BodyMetrics {
            return TrackerFeatureBundle(
                repository: UITestMetricsRepository(
                    repository: repository,
                    failsFirstCreate: true
                )
            )
        }
        #endif
        return TrackerFeatureBundle(repository: repository)
    }
}

#if DEBUG
@MainActor
private final class UITestMetricsRepository: MetricsRepository {
    private enum FixtureFailure: Error {
        case create
    }

    private let repository: any MetricsRepository
    private var failsNextCreate: Bool

    init(
        repository: any MetricsRepository,
        failsFirstCreate: Bool
    ) {
        self.repository = repository
        failsNextCreate = failsFirstCreate
    }

    func fetchBodyMetrics() async throws -> [BodyMetricSnapshot] {
        try await repository.fetchBodyMetrics()
    }

    func createBodyMetrics(
        _ input: BodyMetricBatchInput
    ) async throws -> BodyMetricCreationMutation {
        if failsNextCreate {
            failsNextCreate = false
            throw FixtureFailure.create
        }
        return try await repository.createBodyMetrics(input)
    }

    func updateBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        date: Date,
        value: BodyMetricValueInput
    ) async throws -> BodyMetricSnapshot {
        try await repository.updateBodyMetric(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt,
            date: date,
            value: value
        )
    }

    func deleteBodyMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        try await repository.deleteBodyMetric(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt
        )
    }

    func undoBodyMetricCreation(
        _ token: BodyMetricCreationUndoToken
    ) async throws {
        try await repository.undoBodyMetricCreation(token)
    }
}
#endif
