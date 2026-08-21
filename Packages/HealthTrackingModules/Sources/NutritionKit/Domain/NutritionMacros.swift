import Foundation

public struct NutritionMacros: Equatable, Sendable {
    public let calories: Decimal
    public let proteinG: Decimal
    public let carbG: Decimal
    public let fatG: Decimal

    public static let zero = NutritionMacros(
        canonicalCalories: 0,
        canonicalProteinG: 0,
        canonicalCarbG: 0,
        canonicalFatG: 0
    )

    public init(
        calories: Decimal,
        proteinG: Decimal,
        carbG: Decimal,
        fatG: Decimal
    ) throws {
        self.calories = try NutritionDecimalMath.canonicalMacro(
            calories,
            field: .calories
        )
        self.proteinG = try NutritionDecimalMath.canonicalMacro(
            proteinG,
            field: .proteinG
        )
        self.carbG = try NutritionDecimalMath.canonicalMacro(
            carbG,
            field: .carbG
        )
        self.fatG = try NutritionDecimalMath.canonicalMacro(
            fatG,
            field: .fatG
        )
    }

    public func adding(_ other: NutritionMacros) throws -> NutritionMacros {
        try NutritionMacros(
            calories: NutritionDecimalMath.add(calories, other.calories),
            proteinG: NutritionDecimalMath.add(proteinG, other.proteinG),
            carbG: NutritionDecimalMath.add(carbG, other.carbG),
            fatG: NutritionDecimalMath.add(fatG, other.fatG)
        )
    }

    public func subtracting(_ other: NutritionMacros) throws -> NutritionMacros {
        try NutritionMacros(
            calories: NutritionDecimalMath.subtract(calories, other.calories),
            proteinG: NutritionDecimalMath.subtract(proteinG, other.proteinG),
            carbG: NutritionDecimalMath.subtract(carbG, other.carbG),
            fatG: NutritionDecimalMath.subtract(fatG, other.fatG)
        )
    }

    public func scaled(by factor: Decimal) throws -> NutritionMacros {
        guard factor.isFinite else {
            throw NutritionNumericError.nonFiniteScale
        }
        guard factor >= 0 else {
            throw NutritionNumericError.negativeScale
        }
        return try NutritionMacros(
            calories: NutritionDecimalMath.multiply(calories, factor),
            proteinG: NutritionDecimalMath.multiply(proteinG, factor),
            carbG: NutritionDecimalMath.multiply(carbG, factor),
            fatG: NutritionDecimalMath.multiply(fatG, factor)
        )
    }

    public func divided(by divisor: Decimal) throws -> NutritionMacros {
        try NutritionMacros(
            calories: NutritionDecimalMath.divide(calories, divisor),
            proteinG: NutritionDecimalMath.divide(proteinG, divisor),
            carbG: NutritionDecimalMath.divide(carbG, divisor),
            fatG: NutritionDecimalMath.divide(fatG, divisor)
        )
    }

    private init(
        canonicalCalories: Decimal,
        canonicalProteinG: Decimal,
        canonicalCarbG: Decimal,
        canonicalFatG: Decimal
    ) {
        calories = canonicalCalories
        proteinG = canonicalProteinG
        carbG = canonicalCarbG
        fatG = canonicalFatG
    }
}
