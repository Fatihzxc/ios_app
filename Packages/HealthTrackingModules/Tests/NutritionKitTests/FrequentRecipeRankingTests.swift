import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

final class FrequentRecipeRankingTests: XCTestCase {
    func testRankingUsesCountThenMostRecentUseThenNormalizedNameThenUUID() throws {
        let breakfast = try MealCategory(kind: .breakfast)
        let mostFrequent = recipe(
            id: uuid("00000000-0000-4000-8000-000000000401"),
            name: "Zeta",
            category: breakfast
        )
        let mostRecent = recipe(
            id: uuid("00000000-0000-4000-8000-000000000402"),
            name: "Beta",
            category: breakfast
        )
        let lessRecent = recipe(
            id: uuid("00000000-0000-4000-8000-000000000403"),
            name: "Çorba",
            category: breakfast
        )
        let normalizedNameLowerUUID = recipe(
            id: uuid("00000000-0000-4000-8000-000000000404"),
            name: "Álma",
            category: breakfast
        )
        let normalizedNameHigherUUID = recipe(
            id: uuid("00000000-0000-4000-8000-000000000405"),
            name: "alma",
            category: breakfast
        )
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = [
            RecipeUsageEvent(recipeID: mostFrequent.id, category: breakfast, loggedAt: base),
            RecipeUsageEvent(
                recipeID: mostFrequent.id,
                category: breakfast,
                loggedAt: base.addingTimeInterval(1)
            ),
            RecipeUsageEvent(
                recipeID: lessRecent.id,
                category: breakfast,
                loggedAt: base.addingTimeInterval(10)
            ),
            RecipeUsageEvent(
                recipeID: mostRecent.id,
                category: breakfast,
                loggedAt: base.addingTimeInterval(20)
            ),
        ]

        XCTAssertEqual(
            FrequentRecipeRanking.recipes(
                active: [
                    normalizedNameHigherUUID,
                    lessRecent,
                    mostFrequent,
                    normalizedNameLowerUUID,
                    mostRecent,
                ],
                usage: usage,
                category: breakfast
            ).map(\.id),
            [
                mostFrequent.id,
                mostRecent.id,
                lessRecent.id,
                normalizedNameLowerUUID.id,
                normalizedNameHigherUUID.id,
            ]
        )
    }

    func testFilteringUsesTheFullCustomCategoryAndOnlyTheActiveRecipeInput() throws {
        let selected = try MealCategory(kind: .custom, customName: "Gece")
        let otherCustom = try MealCategory(kind: .custom, customName: "Antrenman sonrası")
        let selectedRecipe = recipe(
            id: uuid("00000000-0000-4000-8000-000000000411"),
            name: "Gece kasesi",
            category: selected
        )
        let otherRecipe = recipe(
            id: uuid("00000000-0000-4000-8000-000000000412"),
            name: "Shake",
            category: otherCustom
        )
        let archivedRecipe = recipe(
            id: uuid("00000000-0000-4000-8000-000000000413"),
            name: "Arşivli gece",
            category: selected
        )
        let usage = [
            RecipeUsageEvent(
                recipeID: selectedRecipe.id,
                category: otherCustom,
                loggedAt: Date(timeIntervalSince1970: 1_700_000_100)
            ),
            RecipeUsageEvent(
                recipeID: otherRecipe.id,
                category: selected,
                loggedAt: Date(timeIntervalSince1970: 1_700_000_200)
            ),
            RecipeUsageEvent(
                recipeID: archivedRecipe.id,
                category: selected,
                loggedAt: Date(timeIntervalSince1970: 1_700_000_300)
            ),
        ]

        XCTAssertEqual(
            FrequentRecipeRanking.recipes(
                active: [selectedRecipe, otherRecipe],
                usage: usage,
                category: selected
            ).map(\.id),
            [selectedRecipe.id],
            "A custom category must not collapse to the shared .custom kind, and archived rows are not active input."
        )
    }

    private func recipe(
        id: UUID,
        name: String,
        category: MealCategory
    ) -> RecipeSnapshot {
        RecipeSnapshot(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            name: name,
            category: category,
            servings: 1,
            isDirectMacros: true,
            totalMacros: .zero,
            note: nil
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
