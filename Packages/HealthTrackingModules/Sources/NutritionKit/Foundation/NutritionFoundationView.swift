import CoreModels
import SwiftUI

@MainActor
public struct NutritionFoundationView: View {
    private let dayViewModel: NutritionDayViewModel
    private let foodLibraryViewModel: FoodLibraryViewModel
    private let recipeLibraryViewModel: RecipeLibraryViewModel
    private let quickAddViewModel: NutritionQuickAddViewModel
    private let externalQuickAddIntent: NutritionQuickAddIntent?
    private let onNutritionSnapshot: @MainActor (
        NutritionDayEntriesSnapshot,
        NutritionMacroTargets?
    ) -> Void
    @State private var activeQuickAddIntent: NutritionQuickAddIntent?

    public init(
        dayViewModel: NutritionDayViewModel,
        foodLibraryViewModel: FoodLibraryViewModel,
        recipeLibraryViewModel: RecipeLibraryViewModel,
        quickAddViewModel: NutritionQuickAddViewModel,
        externalQuickAddIntent: NutritionQuickAddIntent? = nil,
        onNutritionSnapshot: @escaping @MainActor (
            NutritionDayEntriesSnapshot,
            NutritionMacroTargets?
        ) -> Void = { _, _ in }
    ) {
        self.dayViewModel = dayViewModel
        self.foodLibraryViewModel = foodLibraryViewModel
        self.recipeLibraryViewModel = recipeLibraryViewModel
        self.quickAddViewModel = quickAddViewModel
        self.externalQuickAddIntent = externalQuickAddIntent
        self.onNutritionSnapshot = onNutritionSnapshot
    }

    public var body: some View {
        NavigationStack {
            NutritionDayView(
                viewModel: dayViewModel,
                foodLibraryViewModel: foodLibraryViewModel,
                recipeLibraryViewModel: recipeLibraryViewModel,
                onAddMeal: startQuickAdd
            )
        }
        .accessibilityIdentifier("root.nutrition")
        .task(id: externalQuickAddIntent?.id) {
            if let externalQuickAddIntent {
                activeQuickAddIntent = externalQuickAddIntent
            }
        }
        .sheet(item: $activeQuickAddIntent) { intent in
            NutritionQuickAddView(
                viewModel: quickAddViewModel,
                intent: intent,
                onPublish: publish,
                onComplete: closeQuickAdd,
                onCancel: closeQuickAdd
            )
        }
    }

    private func startQuickAdd(_ category: MealCategory) {
        activeQuickAddIntent = NutritionQuickAddIntent(
            day: dayViewModel.selectedDay,
            category: category
        )
    }

    private func publish(
        _ snapshot: NutritionDayEntriesSnapshot,
        _ targets: NutritionMacroTargets?
    ) {
        dayViewModel.applyQuickAdd(snapshot: snapshot, targets: targets)
        onNutritionSnapshot(snapshot, targets)
    }

    private func closeQuickAdd() {
        activeQuickAddIntent = nil
    }
}
