import Foundation

public enum NutritionMacroField: String, CaseIterable, Equatable, Sendable {
    case calories
    case proteinG
    case carbG
    case fatG
}

public enum NutritionNumericError: Error, Equatable, Sendable {
    case nonFiniteMacro(NutritionMacroField)
    case negativeMacro(NutritionMacroField)
    case nonFiniteScale
    case negativeScale
    case nonFiniteQuantity
    case nonPositiveQuantity
    case nonFiniteServingCount
    case nonPositiveServingCount
    case arithmeticOverflow
    case arithmeticUnderflow
    case divisionByZero
}

public struct NutritionQuantity: Equatable, Sendable {
    public let value: Decimal

    public init(_ value: Decimal) throws {
        guard value.isFinite else {
            throw NutritionNumericError.nonFiniteQuantity
        }
        guard value > 0 else {
            throw NutritionNumericError.nonPositiveQuantity
        }
        self.value = value
    }
}

public struct NutritionServingCount: Equatable, Sendable {
    public let value: Decimal

    public init(_ value: Decimal) throws {
        guard value.isFinite else {
            throw NutritionNumericError.nonFiniteServingCount
        }
        guard value > 0 else {
            throw NutritionNumericError.nonPositiveServingCount
        }
        self.value = value
    }
}

enum NutritionDecimalMath {
    static let scale = 6

    static func canonicalMacro(
        _ value: Decimal,
        field: NutritionMacroField
    ) throws -> Decimal {
        guard value.isFinite else {
            throw NutritionNumericError.nonFiniteMacro(field)
        }
        guard value >= 0 else {
            throw NutritionNumericError.negativeMacro(field)
        }
        let result = rounded(value)
        guard result.isFinite else {
            throw NutritionNumericError.arithmeticOverflow
        }
        guard result >= 0 else {
            throw NutritionNumericError.negativeMacro(field)
        }
        return result
    }

    static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        let error = NSDecimalAdd(&result, &lhs, &rhs, .bankers)
        try validate(error)
        return try canonicalResult(result)
    }

    static func subtract(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        let error = NSDecimalSubtract(&result, &lhs, &rhs, .bankers)
        try validate(error)
        return try canonicalResult(result)
    }

    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        let error = NSDecimalMultiply(&result, &lhs, &rhs, .bankers)
        try validate(error)
        return try canonicalResult(result)
    }

    static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard rhs.isFinite, rhs > 0 else {
            throw NutritionNumericError.divisionByZero
        }
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        let error = NSDecimalDivide(&result, &lhs, &rhs, .bankers)
        try validate(error)
        return try canonicalResult(result)
    }

    static func multiplyThenDivide(
        _ value: Decimal,
        multiplier: Decimal,
        divisor: Decimal
    ) throws -> Decimal {
        guard multiplier.isFinite else {
            throw NutritionNumericError.nonFiniteScale
        }
        guard multiplier >= 0 else {
            throw NutritionNumericError.negativeScale
        }
        guard divisor.isFinite, divisor > 0 else {
            throw NutritionNumericError.divisionByZero
        }

        var value = value
        var multiplier = multiplier
        var product = Decimal()
        try validate(NSDecimalMultiply(&product, &value, &multiplier, .bankers))

        var divisor = divisor
        var result = Decimal()
        try validate(NSDecimalDivide(&result, &product, &divisor, .bankers))
        return try canonicalResult(result)
    }

    private static func canonicalResult(_ value: Decimal) throws -> Decimal {
        let result = rounded(value)
        guard result.isFinite else {
            throw NutritionNumericError.arithmeticOverflow
        }
        return result
    }

    private static func rounded(_ value: Decimal) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .bankers)
        return result
    }

    private static func validate(
        _ error: NSDecimalNumber.CalculationError
    ) throws {
        switch error {
        case .noError, .lossOfPrecision:
            return
        case .underflow:
            throw NutritionNumericError.arithmeticUnderflow
        case .overflow:
            throw NutritionNumericError.arithmeticOverflow
        case .divideByZero:
            throw NutritionNumericError.divisionByZero
        @unknown default:
            throw NutritionNumericError.arithmeticOverflow
        }
    }
}
