import CoreModels
import Foundation

public enum MealCategorySuggestion {
    public static func category(
        at date: Date,
        calendar: Calendar
    ) -> MealCategory {
        let hour = calendar.component(.hour, from: date)
        let kind: MealCategory.Kind
        switch hour {
        case 5...10:
            kind = .breakfast
        case 11...15:
            kind = .lunch
        case 16...21:
            kind = .dinner
        default:
            kind = .snack
        }
        return (try? MealCategory(kind: kind)) ?? .defaultValue
    }
}

public struct RecipeUsageEvent: Equatable, Sendable {
    public let recipeID: UUID
    public let loggedAt: Date

    public init(recipeID: UUID, loggedAt: Date) {
        self.recipeID = recipeID
        self.loggedAt = loggedAt
    }
}

public enum NutritionQuickAddRanking {
    public static func sorted(
        recipes: [RecipeSnapshot],
        usage: [RecipeUsageEvent]
    ) -> [RecipeSnapshot] {
        let usageByRecipe = Dictionary(grouping: usage, by: \.recipeID)
        return recipes.sorted { lhs, rhs in
            let leftUsage = usageByRecipe[lhs.id] ?? []
            let rightUsage = usageByRecipe[rhs.id] ?? []
            if leftUsage.count != rightUsage.count {
                return leftUsage.count > rightUsage.count
            }

            let leftRecent = leftUsage.map(\.loggedAt).max()
            let rightRecent = rightUsage.map(\.loggedAt).max()
            if leftRecent != rightRecent {
                return (leftRecent ?? .distantPast) > (rightRecent ?? .distantPast)
            }

            let leftName = normalized(lhs.name)
            let rightName = normalized(rhs.name)
            if leftName != rightName {
                return leftName < rightName
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func normalized(_ value: String) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        return value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            )
            .lowercased(with: locale)
    }
}
