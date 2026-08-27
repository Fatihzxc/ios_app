@testable import DesignSystem
import XCTest

final class MedicalSafetyFocusPolicyTests: XCTestCase {
    // Mutation caught: returning a fixed false value would leave a newly inserted
    // L2 heading visible but never request accessibility focus at the consumer boundary.
    func testLevelTwoAppearanceActivatesHeadingFocusAndRemovalClearsIt() {
        XCTAssertTrue(
            MedicalSafetyFocusPolicy.headingFocused(isLevelTwoPresented: true)
        )
        XCTAssertFalse(
            MedicalSafetyFocusPolicy.headingFocused(isLevelTwoPresented: false)
        )
    }
}
