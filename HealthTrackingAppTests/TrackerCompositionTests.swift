@testable import HealthTrackingApp
import CoreModels
import Foundation
import MetricsKit
import SleepMoodKit
import XCTest

@MainActor
final class TrackerCompositionTests: XCTestCase {
    func testBootstrapAndRootConstructionDoNotInvokeTrackerFactoryAndFirstRouteCachesOnce() async throws {
        var factoryCalls = 0
        let repository = TrackerMetricsRepositoryStub()
        let lifestyleRepository = TrackerLifestyleRepositoryStub()
        let dependencies = try AppDependencies(
            environment: .uiTesting,
            makeTrackerFeatureBundle: { _ in
                factoryCalls += 1
                return TrackerFeatureBundle(
                    metricsRepository: repository,
                    lifestyleRepository: lifestyleRepository
                )
            }
        )

        XCTAssertEqual(factoryCalls, 0)
        try dependencies.load()
        await dependencies.loadInitialContent()
        XCTAssertEqual(factoryCalls, 0)

        _ = AppRootView(
            todayViewModel: dependencies.todayViewModel,
            foundationViewModel: dependencies.foundationViewModel,
            phaseTransitionViewModel: dependencies.phaseTransitionViewModel,
            trainingHistoryViewModel: dependencies.trainingHistoryViewModel,
            todayNutritionViewModel: dependencies.todayNutritionViewModel,
            nutritionDayViewModel: dependencies.nutritionDayViewModel,
            foodLibraryViewModel: dependencies.foodLibraryViewModel,
            recipeLibraryViewModel: dependencies.recipeLibraryViewModel,
            nutritionQuickAddViewModel: dependencies.nutritionQuickAddViewModel,
            nutritionManualEntryViewModel: dependencies.nutritionManualEntryViewModel,
            makeSessionViewModel: dependencies.makeSessionViewModel,
            makeTrackerFeatureRouter: dependencies.makeTrackerFeatureRouter,
            trainingHapticController: dependencies.trainingHapticController,
            shouldLoadFoundation: dependencies.shouldLoadFoundation,
            persistencePresentation: dependencies.persistencePresentation
        )
        XCTAssertEqual(factoryCalls, 0)

        let firstRoute = dependencies.makeTrackerFeatureRouter()
        let progressRoute = dependencies.makeTrackerFeatureRouter()

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertTrue(firstRoute === progressRoute)
        let bundle = try XCTUnwrap(firstRoute as? TrackerFeatureBundle)
        XCTAssertTrue((bundle.repository as AnyObject) === repository)
        XCTAssertTrue(
            (bundle.lifestyleRepository as AnyObject) === lifestyleRepository
        )
    }
}

@MainActor
private final class TrackerLifestyleRepositoryStub: LifestyleRepository {
    func fetchLifestyleDay(containing date: Date) async throws -> LifestyleDaySnapshot {
        throw StubFailure.unexpectedLoad
    }

    func upsertLifestyleDay(
        _ input: LifestyleDayInput,
        expected: LifestyleDaySnapshot
    ) async throws -> LifestyleDaySnapshot {
        throw StubFailure.unexpectedMutation
    }

    private enum StubFailure: Error {
        case unexpectedLoad
        case unexpectedMutation
    }
}

@MainActor
private final class TrackerMetricsRepositoryStub: MetricsRepository {
    func fetchPostureMetrics() async throws -> [PostureMetricSnapshot] { [] }

    func createPostureMetric(
        _ input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedMutation
    }

    func updatePostureMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedMutation
    }

    func deletePostureMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        throw StubFailure.unexpectedMutation
    }

    func upsertPostureMetric(
        id: UUID,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedMutation
    }

    func fetchBodyMetrics() async throws -> [BodyMetricSnapshot] { [] }

    func createBodyMetrics(
        _ input: BodyMetricBatchInput
    ) async throws -> BodyMetricCreationMutation {
        throw StubFailure.unexpectedMutation
    }

    func updateBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        date: Date,
        value: BodyMetricValueInput
    ) async throws -> BodyMetricSnapshot {
        throw StubFailure.unexpectedMutation
    }

    func deleteBodyMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        throw StubFailure.unexpectedMutation
    }

    func undoBodyMetricCreation(_ token: BodyMetricCreationUndoToken) async throws {
        throw StubFailure.unexpectedMutation
    }

    private enum StubFailure: Error {
        case unexpectedMutation
    }
}
