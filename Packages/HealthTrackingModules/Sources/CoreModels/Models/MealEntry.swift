import Foundation
import SwiftData

@Model
public final class MealEntry {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var category: MealCategory = MealCategory.defaultValue
    public var recipeId: UUID?
    public var foodId: UUID?
    public var adhocName: String?
    public var quantity: Double = 0
    public var caloriesResolved: Double = 0
    public var proteinResolved: Double = 0
    public var carbResolved: Double = 0
    public var fatResolved: Double = 0
    public var loggedAt: Date = Foundation.Date.now
    public var dailyNutritionLog: DailyNutritionLog?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        category: MealCategory = MealCategory.defaultValue, recipeId: UUID? = nil, foodId: UUID? = nil,
        adhocName: String? = nil, quantity: Double = 0, caloriesResolved: Double = 0,
        proteinResolved: Double = 0, carbResolved: Double = 0, fatResolved: Double = 0,
        loggedAt: Date = .now, dailyNutritionLog: DailyNutritionLog? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.category = category
        self.recipeId = recipeId
        self.foodId = foodId
        self.adhocName = adhocName
        self.quantity = quantity
        self.caloriesResolved = caloriesResolved
        self.proteinResolved = proteinResolved
        self.carbResolved = carbResolved
        self.fatResolved = fatResolved
        self.loggedAt = loggedAt
        self.dailyNutritionLog = dailyNutritionLog
    }
}
