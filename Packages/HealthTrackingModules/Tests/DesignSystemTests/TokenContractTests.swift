import XCTest
@testable import DesignSystem

@MainActor
final class TokenContractTests: XCTestCase {
    func testSpacingAndRadiusContractsAreExact() {
        XCTAssertEqual(AppSpacing.scale, [2, 4, 8, 12, 16, 24, 32, 40])
        XCTAssertEqual(AppSpacing.screenHorizontal, 20)
        XCTAssertEqual(AppRadius.chip, 8)
        XCTAssertEqual(AppRadius.input, 10)
        XCTAssertEqual(AppRadius.action, 14)
        XCTAssertEqual(AppRadius.sheet, 16)
    }

    func testTypographyTokensAreAvailable() {
        _ = AppTypography.directive
        _ = AppTypography.titleLarge
        _ = AppTypography.titleMedium
        _ = AppTypography.body
        _ = AppTypography.label
        _ = AppTypography.caption
        _ = AppTypography.micro
        _ = AppTypography.numericHero
        _ = AppTypography.numericRow
    }

    func testMotionContractsRespectReduceMotion() {
        XCTAssertEqual(AppMotion.microStateDuration, 0.120, accuracy: 0.000_001)
        XCTAssertEqual(AppMotion.standardTransitionDuration, 0.220, accuracy: 0.000_001)
        XCTAssertEqual(AppMotion.pageTransitionDuration, 0.320, accuracy: 0.000_001)
        XCTAssertEqual(AppMotion.transition(reduceMotion: true), .opacity(duration: 0.120))
    }

    func testEmptyStateCarriesARequiredActionContract() {
        var actionInvocationCount = 0
        let state = FeatureState.empty(
            message: "Add your first record to begin.",
            actionTitle: "Add record",
            actionAccessibilityLabel: "Add your first record",
            action: { actionInvocationCount += 1 }
        )

        guard case let .empty(message, actionTitle, actionAccessibilityLabel, action) = state else {
            return XCTFail("The empty state must retain its required action contract.")
        }
        XCTAssertEqual(message, "Add your first record to begin.")
        XCTAssertEqual(actionTitle, "Add record")
        XCTAssertEqual(actionAccessibilityLabel, "Add your first record")
        action()
        XCTAssertEqual(actionInvocationCount, 1)
    }

    func testErrorStateSupportsRetryPresentAndAbsentPresentations() {
        _ = FeatureStateView(state: .error(message: "Could not load records."))
        _ = FeatureStateView(state: .error(message: "Could not load records."), retry: {})
    }
}
