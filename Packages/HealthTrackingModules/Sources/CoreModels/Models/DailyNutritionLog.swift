import Foundation
import SwiftData

@Model
public final class DailyNutritionLog {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var date: Date = Foundation.Date.now
    @Relationship(deleteRule: .nullify, inverse: \MealEntry.dailyNutritionLog)
    public var mealEntries: [MealEntry]? = nil

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, date: Date = .now,
        mealEntries: [MealEntry]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.mealEntries = mealEntries
    }
}
