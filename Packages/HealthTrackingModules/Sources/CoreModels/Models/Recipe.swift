import Foundation
import SwiftData

@Model
public final class Recipe {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var name: String = ""
    public var category: MealCategory = MealCategory.defaultValue
    public var servings: Double = 0
    public var isDirectMacros: Bool = false
    public var caloriesTotal: Double = 0
    public var proteinTotalG: Double = 0
    public var carbTotalG: Double = 0
    public var fatTotalG: Double = 0
    public var note: String?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, name: String = "",
        category: MealCategory = MealCategory.defaultValue, servings: Double = 0,
        isDirectMacros: Bool = false, caloriesTotal: Double = 0, proteinTotalG: Double = 0,
        carbTotalG: Double = 0, fatTotalG: Double = 0, note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.category = category
        self.servings = servings
        self.isDirectMacros = isDirectMacros
        self.caloriesTotal = caloriesTotal
        self.proteinTotalG = proteinTotalG
        self.carbTotalG = carbTotalG
        self.fatTotalG = fatTotalG
        self.note = note
    }
}
