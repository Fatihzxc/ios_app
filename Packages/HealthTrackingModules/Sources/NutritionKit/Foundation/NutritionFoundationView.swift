import CoreModels
import SwiftUI

@MainActor
public struct NutritionFoundationView: View {
    private let dayViewModel: NutritionDayViewModel
    private let foodLibraryViewModel: FoodLibraryViewModel
    private let recipeLibraryViewModel: RecipeLibraryViewModel
    private let onAddMeal: @MainActor (NutritionDayKey, MealCategory) -> Void

    public init(
        dayViewModel: NutritionDayViewModel,
        foodLibraryViewModel: FoodLibraryViewModel,
        recipeLibraryViewModel: RecipeLibraryViewModel,
        onAddMeal: @escaping @MainActor (
            NutritionDayKey,
            MealCategory
        ) -> Void = { _, _ in }
    ) {
        self.dayViewModel = dayViewModel
        self.foodLibraryViewModel = foodLibraryViewModel
        self.recipeLibraryViewModel = recipeLibraryViewModel
        self.onAddMeal = onAddMeal
    }

    public var body: some View {
        NavigationStack {
            NutritionDayView(
                viewModel: dayViewModel,
                foodLibraryViewModel: foodLibraryViewModel,
                recipeLibraryViewModel: recipeLibraryViewModel,
                onAddMeal: onAddMeal
            )
        }
        .accessibilityIdentifier("root.nutrition")
    }
}
