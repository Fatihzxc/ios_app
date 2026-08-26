import CoreModels
import Foundation

public struct RecipeSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let name: String
    public let category: MealCategory
    public let servings: Decimal
    public let isDirectMacros: Bool
    public let totalMacros: NutritionMacros
    public let note: String?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        name: String,
        category: MealCategory,
        servings: Decimal,
        isDirectMacros: Bool,
        totalMacros: NutritionMacros,
        note: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.category = category
        self.servings = servings
        self.isDirectMacros = isDirectMacros
        self.totalMacros = totalMacros
        self.note = note
    }

    public func resolvedMacros(
        consumedServings: Decimal
    ) throws -> NutritionMacros {
        let consumed = try NutritionServingCount(consumedServings)
        let totalServings = try NutritionServingCount(servings)
        return try totalMacros.scaled(
            by: consumed.value,
            dividedBy: totalServings.value
        )
    }
}

public struct RecipeLibrarySnapshot: Equatable, Sendable {
    public let active: [RecipeSnapshot]
    public let archived: [RecipeSnapshot]

    public init(active: [RecipeSnapshot], archived: [RecipeSnapshot]) {
        self.active = active
        self.archived = archived
    }
}

public enum RecipeRemovalResult: Equatable, Sendable {
    case deleted
    case archived
}

public enum RecipeRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateRecipeIDs(id: UUID, count: Int)
    case recipeIDCollision(id: UUID)
    case invalidPersistedRecipe(id: UUID)
    case duplicateArchiveSettings(count: Int)
    case archivedRecipeMissing(id: UUID)
}

public enum RecipeRepositoryMutationError: Error, Equatable, Sendable {
    case recipeNotFound(id: UUID)
    case recipeNotArchived(id: UUID)
    case invalidInput
}

@MainActor
public protocol RecipeLibraryRepository {
    func fetchRecipeLibrary(
        matching query: String,
        category: MealCategory.Kind?
    ) async throws -> RecipeLibrarySnapshot
    func createRecipe(_ input: RecipeInput) async throws -> RecipeSnapshot
    func updateRecipe(id: UUID, input: RecipeInput) async throws -> RecipeSnapshot
    func removeRecipe(id: UUID) async throws -> RecipeRemovalResult
    func restoreRecipe(id: UUID) async throws -> RecipeSnapshot
}

package enum RecipeSearch {
    package static func library(
        active: [RecipeSnapshot],
        archived: [RecipeSnapshot],
        matching query: String,
        category: MealCategory.Kind?
    ) -> RecipeLibrarySnapshot {
        RecipeLibrarySnapshot(
            active: results(active, matching: query, category: category),
            archived: results(archived, matching: query, category: category)
        )
    }

    private static func results(
        _ recipes: [RecipeSnapshot],
        matching query: String,
        category: MealCategory.Kind?
    ) -> [RecipeSnapshot] {
        let query = FoodSearch.normalized(query)
        return recipes
            .filter { recipe in
                (query.isEmpty || FoodSearch.normalized(recipe.name).contains(query))
                    && (category == nil || recipe.category.kind == category)
            }
            .sorted(by: ordered)
    }

    private static func ordered(
        _ lhs: RecipeSnapshot,
        _ rhs: RecipeSnapshot
    ) -> Bool {
        let lhsName = FoodSearch.normalized(lhs.name)
        let rhsName = FoodSearch.normalized(rhs.name)
        if lhsName != rhsName { return lhsName < rhsName }

        let lhsCategory = categoryKey(lhs.category)
        let rhsCategory = categoryKey(rhs.category)
        if lhsCategory.rank != rhsCategory.rank {
            return lhsCategory.rank < rhsCategory.rank
        }
        if lhsCategory.customName != rhsCategory.customName {
            return lhsCategory.customName < rhsCategory.customName
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func categoryKey(
        _ category: MealCategory
    ) -> (rank: Int, customName: String) {
        let rank: Int
        switch category.kind {
        case .breakfast: rank = 0
        case .lunch: rank = 1
        case .dinner: rank = 2
        case .snack: rank = 3
        case .custom: rank = 4
        }
        return (
            rank,
            category.customName.map(FoodSearch.normalized) ?? ""
        )
    }
}
