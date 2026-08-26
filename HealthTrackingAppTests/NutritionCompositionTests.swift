@testable import HealthTrackingApp
import CoreModels
import Foundation
import NutritionKit
import XCTest

@MainActor
final class NutritionCompositionTests: XCTestCase {
    func testUITestCompositionPublishesRepositoryBackedNutritionToday() async throws {
        let dependencies = try AppDependencies(environment: .uiTesting)
        try dependencies.load()

        XCTAssertNotNil(dependencies.nutritionRepository)
        XCTAssertNotNil(dependencies.nutritionManualEntryViewModel)
        await dependencies.nutritionDayViewModel.load()

        guard case let .empty(presentation) = dependencies.nutritionDayViewModel.state else {
            XCTFail("The seeded composition must expose a real, currently empty nutrition day.")
            return
        }
        XCTAssertEqual(
            presentation.sections.map(\.category.kind),
            [.breakfast, .lunch, .dinner, .snack]
        )
        XCTAssertEqual(presentation.totalMacros, .zero)
        guard case let .targeted(_, target, _, _) = presentation.targets.proteinG else {
            XCTFail("The seeded user profile's protein target must reach NutritionKit.")
            return
        }
        XCTAssertGreaterThan(target, 0)
    }

    func testAppCompositionUsesOneRepositoryForDayFoodAndRecipeViewModels() async throws {
        let dependencies = try AppDependencies(environment: .uiTesting)
        try dependencies.load()

        await dependencies.nutritionDayViewModel.load()
        await dependencies.foodLibraryViewModel.load()
        await dependencies.recipeLibraryViewModel.load()

        XCTAssertNotEqual(dependencies.nutritionDayViewModel.state, .loading)
        XCTAssertNotEqual(dependencies.foodLibraryViewModel.state, .loading)
        XCTAssertNotEqual(dependencies.recipeLibraryViewModel.state, .loading)
        withExtendedLifetime(dependencies.nutritionRepository) {}
    }

    func testRootInitializerRequiresComposedNutritionDependencies() {
        withExtendedLifetime(Self.rootInitializerIsTypeChecked) {}
    }

    func testNutritionEvidenceScenariosHaveStableLaunchValues() {
        XCTAssertEqual(AppUITestScenario.nutritionContent.rawValue, "nutrition-content")
        XCTAssertEqual(AppUITestScenario.nutritionEmpty.rawValue, "nutrition-empty")
        XCTAssertEqual(AppUITestScenario.nutritionErrorOnce.rawValue, "nutrition-error-once")
        XCTAssertEqual(
            AppUITestScenario.nutritionDeleteErrorOnce.rawValue,
            "nutrition-delete-error-once"
        )
        XCTAssertEqual(
            AppUITestScenario.nutritionQuickAdd.rawValue,
            "nutrition-quick-add"
        )
        XCTAssertEqual(AppUITestScenario.m2Acceptance.rawValue, "m2-acceptance")
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
