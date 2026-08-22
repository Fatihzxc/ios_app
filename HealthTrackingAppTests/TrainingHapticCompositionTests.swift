@testable import HealthTrackingApp
import Foundation
import TrainingKit
import XCTest

@MainActor
final class TrainingHapticCompositionTests: XCTestCase {
    func testAppCompositionInjectsOneLoadedControllerIntoSessionAndSettings() async throws {
        let client = AppHapticClientSpy()
        let dependencies = try AppDependencies(
            environment: .uiTesting,
            hapticClient: client
        )
        try dependencies.load()
        XCTAssertNil(
            dependencies.trainingHapticController,
            "Haptic composition must stay outside the measured pre-Today launch path."
        )
        await dependencies.loadInitialContent()

        let session = dependencies.makeSessionViewModel()
        session.stepperChanged()
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
            makeSessionViewModel: dependencies.makeSessionViewModel,
            trainingHapticController: dependencies.trainingHapticController,
            shouldLoadFoundation: dependencies.shouldLoadFoundation,
            persistencePresentation: dependencies.persistencePresentation
        )

        let controller = try XCTUnwrap(dependencies.trainingHapticController)
        XCTAssertEqual(controller.preferenceState, .loaded)
        XCTAssertEqual(client.feedback, [.selection])
    }

    func testAppCompositionReloadsPersistedKillSwitchAndSessionEmitsNothing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("app-haptics.store")

        try await disableHaptics(at: storeURL)

        let client = AppHapticClientSpy()
        let relaunched = try AppDependencies(
            environment: .local(storeURL: storeURL),
            hapticClient: client
        )
        try relaunched.load()
        await relaunched.loadInitialContent()
        relaunched.makeSessionViewModel().stepperChanged()

        XCTAssertFalse(try XCTUnwrap(relaunched.trainingHapticController).isEnabled)
        XCTAssertTrue(client.feedback.isEmpty)
    }

    private func disableHaptics(at storeURL: URL) async throws {
        let dependencies = try AppDependencies(
            environment: .local(storeURL: storeURL),
            hapticClient: AppHapticClientSpy()
        )
        try dependencies.load()
        await dependencies.loadInitialContent()
        try XCTUnwrap(dependencies.trainingHapticController).setEnabled(false)
    }
}

@MainActor
private final class AppHapticClientSpy: TrainingHapticClient {
    private(set) var feedback: [TrainingHapticFeedback] = []

    func play(_ feedback: TrainingHapticFeedback) {
        self.feedback.append(feedback)
    }
}
