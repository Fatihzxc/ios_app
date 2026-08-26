import CoreModels
import Foundation

public enum MealCategorySuggestion {
    public static func category(
        at date: Date,
        calendar: Calendar
    ) throws -> MealCategory {
        let kind: MealCategory.Kind
        switch calendar.component(.hour, from: date) {
        case 5...10:
            kind = .breakfast
        case 11...15:
            kind = .lunch
        case 16...21:
            kind = .dinner
        default:
            kind = .snack
        }
        return try MealCategory(kind: kind)
    }
}

public struct RecipeUsageEvent: Equatable, Sendable {
    public let recipeID: UUID
    public let category: MealCategory
    public let loggedAt: Date

    public init(
        recipeID: UUID,
        category: MealCategory,
        loggedAt: Date
    ) {
        self.recipeID = recipeID
        self.category = category
        self.loggedAt = loggedAt
    }
}

public enum FrequentRecipeRanking {
    private struct UsageSummary {
        var count = 0
        var mostRecent: Date?
    }

    public static func recipes(
        active: [RecipeSnapshot],
        usage: [RecipeUsageEvent],
        category: MealCategory
    ) -> [RecipeSnapshot] {
        var summaries: [UUID: UsageSummary] = [:]
        for event in usage where event.category == category {
            var summary = summaries[event.recipeID] ?? UsageSummary()
            summary.count += 1
            if summary.mostRecent.map({ event.loggedAt > $0 }) ?? true {
                summary.mostRecent = event.loggedAt
            }
            summaries[event.recipeID] = summary
        }

        return active
            .filter { $0.category == category }
            .sorted { lhs, rhs in
                let left = summaries[lhs.id] ?? UsageSummary()
                let right = summaries[rhs.id] ?? UsageSummary()
                if left.count != right.count { return left.count > right.count }
                if left.mostRecent != right.mostRecent {
                    switch (left.mostRecent, right.mostRecent) {
                    case let (left?, right?): return left > right
                    case (.some, .none): return true
                    case (.none, .some): return false
                    case (.none, .none): break
                    }
                }
                let leftName = FoodSearch.normalized(lhs.name)
                let rightName = FoodSearch.normalized(rhs.name)
                if leftName != rightName { return leftName < rightName }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }
}

public struct NutritionQuickAddIntent: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let day: NutritionDayKey
    public let category: MealCategory

    public init(
        id: UUID = UUID(),
        day: NutritionDayKey,
        category: MealCategory
    ) {
        self.id = id
        self.day = day
        self.category = category
    }

    public static func suggested(
        at date: Date,
        calendar: Calendar,
        id: UUID = UUID()
    ) throws -> Self {
        try Self(
            id: id,
            day: NutritionDayKey(containing: date, calendar: calendar),
            category: MealCategorySuggestion.category(at: date, calendar: calendar)
        )
    }
}

public struct NutritionQuickAddContext: Equatable, Sendable {
    public let daySnapshot: NutritionDayEntriesSnapshot
    public let targets: NutritionMacroTargets?
    public let activeRecipes: [RecipeSnapshot]
    public let usage: [RecipeUsageEvent]

    public init(
        daySnapshot: NutritionDayEntriesSnapshot,
        targets: NutritionMacroTargets?,
        activeRecipes: [RecipeSnapshot],
        usage: [RecipeUsageEvent]
    ) {
        self.daySnapshot = daySnapshot
        self.targets = targets
        self.activeRecipes = activeRecipes
        self.usage = usage
    }
}

public enum NutritionQuickAddPhase: Equatable, Sendable {
    case idle
    case loading
    case selecting
    case confirming
    case saving
    case saveError
    case loadError
    case completed
}

@MainActor
public protocol NutritionQuickAddRepository {
    func fetchQuickAddContext(
        containing date: Date
    ) async throws -> NutritionQuickAddContext

    func createMealEntry(
        _ request: MealEntryCreateRequest
    ) async throws -> NutritionDayEntriesSnapshot
}
