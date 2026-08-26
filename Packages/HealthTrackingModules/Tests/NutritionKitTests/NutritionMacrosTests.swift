import Foundation
@testable import NutritionKit
import XCTest

final class NutritionMacrosTests: XCTestCase {
    func testDecimalAdditionAndSubtractionDoNotIntroduceBinaryDrift() throws {
        let oneTenth = try NutritionMacros(
            calories: decimal("0.1"),
            proteinG: decimal("0.1"),
            carbG: decimal("0.1"),
            fatG: decimal("0.1")
        )
        let twoTenths = try NutritionMacros(
            calories: decimal("0.2"),
            proteinG: decimal("0.2"),
            carbG: decimal("0.2"),
            fatG: decimal("0.2")
        )

        let sum = try oneTenth.adding(twoTenths)
        let restored = try sum.subtracting(oneTenth)

        XCTAssertEqual(
            sum,
            try NutritionMacros(
                calories: decimal("0.3"),
                proteinG: decimal("0.3"),
                carbG: decimal("0.3"),
                fatG: decimal("0.3")
            )
        )
        XCTAssertEqual(restored, twoTenths)
        assertEquatableSendable(sum)
    }

    func testCanonicalValuesUseSixPlaceBankersRoundingAtExactHalves() throws {
        let macros = try NutritionMacros(
            calories: decimal("1.2345675"),
            proteinG: decimal("1.2345685"),
            carbG: decimal("8.7654325"),
            fatG: decimal("8.7654315")
        )

        XCTAssertEqual(macros.calories, decimal("1.234568"))
        XCTAssertEqual(macros.proteinG, decimal("1.234568"))
        XCTAssertEqual(macros.carbG, decimal("8.765432"))
        XCTAssertEqual(macros.fatG, decimal("8.765432"))
    }

    func testScalingHasZeroAndOneIdentitiesAndDivisionRoundsDeterministically() throws {
        let macros = try NutritionMacros(
            calories: 1,
            proteinG: 2,
            carbG: 3,
            fatG: 4
        )

        XCTAssertEqual(try macros.scaled(by: 0), .zero)
        XCTAssertEqual(try macros.scaled(by: 1), macros)
        XCTAssertEqual(
            try macros.divided(by: 3),
            try NutritionMacros(
                calories: decimal("0.333333"),
                proteinG: decimal("0.666667"),
                carbG: 1,
                fatG: decimal("1.333333")
            )
        )
    }

    func testCombinedScaleAndDivisionRoundsOnlyTheFinalResult() throws {
        let macros = try NutritionMacros(
            calories: 10,
            proteinG: 20,
            carbG: 30,
            fatG: 40
        )

        XCTAssertEqual(
            try macros.scaled(by: 1, dividedBy: 3),
            try NutritionMacros(
                calories: decimal("3.333333"),
                proteinG: decimal("6.666667"),
                carbG: 10,
                fatG: decimal("13.333333")
            )
        )
        XCTAssertEqual(
            try macros.scaled(by: 3, dividedBy: 3),
            macros
        )
    }

    func testNormalizedAdditionIsAssociativeForCanonicalInputs() throws {
        let first = try macros("0.100001")
        let second = try macros("0.200002")
        let third = try macros("0.300003")

        let left = try first.adding(second).adding(third)
        let right = try first.adding(try second.adding(third))

        XCTAssertEqual(left, right)
        XCTAssertEqual(left.calories, decimal("0.600006"))
    }

    func testMacrosRejectNegativeAndNonfiniteFieldsWithStableSemanticErrors() throws {
        assertMacroError(
            .negativeMacro(.calories),
            calories: -1,
            proteinG: 0,
            carbG: 0,
            fatG: 0
        )
        assertMacroError(
            .negativeMacro(.proteinG),
            calories: 0,
            proteinG: -1,
            carbG: 0,
            fatG: 0
        )
        assertMacroError(
            .nonFiniteMacro(.carbG),
            calories: 0,
            proteinG: 0,
            carbG: .nan,
            fatG: 0
        )
        assertMacroError(
            .negativeMacro(.fatG),
            calories: 0,
            proteinG: 0,
            carbG: 0,
            fatG: -1
        )
    }

    func testQuantityAndServingValuesRequireFinitePositiveDecimals() throws {
        XCTAssertEqual(try NutritionQuantity(1).value, 1)
        XCTAssertEqual(try NutritionServingCount(decimal("0.5")).value, decimal("0.5"))

        assertThrows(.nonPositiveQuantity) { _ = try NutritionQuantity(0) }
        assertThrows(.nonPositiveQuantity) { _ = try NutritionQuantity(-1) }
        assertThrows(.nonFiniteQuantity) { _ = try NutritionQuantity(.nan) }
        assertThrows(.nonPositiveServingCount) { _ = try NutritionServingCount(0) }
        assertThrows(.nonPositiveServingCount) { _ = try NutritionServingCount(-1) }
        assertThrows(.nonFiniteServingCount) { _ = try NutritionServingCount(.nan) }

        assertEquatableSendable(try NutritionQuantity(1))
        assertEquatableSendable(try NutritionServingCount(1))
    }

    func testInvalidScaleDivisionAndOverflowFailInsteadOfProducingSilentValues() throws {
        let macros = try NutritionMacros(
            calories: 1,
            proteinG: 1,
            carbG: 1,
            fatG: 1
        )

        assertThrows(.negativeScale) { _ = try macros.scaled(by: -1) }
        assertThrows(.nonFiniteScale) { _ = try macros.scaled(by: .nan) }
        assertThrows(.divisionByZero) { _ = try macros.divided(by: 0) }
        assertThrows(.divisionByZero) { _ = try macros.divided(by: -1) }

        let huge = try NutritionMacros(
            calories: decimal("9E+127"),
            proteinG: 0,
            carbG: 0,
            fatG: 0
        )
        assertThrows(.arithmeticOverflow) { _ = try huge.scaled(by: 10) }
    }

    private func macros(_ value: String) throws -> NutritionMacros {
        let value = decimal(value)
        return try NutritionMacros(
            calories: value,
            proteinG: value,
            carbG: value,
            fatG: value
        )
    }

    private func assertMacroError(
        _ expected: NutritionNumericError,
        calories: Decimal,
        proteinG: Decimal,
        carbG: Decimal,
        fatG: Decimal,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try NutritionMacros(
                calories: calories,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? NutritionNumericError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func assertThrows(
        _ expected: NutritionNumericError,
        _ expression: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? NutritionNumericError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
