import SwiftUI

@MainActor
public struct NutritionFoundationView: View {
    private let dayViewModel: NutritionDayViewModel
    private let foodLibraryViewModel: FoodLibraryViewModel
    private let recipeLibraryViewModel: RecipeLibraryViewModel

    public init(
        dayViewModel: NutritionDayViewModel,
        foodLibraryViewModel: FoodLibraryViewModel,
        recipeLibraryViewModel: RecipeLibraryViewModel
    ) {
        self.dayViewModel = dayViewModel
        self.foodLibraryViewModel = foodLibraryViewModel
        self.recipeLibraryViewModel = recipeLibraryViewModel
    }

    public var body: some View {
        NavigationStack {
            NutritionDayView(
                viewModel: dayViewModel,
                foodLibraryViewModel: foodLibraryViewModel,
                recipeLibraryViewModel: recipeLibraryViewModel
            )
        }
        .accessibilityIdentifier("root.nutrition")
    }
}
