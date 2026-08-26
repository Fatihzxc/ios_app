import Foundation

public struct TodayNutritionMetricPresentation: Equatable, Sendable {
    public let consumed: Decimal
    public let target: Decimal?
    public let remaining: Decimal?
    public let clampedProgress: Decimal?

    public init(
        consumed: Decimal,
        target: Decimal?,
        remaining: Decimal?,
        clampedProgress: Decimal?
    ) {
        self.consumed = consumed
        self.target = target
        self.remaining = remaining
        self.clampedProgress = clampedProgress
    }
}

public struct TodayNutritionPresentation: Equatable, Sendable {
    public let calories: TodayNutritionMetricPresentation
    public let protein: TodayNutritionMetricPresentation
    public let carbG: TodayNutritionMetricPresentation
    public let fatG: TodayNutritionMetricPresentation

    public init(
        calories: TodayNutritionMetricPresentation,
        protein: TodayNutritionMetricPresentation,
        carbG: TodayNutritionMetricPresentation,
        fatG: TodayNutritionMetricPresentation
    ) {
        self.calories = calories
        self.protein = protein
        self.carbG = carbG
        self.fatG = fatG
    }
}

public enum TodayNutritionViewState: Equatable, Sendable {
    case loading
    case empty(TodayNutritionPresentation)
    case content(TodayNutritionPresentation)
    case error
}
