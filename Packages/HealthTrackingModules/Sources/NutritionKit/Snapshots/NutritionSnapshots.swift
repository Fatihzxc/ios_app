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

public struct NutritionMacroTargets: Equatable, Sendable {
    public let calories: Decimal?
    public let proteinG: Decimal?
    public let carbG: Decimal?
    public let fatG: Decimal?

    public init(
        calories: Decimal?,
        proteinG: Decimal?,
        carbG: Decimal?,
        fatG: Decimal?
    ) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbG = carbG
        self.fatG = fatG
    }
}

public enum NutritionTargetPresentation: Equatable, Sendable {
    case total(consumed: Decimal)
    case targeted(
        consumed: Decimal,
        target: Decimal,
        remaining: Decimal,
        progress: Decimal
    )

    public var clampedProgress: Decimal? {
        guard case let .targeted(_, _, _, progress) = self else {
            return nil
        }
        return min(max(progress, 0), 1)
    }

    init(consumed: Decimal, target: Decimal?) throws {
        guard let target, target.isFinite, target > 0 else {
            self = .total(consumed: consumed)
            return
        }
        self = try .targeted(
            consumed: consumed,
            target: target,
            remaining: NutritionDecimalMath.subtract(target, consumed),
            progress: NutritionDecimalMath.divide(consumed, target)
        )
    }
}

public struct NutritionTargetSummary: Equatable, Sendable {
    public let calories: NutritionTargetPresentation
    public let proteinG: NutritionTargetPresentation
    public let carbG: NutritionTargetPresentation
    public let fatG: NutritionTargetPresentation

    public init(
        consumed: NutritionMacros,
        targets: NutritionMacroTargets
    ) throws {
        calories = try NutritionTargetPresentation(
            consumed: consumed.calories,
            target: targets.calories
        )
        proteinG = try NutritionTargetPresentation(
            consumed: consumed.proteinG,
            target: targets.proteinG
        )
        carbG = try NutritionTargetPresentation(
            consumed: consumed.carbG,
            target: targets.carbG
        )
        fatG = try NutritionTargetPresentation(
            consumed: consumed.fatG,
            target: targets.fatG
        )
    }
}
