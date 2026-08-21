import Foundation

public struct NutritionDaySnapshot: Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let day: NutritionDayKey
    public let mealEntryIDs: [UUID]

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        day: NutritionDayKey,
        mealEntryIDs: [UUID]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.day = day
        self.mealEntryIDs = mealEntryIDs
    }
}
