@testable import DesignSystem
import XCTest

final class MedicalSafetyMotionPolicyTests: XCTestCase {
    private enum TransitionProbe: Equatable {
        case identity
        case opacity
    }

    // Mutation caught: reversing the generic selection would give every SwiftUI
    // consumer opacity under Reduce Motion and identity under the default setting.
    func testReduceMotionSelectsIdentityAndDefaultSelectsOpacity() {
        XCTAssertEqual(
            MedicalSafetyMotionPolicy.transition(
                reduceMotion: true,
                identity: TransitionProbe.identity,
                opacity: TransitionProbe.opacity
            ),
            .identity
        )
        XCTAssertEqual(
            MedicalSafetyMotionPolicy.transition(
                reduceMotion: false,
                identity: TransitionProbe.identity,
                opacity: TransitionProbe.opacity
            ),
            .opacity
        )
    }
}
