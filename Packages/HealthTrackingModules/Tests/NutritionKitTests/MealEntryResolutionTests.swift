import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

final class MealEntryResolutionTests: XCTestCase {
    func testValidatedCreateRequestCanonicalizesAdhocNameAndExactlyOneSource() throws {
        let requestID = uuid("00000000-0000-4000-8000-000000000701")
        let date = Date(timeIntervalSinceReferenceDate: 7_000)
        let category = try MealCategory(
            kind: .custom,
            customName: "  İkinci kahvaltı  "
        )
        let macros = try makeMacros(calories: 250, proteinG: 20, carbG: 30, fatG: 8)

        let request = try MealEntryCreateRequest(
            requestID: requestID,
            date: date,
            category: category,
            source: .adhoc(
                name: "  Ev yapımı kase  ",
                quantity: 2,
                resolvedMacros: macros
            )
        )

        XCTAssertEqual(request.requestID, requestID)
        XCTAssertEqual(request.date, date)
        XCTAssertEqual(request.category.customName, "İkinci kahvaltı")
        XCTAssertEqual(
            request.source,
            .adhoc(name: "Ev yapımı kase", quantity: 2, resolvedMacros: macros)
        )
        assertEquatableSendable(request)
    }

    func testCreateRequestRejectsEmptyAdhocNameAndInvalidQuantities() throws {
        let category = try MealCategory(kind: .dinner)
        let macros = try makeMacros()

        assertRequestError(.emptyAdhocName) {
            try makeRequest(
                category: category,
                source: .adhoc(name: " \n ", quantity: 1, resolvedMacros: macros)
            )
        }
        assertRequestError(.nonPositiveQuantity) {
            try makeRequest(category: category, source: .recipe(id: UUID(), consumedServings: 0))
        }
        assertRequestError(.nonFiniteQuantity) {
            try makeRequest(category: category, source: .food(id: UUID(), quantity: .nan))
        }
        assertRequestError(.nonPositiveQuantity) {
            try makeRequest(
                category: category,
                source: .adhoc(name: "Kase", quantity: -1, resolvedMacros: macros)
            )
        }
    }

    func testUpdateCanonicalizesCategoryAndRequiresPositiveFiniteQuantity() throws {
        let update = try MealEntryUpdate(
            category: MealCategory(kind: .custom, customName: "  Gece  "),
            quantity: decimal("1.25")
        )

        XCTAssertEqual(update.category.customName, "Gece")
        XCTAssertEqual(update.quantity, decimal("1.25"))
        XCTAssertThrowsError(
            try MealEntryUpdate(
                category: MealCategory(kind: .lunch),
                quantity: 0
            )
        ) { error in
            XCTAssertEqual(error as? MealEntryRequestError, .nonPositiveQuantity)
        }
        XCTAssertThrowsError(
            try MealEntryUpdate(
                category: MealCategory(kind: .lunch),
                quantity: .nan
            )
        ) { error in
            XCTAssertEqual(error as? MealEntryRequestError, .nonFiniteQuantity)
        }
        assertEquatableSendable(update)
    }

    func testRecipeFoodAndAdhocResolutionUseTheirDistinctScalingContracts() throws {
        let recipe = RecipeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000711"),
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            name: "Tarif",
            category: try MealCategory(kind: .dinner),
            servings: 3,
            isDirectMacros: true,
            totalMacros: try makeMacros(
                calories: 10,
                proteinG: 20,
                carbG: 30,
                fatG: 40
            ),
            note: nil
        )
        let food = FoodSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000712"),
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            name: "Besin",
            brand: nil,
            servingSize: 100,
            servingUnit: "g",
            macros: try makeMacros(
                calories: 100,
                proteinG: 8,
                carbG: 12,
                fatG: 4
            ),
            fiberG: nil,
            source: .userCreated
        )
        let adhoc = try makeMacros(
            calories: 275,
            proteinG: 17,
            carbG: 31,
            fatG: 9
        )

        XCTAssertEqual(
            try MealEntryMacroResolver.recipe(recipe, consumedServings: 1),
            try makeMacros(
                calories: decimal("3.333333"),
                proteinG: decimal("6.666667"),
                carbG: 10,
                fatG: decimal("13.333333")
            )
        )
        XCTAssertEqual(
            try MealEntryMacroResolver.food(food, quantity: decimal("2.5")),
            try makeMacros(calories: 250, proteinG: 20, carbG: 30, fatG: 10)
        )
        XCTAssertEqual(
            try MealEntryMacroResolver.adhoc(
                resolvedMacros: adhoc,
                quantity: 2
            ),
            adhoc,
            "Ad-hoc values are already the final total for the entered quantity."
        )
    }

    func testSnapshotRescaleUsesNewToOldQuantityWithoutEarlyRatioRounding() throws {
        let original = try makeMacros(
            calories: 10,
            proteinG: 20,
            carbG: 30,
            fatG: 40
        )

        let rescaled = try MealEntryMacroResolver.rescaleSnapshot(
            original,
            from: 3,
            to: 1
        )

        XCTAssertEqual(
            rescaled,
            try makeMacros(
                calories: decimal("3.333333"),
                proteinG: decimal("6.666667"),
                carbG: 10,
                fatG: decimal("13.333333")
            )
        )
        XCTAssertThrowsError(
            try MealEntryMacroResolver.rescaleSnapshot(original, from: 0, to: 1)
        ) { error in
            XCTAssertEqual(error as? NutritionNumericError, .nonPositiveQuantity)
        }
        XCTAssertThrowsError(
            try MealEntryMacroResolver.rescaleSnapshot(original, from: 1, to: .nan)
        ) { error in
            XCTAssertEqual(error as? NutritionNumericError, .nonFiniteQuantity)
        }
    }

    private func makeRequest(
        category: MealCategory,
        source: MealEntrySourceRequest
    ) throws -> MealEntryCreateRequest {
        try MealEntryCreateRequest(
            requestID: uuid("00000000-0000-4000-8000-000000000799"),
            date: Date(timeIntervalSinceReferenceDate: 100),
            category: category,
            source: source
        )
    }

    private func assertRequestError(
        _ expected: MealEntryRequestError,
        _ expression: () throws -> MealEntryCreateRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? MealEntryRequestError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func makeMacros(
        calories: Decimal = 400,
        proteinG: Decimal = 30,
        carbG: Decimal = 40,
        fatG: Decimal = 12
    ) throws -> NutritionMacros {
        try NutritionMacros(
            calories: calories,
            proteinG: proteinG,
            carbG: carbG,
            fatG: fatG
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
