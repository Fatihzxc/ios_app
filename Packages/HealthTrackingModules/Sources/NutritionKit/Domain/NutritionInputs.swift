import Foundation

public enum FoodInputField: String, CaseIterable, Equatable, Sendable {
    case servingSize
    case calories
    case proteinG
    case carbG
    case fatG
    case fiberG
}

public enum FoodInputError: Error, Equatable, Sendable {
    case emptyName
    case emptyServingUnit
    case nonFinite(FoodInputField)
    case nonPositiveServingSize
    case negative(FoodInputField)
    case notRepresentable(FoodInputField)
}

public struct FoodInput: Equatable, Sendable {
    public let name: String
    public let brand: String?
    public let servingSize: Decimal
    public let servingUnit: String
    public let macros: NutritionMacros
    public let fiberG: Decimal?

    public init(
        name: String,
        brand: String?,
        servingSize: Decimal,
        servingUnit: String,
        caloriesPerServing: Decimal,
        proteinG: Decimal,
        carbG: Decimal,
        fatG: Decimal,
        fiberG: Decimal?
    ) throws {
        let name = Self.trim(name)
        guard !name.isEmpty else { throw FoodInputError.emptyName }
        let servingUnit = Self.trim(servingUnit)
        guard !servingUnit.isEmpty else {
            throw FoodInputError.emptyServingUnit
        }
        guard servingSize.isFinite else {
            throw FoodInputError.nonFinite(.servingSize)
        }
        guard servingSize > 0 else {
            throw FoodInputError.nonPositiveServingSize
        }

        self.name = name
        self.brand = brand.flatMap { value in
            let normalized = Self.trim(value)
            return normalized.isEmpty ? nil : normalized
        }
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        macros = try Self.makeMacros(
            calories: caloriesPerServing,
            proteinG: proteinG,
            carbG: carbG,
            fatG: fatG
        )
        self.fiberG = try fiberG.map(Self.canonicalFiber)
    }

    private static func makeMacros(
        calories: Decimal,
        proteinG: Decimal,
        carbG: Decimal,
        fatG: Decimal
    ) throws -> NutritionMacros {
        do {
            return try NutritionMacros(
                calories: calories,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG
            )
        } catch let error as NutritionNumericError {
            switch error {
            case let .nonFiniteMacro(field):
                throw FoodInputError.nonFinite(inputField(field))
            case let .negativeMacro(field):
                throw FoodInputError.negative(inputField(field))
            default:
                throw FoodInputError.notRepresentable(.calories)
            }
        }
    }

    private static func canonicalFiber(_ value: Decimal) throws -> Decimal {
        guard value.isFinite else {
            throw FoodInputError.nonFinite(.fiberG)
        }
        guard value >= 0 else {
            throw FoodInputError.negative(.fiberG)
        }
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, NutritionDecimalMath.scale, .bankers)
        guard result.isFinite else {
            throw FoodInputError.notRepresentable(.fiberG)
        }
        return result
    }

    private static func inputField(
        _ field: NutritionMacroField
    ) -> FoodInputField {
        switch field {
        case .calories: return .calories
        case .proteinG: return .proteinG
        case .carbG: return .carbG
        case .fatG: return .fatG
        }
    }

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
