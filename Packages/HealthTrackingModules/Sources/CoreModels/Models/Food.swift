import Foundation
import SwiftData

@Model
public final class Food {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var name: String = ""
    public var brand: String?
    public var servingSize: Double = 0
    public var servingUnit: String = ""
    public var caloriesPerServing: Double = 0
    public var proteinG: Double = 0
    public var carbG: Double = 0
    public var fatG: Double = 0
    public var fiberG: Double?
    public var source: FoodSource = FoodSource.userCreated

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, name: String = "",
        brand: String? = nil, servingSize: Double = 0, servingUnit: String = "",
        caloriesPerServing: Double = 0, proteinG: Double = 0, carbG: Double = 0, fatG: Double = 0,
        fiberG: Double? = nil, source: FoodSource = .userCreated
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.brand = brand
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        self.caloriesPerServing = caloriesPerServing
        self.proteinG = proteinG
        self.carbG = carbG
        self.fatG = fatG
        self.fiberG = fiberG
        self.source = source
    }
}
