import CoreModels
import Foundation

public struct FoodSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let name: String
    public let brand: String?
    public let servingSize: Decimal
    public let servingUnit: String
    public let macros: NutritionMacros
    public let fiberG: Decimal?
    public let source: FoodSource

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        name: String,
        brand: String?,
        servingSize: Decimal,
        servingUnit: String,
        macros: NutritionMacros,
        fiberG: Decimal?,
        source: FoodSource
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.brand = brand
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        self.macros = macros
        self.fiberG = fiberG
        self.source = source
    }
}

public enum FoodRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateFoodIDs(id: UUID, count: Int)
    case foodIDCollision(id: UUID)
    case invalidPersistedFood(id: UUID)
}

public enum FoodRepositoryMutationError: Error, Equatable, Sendable {
    case foodNotFound(id: UUID)
    case unsupportedMutationSource(id: UUID, source: FoodSource)
    case invalidInput
}

@MainActor
public protocol FoodLibraryRepository {
    func fetchFoods(matching query: String) async throws -> [FoodSnapshot]
    func createFood(_ input: FoodInput) async throws -> FoodSnapshot
    func updateFood(id: UUID, input: FoodInput) async throws -> FoodSnapshot
    func deleteFood(id: UUID) async throws
}

package enum FoodSearch {
    private static let locale = Locale(identifier: "en_US_POSIX")

    package static func results(
        _ foods: [FoodSnapshot],
        matching query: String
    ) -> [FoodSnapshot] {
        let query = normalized(query)
        return foods
            .filter { food in
                query.isEmpty
                    || normalized(food.name).contains(query)
                    || food.brand.map { normalized($0).contains(query) } == true
            }
            .sorted(by: ordered)
    }

    package static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            )
            .lowercased(with: locale)
    }

    private static func ordered(_ lhs: FoodSnapshot, _ rhs: FoodSnapshot) -> Bool {
        let lhsName = normalized(lhs.name)
        let rhsName = normalized(rhs.name)
        if lhsName != rhsName { return lhsName < rhsName }
        let lhsBrand = lhs.brand.map(normalized) ?? ""
        let rhsBrand = rhs.brand.map(normalized) ?? ""
        if lhsBrand != rhsBrand { return lhsBrand < rhsBrand }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
