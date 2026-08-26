import SwiftUI
import XCTest
@testable import DesignSystem

@MainActor
final class QuickEntryLayoutContractTests: XCTestCase {
    func testValidationIssueIsImmutablePresentationData() {
        let issue = QuickEntryValidationIssue(
            id: "weight.invalid",
            fieldIdentifier: "weight",
            localizedMessage: "Geçerli bir kilo girin.",
            accessibilityAnnouncement: "Kilo alanı geçersiz. Geçerli bir kilo girin."
        )

        XCTAssertEqual(issue.id, "weight.invalid")
        XCTAssertEqual(issue.fieldIdentifier, "weight")
        XCTAssertEqual(issue.localizedMessage, "Geçerli bir kilo girin.")
        XCTAssertEqual(
            issue.accessibilityAnnouncement,
            "Kilo alanı geçersiz. Geçerli bir kilo girin."
        )
    }

    func testActionLayoutTurnsVerticalAtAccessibilitySizes() {
        XCTAssertEqual(
            QuickEntryFormContract.actionLayout(isAccessibilitySize: false),
            .horizontal
        )
        XCTAssertEqual(
            QuickEntryFormContract.actionLayout(isAccessibilitySize: true),
            .vertical
        )
    }

    func testActionsAndKeyboardContractHaveStableAccessibleValues() {
        XCTAssertEqual(QuickEntryFormContract.minimumActionHeight, 52)
        XCTAssertEqual(
            QuickEntryFormContract.keyboardDismissAccessibilityIdentifier,
            "quick-entry.keyboard.dismiss"
        )
        XCTAssertEqual(
            QuickEntryFormContract.keyboardDismissLocalizationKey,
            "designSystem.quick-entry.keyboard.dismiss"
        )
    }

    func testScaffoldAcceptsFocusedScrollableContentAndExplicitActionLabels() {
        _ = QuickEntryFormScaffold(
            title: "Ölçüm ekle",
            primaryActionTitle: "Kaydet",
            primaryActionAccessibilityLabel: "Ölçümü kaydet",
            isPrimaryActionLoading: false,
            isPrimaryActionEnabled: true,
            secondaryActionTitle: "Vazgeç",
            secondaryActionAccessibilityLabel: "Ölçüm eklemeyi kapat",
            primaryAction: {},
            secondaryAction: {},
            content: { focus in
                TextField("Kilo", text: .constant(""))
                    .focused(focus)
            }
        )
    }

    func testReduceMotionUsesOpacityTransition() {
        XCTAssertEqual(
            AppMotion.transition(reduceMotion: true),
            .opacity(duration: AppMotion.microStateDuration)
        )
    }
}
