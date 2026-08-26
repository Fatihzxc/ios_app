import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

final class RecipeInputTests: XCTestCase {
    func testInputCanonicalizesIdentityCategoryNoteAndTotalMacros() throws {
        let input = try makeInput(
            name: "\u{2003}Akşam Kasesi\u{00A0}",
            category: MealCategory(
                kind: .custom,
                customName: "\u{00A0}Gece öğünü\n"
            ),
            servings: decimal("3.5"),
            calories: decimal("123.4567895"),
            proteinG: decimal("10.1234565"),
            carbG: decimal("20.0000004"),
            fatG: decimal("3.5"),
            note: "\u{2003}Önceden hazırla\n"
        )

        XCTAssertEqual(input.name, "Akşam Kasesi")
        XCTAssertEqual(input.category.kind, .custom)
        XCTAssertEqual(input.category.customName, "Gece öğünü")
        XCTAssertEqual(input.servings, decimal("3.5"))
        XCTAssertEqual(input.totalMacros.calories, decimal("123.456790"))
        XCTAssertEqual(input.totalMacros.proteinG, decimal("10.123456"))
        XCTAssertEqual(input.totalMacros.carbG, 20)
        XCTAssertEqual(input.totalMacros.fatG, decimal("3.5"))
        XCTAssertEqual(input.note, "Önceden hazırla")

        let withoutNote = try makeInput(note: " \u{2003}\n")
        XCTAssertNil(withoutNote.note)
        assertEquatableSendable(input)
    }

    func testNameCannotBeEmptyAfterUnicodeWhitespaceTrim() {
        assertInputError(.emptyName) {
            try makeInput(name: " \u{2003}\u{00A0}\n")
        }
    }

    func testServingsMustBeFiniteAndPositive() {
        assertInputError(.nonFinite(.servings)) {
            try makeInput(servings: .nan)
        }
        assertInputError(.nonPositiveServings) {
            try makeInput(servings: 0)
        }
        assertInputError(.nonPositiveServings) {
            try makeInput(servings: -1)
        }
    }

    func testTotalMacrosMustBeFiniteAndNonnegative() {
        assertInputError(.nonFinite(.calories)) {
            try makeInput(calories: .nan)
        }
        assertInputError(.negative(.proteinG)) {
            try makeInput(proteinG: -1)
        }
        assertInputError(.nonFinite(.carbG)) {
            try makeInput(carbG: .nan)
        }
        assertInputError(.negative(.fatG)) {
            try makeInput(fatG: -1)
        }

        XCTAssertNoThrow(
            try makeInput(
                calories: 0,
                proteinG: 0,
                carbG: 0,
                fatG: 0
            )
        )
    }

    func testMealCategoryCanonicalizesCustomNameAndRejectsInvalidShapes() throws {
        let custom = try MealCategory(
            kind: .custom,
            customName: "\u{2003}İkinci kahvaltı\u{00A0}"
        )
        XCTAssertEqual(custom.customName, "İkinci kahvaltı")

        XCTAssertThrowsError(try MealCategory(kind: .custom, customName: " \n"))
        XCTAssertThrowsError(
            try MealCategory(kind: .breakfast, customName: "Kahvaltı")
        )
        XCTAssertNoThrow(try MealCategory(kind: .breakfast))
    }

    func testResolvedMacrosUseWholeYieldWithoutRoundingTheRatioEarly() throws {
        let input = try makeInput(
            servings: 3,
            calories: 10,
            proteinG: 20,
            carbG: 30,
            fatG: 40
        )
        let snapshot = RecipeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000401"),
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            name: input.name,
            category: input.category,
            servings: input.servings,
            isDirectMacros: true,
            totalMacros: input.totalMacros,
            note: input.note
        )

        XCTAssertEqual(
            try snapshot.resolvedMacros(consumedServings: 1),
            try NutritionMacros(
                calories: decimal("3.333333"),
                proteinG: decimal("6.666667"),
                carbG: 10,
                fatG: decimal("13.333333")
            )
        )
        XCTAssertTrue(snapshot.isDirectMacros)
        assertEquatableSendable(snapshot)
    }

    private func makeInput(
        name: String = "Tarif",
        category: MealCategory? = nil,
        servings: Decimal = 2,
        calories: Decimal = 400,
        proteinG: Decimal = 30,
        carbG: Decimal = 40,
        fatG: Decimal = 12,
        note: String? = nil
    ) throws -> RecipeInput {
        try RecipeInput(
            name: name,
            category: category ?? MealCategory(kind: .dinner),
            servings: servings,
            caloriesTotal: calories,
            proteinTotalG: proteinG,
            carbTotalG: carbG,
            fatTotalG: fatG,
            note: note
        )
    }

    private func assertInputError(
        _ expected: RecipeInputError,
        _ expression: () throws -> RecipeInput,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? RecipeInputError, expected, file: file, line: line)
        }
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
