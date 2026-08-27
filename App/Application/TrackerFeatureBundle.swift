import Foundation
import MetricsKit
import PersistenceKit
import SleepMoodKit
import SwiftData
import SwiftUI

@MainActor
final class TrackerFeatureBundle: TrackerFeatureRouting {
    let repository: any MetricsRepository
    let lifestyleRepository: any LifestyleRepository
    let bodyMetricViewModel: BodyMetricViewModel
    let postureViewModel: PostureViewModel
    let lifestyleViewModel: LifestyleViewModel
    private let now: @MainActor () -> Date

    init(
        metricsRepository: any MetricsRepository,
        lifestyleRepository: any LifestyleRepository,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        repository = metricsRepository
        self.lifestyleRepository = lifestyleRepository
        self.now = now
        bodyMetricViewModel = BodyMetricViewModel(repository: metricsRepository)
        postureViewModel = PostureViewModel(repository: metricsRepository)
        lifestyleViewModel = LifestyleViewModel(repository: lifestyleRepository)
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

    func makeLifestyleEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        AnyView(
            LifestyleEntryView(
                viewModel: lifestyleViewModel,
                initialDate: now(),
                onClose: onClose
            )
        )
    }

    func makePostureEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        AnyView(
            PostureEntryView(
                viewModel: postureViewModel,
                initialDate: now(),
                onClose: onClose
            )
        )
    }

    func makeProgressView() -> AnyView {
        AnyView(
            BodyMetricProgressView(viewModel: bodyMetricViewModel) {
                VStack(alignment: .leading, spacing: 24) {
                    LifestyleProgressSection(
                        viewModel: lifestyleViewModel,
                        date: now()
                    )
                    PostureProgressSection(viewModel: postureViewModel)
                }
            }
        )
    }
}

@MainActor
enum DefaultTrackerFeatureFactory {
    static func make(
        environment: AppEnvironment,
        modelContext: ModelContext
    ) -> any TrackerFeatureRouting {
        let metricsRepository = SwiftDataMetricsRepository(modelContext: modelContext)
        let lifestyleRepository = SwiftDataLifestyleRepository(modelContext: modelContext)
        #if DEBUG
        if environment == .uiTesting,
           let scenario = AppUITestLaunchConfiguration.resolve()?.scenario {
            if scenario == .m3BodyMetrics {
                return TrackerFeatureBundle(
                    metricsRepository: UITestMetricsRepository(
                        repository: metricsRepository,
                        failsFirstCreate: true
                    ),
                    lifestyleRepository: lifestyleRepository
                )
            }
            if scenario == .m3SleepMood {
                return TrackerFeatureBundle(
                    metricsRepository: metricsRepository,
                    lifestyleRepository: UITestLifestyleRepository(
                        repository: lifestyleRepository,
                        failsFirstUpsert: true
                    )
                )
            }
            if scenario == .m3Posture {
                return TrackerFeatureBundle(
                    metricsRepository: UITestMetricsRepository(
                        repository: metricsRepository,
                        failsFirstCreate: false,
                        failsFirstPostureCreate: true
                    ),
                    lifestyleRepository: lifestyleRepository
                )
            }
        }
        #endif
        return TrackerFeatureBundle(
            metricsRepository: metricsRepository,
            lifestyleRepository: lifestyleRepository
        )
    }
}

#if DEBUG
@MainActor
private final class UITestLifestyleRepository: LifestyleRepository {
    private enum FixtureFailure: Error {
        case upsert
    }

    private let repository: any LifestyleRepository
    private var failsNextUpsert: Bool

    init(
        repository: any LifestyleRepository,
        failsFirstUpsert: Bool
    ) {
        self.repository = repository
        failsNextUpsert = failsFirstUpsert
    }

    func fetchLifestyleDay(containing date: Date) async throws -> LifestyleDaySnapshot {
        try await repository.fetchLifestyleDay(containing: date)
    }

    func upsertLifestyleDay(
        _ input: LifestyleDayInput,
        expected: LifestyleDaySnapshot
    ) async throws -> LifestyleDaySnapshot {
        if failsNextUpsert {
            failsNextUpsert = false
            throw FixtureFailure.upsert
        }
        return try await repository.upsertLifestyleDay(input, expected: expected)
    }
}
#endif

#if DEBUG
@MainActor
private final class UITestMetricsRepository: MetricsRepository {
    private enum FixtureFailure: Error {
        case create
    }

    private let repository: any MetricsRepository
    private var failsNextCreate: Bool
    private var failsNextPostureCreate: Bool

    init(
        repository: any MetricsRepository,
        failsFirstCreate: Bool,
        failsFirstPostureCreate: Bool = false
    ) {
        self.repository = repository
        failsNextCreate = failsFirstCreate
        failsNextPostureCreate = failsFirstPostureCreate
    }

    func fetchPostureMetrics() async throws -> [PostureMetricSnapshot] {
        try await repository.fetchPostureMetrics()
    }

    func createPostureMetric(
        _ input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        if failsNextPostureCreate {
            failsNextPostureCreate = false
            throw FixtureFailure.create
        }
        return try await repository.createPostureMetric(input)
    }

    func updatePostureMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        try await repository.updatePostureMetric(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt,
            input: input
        )
    }

    func deletePostureMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        try await repository.deletePostureMetric(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt
        )
    }

    func upsertPostureMetric(
        id: UUID,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        try await repository.upsertPostureMetric(id: id, input: input)
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
