import Foundation
@testable import NutritionKit
import XCTest

final class NutritionTargetPresentationTests: XCTestCase {
    func testEachMacroTargetIsIndependentAndTargetExcessRetainsRealProgress() throws {
        let consumed = try NutritionMacros(
            calories: 2_100,
            proteinG: 130,
            carbG: 180,
            fatG: 75
        )
        let targets = NutritionMacroTargets(
            calories: 2_000,
            proteinG: 120,
            carbG: nil,
            fatG: 80
        )

        let summary = try NutritionTargetSummary(consumed: consumed, targets: targets)

        XCTAssertEqual(
            summary.calories,
            .targeted(
                consumed: 2_100,
                target: 2_000,
                remaining: -100,
                progress: decimal("1.05")
            )
        )
        XCTAssertEqual(
            summary.proteinG,
            .targeted(
                consumed: 130,
                target: 120,
                remaining: -10,
                progress: decimal("1.083333")
            )
        )
        XCTAssertEqual(summary.carbG, .total(consumed: 180))
        XCTAssertEqual(
            summary.fatG,
            .targeted(
                consumed: 75,
                target: 80,
                remaining: 5,
                progress: decimal("0.9375")
            )
        )
        XCTAssertEqual(summary.calories.clampedProgress, 1)
        XCTAssertEqual(summary.proteinG.clampedProgress, 1)
        XCTAssertNil(summary.carbG.clampedProgress)
        XCTAssertEqual(summary.fatG.clampedProgress, decimal("0.9375"))
        assertEquatableSendable(summary)
    }

    func testNilZeroNegativeAndNonfiniteTargetsBecomeHonestTotals() throws {
        let consumed = try NutritionMacros(
            calories: 400,
            proteinG: 30,
            carbG: 50,
            fatG: 12
        )
        let targets = NutritionMacroTargets(
            calories: nil,
            proteinG: 0,
            carbG: -1,
            fatG: .nan
        )

        let summary = try NutritionTargetSummary(consumed: consumed, targets: targets)

        XCTAssertEqual(summary.calories, .total(consumed: 400))
        XCTAssertEqual(summary.proteinG, .total(consumed: 30))
        XCTAssertEqual(summary.carbG, .total(consumed: 50))
        XCTAssertEqual(summary.fatG, .total(consumed: 12))
    }

    func testEmptyDayKeepsExactZeroTotalsWithAndWithoutTargets() throws {
        let summary = try NutritionTargetSummary(
            consumed: .zero,
            targets: NutritionMacroTargets(
                calories: nil,
                proteinG: 120,
                carbG: nil,
                fatG: nil
            )
        )

        XCTAssertEqual(summary.calories, .total(consumed: 0))
        XCTAssertEqual(
            summary.proteinG,
            .targeted(consumed: 0, target: 120, remaining: 120, progress: 0)
        )
        XCTAssertEqual(summary.carbG, .total(consumed: 0))
        XCTAssertEqual(summary.fatG, .total(consumed: 0))
        XCTAssertEqual(summary.proteinG.clampedProgress, 0)
    }

    func testPublicTargetValuesRemainEquatableAndSendable() {
        let targets = NutritionMacroTargets(
            calories: 2_000,
            proteinG: 120,
            carbG: nil,
            fatG: nil
        )
        assertEquatableSendable(targets)
        assertEquatableSendable(NutritionTargetPresentation.total(consumed: 0))
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
