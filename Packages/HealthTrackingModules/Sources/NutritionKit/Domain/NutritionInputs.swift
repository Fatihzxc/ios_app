import CoreModels
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

public enum RecipeInputField: String, CaseIterable, Equatable, Sendable {
    case servings
    case calories
    case proteinG
    case carbG
    case fatG
}

public enum RecipeInputError: Error, Equatable, Sendable {
    case emptyName
    case nonFinite(RecipeInputField)
    case nonPositiveServings
    case negative(RecipeInputField)
    case invalidCategory
    case notRepresentable(RecipeInputField)
}

public struct RecipeInput: Equatable, Sendable {
    public let name: String
    public let category: MealCategory
    public let servings: Decimal
    public let totalMacros: NutritionMacros
    public let note: String?

    public init(
        name: String,
        category: MealCategory,
        servings: Decimal,
        caloriesTotal: Decimal,
        proteinTotalG: Decimal,
        carbTotalG: Decimal,
        fatTotalG: Decimal,
        note: String?
    ) throws {
        let name = Self.trim(name)
        guard !name.isEmpty else { throw RecipeInputError.emptyName }
        guard servings.isFinite else {
            throw RecipeInputError.nonFinite(.servings)
        }
        guard servings > 0 else {
            throw RecipeInputError.nonPositiveServings
        }

        let canonicalCategory: MealCategory
        do {
            canonicalCategory = try MealCategory(
                kind: category.kind,
                customName: category.customName
            )
        } catch {
            throw RecipeInputError.invalidCategory
        }

        self.name = name
        self.category = canonicalCategory
        self.servings = servings
        totalMacros = try Self.makeMacros(
            calories: caloriesTotal,
            proteinG: proteinTotalG,
            carbG: carbTotalG,
            fatG: fatTotalG
        )
        self.note = note.flatMap { value in
            let normalized = Self.trim(value)
            return normalized.isEmpty ? nil : normalized
        }
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
                throw RecipeInputError.nonFinite(inputField(field))
            case let .negativeMacro(field):
                throw RecipeInputError.negative(inputField(field))
            default:
                throw RecipeInputError.notRepresentable(.calories)
            }
        }
    }

    private static func inputField(
        _ field: NutritionMacroField
    ) -> RecipeInputField {
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

public enum MealEntryRequestError: Error, Equatable, Sendable {
    case emptyAdhocName
    case nonFiniteQuantity
    case nonPositiveQuantity
    case invalidCategory
}

public enum MealEntrySourceRequest: Equatable, Sendable {
    case recipe(id: UUID, consumedServings: Decimal)
    case food(id: UUID, quantity: Decimal)
    case adhoc(
        name: String,
        quantity: Decimal,
        resolvedMacros: NutritionMacros
    )
}

public struct MealEntryCreateRequest: Equatable, Sendable {
    public let requestID: UUID
    public let date: Date
    public let category: MealCategory
    public let source: MealEntrySourceRequest

    public init(
        requestID: UUID,
        date: Date,
        category: MealCategory,
        source: MealEntrySourceRequest
    ) throws {
        self.requestID = requestID
        self.date = date
        self.category = try MealEntryRequestValidation.category(category)

        switch source {
        case let .recipe(id, consumedServings):
            self.source = .recipe(
                id: id,
                consumedServings: try MealEntryRequestValidation.quantity(
                    consumedServings
                )
            )
        case let .food(id, quantity):
            self.source = .food(
                id: id,
                quantity: try MealEntryRequestValidation.quantity(quantity)
            )
        case let .adhoc(name, quantity, resolvedMacros):
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw MealEntryRequestError.emptyAdhocName
            }
            self.source = .adhoc(
                name: name,
                quantity: try MealEntryRequestValidation.quantity(quantity),
                resolvedMacros: resolvedMacros
            )
        }
    }
}

public struct MealEntryUpdate: Equatable, Sendable {
    public let category: MealCategory
    public let quantity: Decimal

    public init(category: MealCategory, quantity: Decimal) throws {
        self.category = try MealEntryRequestValidation.category(category)
        self.quantity = try MealEntryRequestValidation.quantity(quantity)
    }
}

private enum MealEntryRequestValidation {
    static func category(_ value: MealCategory) throws -> MealCategory {
        do {
            return try MealCategory(
                kind: value.kind,
                customName: value.customName
            )
        } catch {
            throw MealEntryRequestError.invalidCategory
        }
    }

    static func quantity(_ value: Decimal) throws -> Decimal {
        do {
            return try NutritionQuantity(value).value
        } catch let error as NutritionNumericError {
            switch error {
            case .nonFiniteQuantity:
                throw MealEntryRequestError.nonFiniteQuantity
            case .nonPositiveQuantity:
                throw MealEntryRequestError.nonPositiveQuantity
            default:
                throw MealEntryRequestError.nonPositiveQuantity
            }
        }
    }
}
