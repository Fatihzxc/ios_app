import Foundation
@testable import NutritionKit
import XCTest

final class FoodInputTests: XCTestCase {
    func testInputTrimsUnicodeWhitespaceAndNormalizesOptionalBrand() throws {
        let unbranded = try makeInput(
            name: "\u{2003}Yoğurt\u{00A0}",
            brand: " \u{2003}\n",
            servingSize: decimal("200.25"),
            servingUnit: "\u{00A0}g \n",
            calories: decimal("123.4567895"),
            proteinG: decimal("10.1234565"),
            carbG: decimal("20.0000004"),
            fatG: decimal("3.5"),
            fiberG: decimal("2.3456785")
        )

        XCTAssertEqual(unbranded.name, "Yoğurt")
        XCTAssertNil(unbranded.brand)
        XCTAssertEqual(unbranded.servingSize, decimal("200.25"))
        XCTAssertEqual(unbranded.servingUnit, "g")
        XCTAssertEqual(unbranded.macros.calories, decimal("123.456790"))
        XCTAssertEqual(unbranded.macros.proteinG, decimal("10.123456"))
        XCTAssertEqual(unbranded.macros.carbG, 20)
        XCTAssertEqual(unbranded.macros.fatG, decimal("3.5"))
        XCTAssertEqual(unbranded.fiberG, decimal("2.345678"))

        let branded = try makeInput(brand: "  Acme Besin  ")
        XCTAssertEqual(branded.brand, "Acme Besin")
        assertEquatableSendable(branded)
    }

    func testNameAndServingUnitCannotBeEmptyAfterUnicodeTrim() {
        assertInputError(.emptyName) {
            try makeInput(name: " \u{2003}\n")
        }
        assertInputError(.emptyServingUnit) {
            try makeInput(servingUnit: "\u{00A0}\t")
        }
    }

    func testServingSizeMustBeFiniteAndPositive() {
        assertInputError(.nonFinite(.servingSize)) {
            try makeInput(servingSize: .nan)
        }
        assertInputError(.nonPositiveServingSize) {
            try makeInput(servingSize: 0)
        }
        assertInputError(.nonPositiveServingSize) {
            try makeInput(servingSize: -1)
        }
    }

    func testMacroAndFiberValuesMustBeFiniteAndNonnegative() {
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
        assertInputError(.nonFinite(.fiberG)) {
            try makeInput(fiberG: .nan)
        }
        assertInputError(.negative(.fiberG)) {
            try makeInput(fiberG: -1)
        }
    }

    func testZeroMacrosAndAbsentFiberAreValid() throws {
        let input = try makeInput(
            servingSize: decimal("0.1"),
            calories: 0,
            proteinG: 0,
            carbG: 0,
            fatG: 0,
            fiberG: nil
        )

        XCTAssertEqual(input.macros, .zero)
        XCTAssertNil(input.fiberG)
    }

    private func makeInput(
        name: String = "Besin",
        brand: String? = nil,
        servingSize: Decimal = 1,
        servingUnit: String = "porsiyon",
        calories: Decimal = 100,
        proteinG: Decimal = 10,
        carbG: Decimal = 15,
        fatG: Decimal = 2,
        fiberG: Decimal? = nil
    ) throws -> FoodInput {
        try FoodInput(
            name: name,
            brand: brand,
            servingSize: servingSize,
            servingUnit: servingUnit,
            caloriesPerServing: calories,
            proteinG: proteinG,
            carbG: carbG,
            fatG: fatG,
            fiberG: fiberG
        )
    }

    private func assertInputError(
        _ expected: FoodInputError,
        _ expression: () throws -> FoodInput,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? FoodInputError, expected, file: file, line: line)
        }
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
