@testable import HealthTrackingApp
import Foundation
import TrainingKit
import XCTest

@MainActor
final class TodayCompositionTests: XCTestCase {
    func testUITestCompositionLoadsTodayThroughTheRealRepositorySnapshot() async throws {
        let dependencies = try AppDependencies(environment: .uiTesting)
        try dependencies.load()

        let repositoryValue = try await dependencies.trainingRepository.fetchTodaySnapshot()
        let repositorySnapshot = try XCTUnwrap(repositoryValue)
        XCTAssertEqual(repositorySnapshot.phases.map(\.name), [
            "Temel", "İnşa", "İlerleme", "Konsolidasyon",
        ])
        XCTAssertEqual(repositorySnapshot.workoutDays.map(\.name), ["Gün A", "Gün B", "Gün C"])
        XCTAssertEqual(
            repositorySnapshot.workoutDays.filter { $0.containsOHP }.map(\.name),
            ["Gün B"]
        )
        XCTAssertTrue(repositorySnapshot.sessions.isEmpty)
        XCTAssertTrue(repositorySnapshot.exerciseHistories.isEmpty)
        XCTAssertEqual(repositorySnapshot.healthChecks.count, 3)

        await dependencies.loadInitialContent()

        guard case let .content(content) = dependencies.todayViewModel.state else {
            XCTFail("The app composition must publish repository-backed Today content.")
            return
        }
        XCTAssertGreaterThan(content.proteinTargetG, 0)
        XCTAssertNotNil(content.firstMeaningfulContentElapsed)
    }

    func testAppRootInitializerRequiresTheComposedTodayViewModel() {
        withExtendedLifetime(Self.rootInitializerIsTypeChecked) {}
    }

    func testEveryTodayEvidenceScenarioHasAStableLaunchValue() {
        XCTAssertEqual(AppUITestScenario.todayTrain.rawValue, "today-train")
        XCTAssertEqual(AppUITestScenario.todayRest.rawValue, "today-rest")
        XCTAssertEqual(AppUITestScenario.todayResume.rawValue, "today-resume")
        XCTAssertEqual(AppUITestScenario.todayDeload.rawValue, "today-deload")
        XCTAssertEqual(AppUITestScenario.todayPhase.rawValue, "today-phase")
        XCTAssertEqual(AppUITestScenario.todayReminder.rawValue, "today-reminder")
        XCTAssertEqual(AppUITestScenario.todayPriority.rawValue, "today-priority")
        XCTAssertEqual(AppUITestScenario.todayEmptyOnce.rawValue, "today-empty-once")
        XCTAssertEqual(AppUITestScenario.todayErrorOnce.rawValue, "today-error-once")
    }

    func testLaunchClockStartsNoLaterThanDependencyConstruction() throws {
        let launchStart = AppLaunchPerformance.startedAt
        _ = try AppDependencies(environment: .uiTesting)

        XCTAssertLessThanOrEqual(launchStart, ProcessInfo.processInfo.systemUptime)
    }

    func testLaunchPerformanceCheckpointNamesAreStableAndOrdered() {
        XCTAssertEqual(
            AppLaunchPerformance.Checkpoint.allCases.map(\.rawValue),
            ["environment", "container", "dependencies", "seed", "today"]
        )
    }

    func testLaunchPerformanceEvidenceRequiresOneExplicitUITestFlag() throws {
        let baseArguments = [
            "HealthTrackingApp",
            "-ui-testing",
            "-ui-test-scenario", "seeded",
            "-ui-test-appearance", "light",
        ]
        XCTAssertFalse(
            try XCTUnwrap(
                AppUITestLaunchConfiguration.resolve(arguments: baseArguments)
            ).exposesLaunchPerformanceEvidence
        )

        let flag = AppUITestLaunchConfiguration.launchPerformanceEvidenceFlag
        XCTAssertTrue(
            try XCTUnwrap(
                AppUITestLaunchConfiguration.resolve(arguments: baseArguments + [flag])
            ).exposesLaunchPerformanceEvidence
        )
        XCTAssertNil(
            AppUITestLaunchConfiguration.resolve(
                arguments: baseArguments + [flag, flag]
            ),
            "Duplicate instrumentation flags must fail closed."
        )
    }

    private static let rootInitializerIsTypeChecked: () -> Void = {
        guard let dependencies = try? AppDependencies(environment: .uiTesting) else { return }
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
            trainingHapticController: dependencies.trainingHapticController,
            shouldLoadFoundation: dependencies.shouldLoadFoundation,
            persistencePresentation: dependencies.persistencePresentation
        )
    }
}
