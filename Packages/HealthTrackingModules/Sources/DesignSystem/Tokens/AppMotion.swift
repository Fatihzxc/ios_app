import Foundation
import SwiftUI

public enum MotionTransition: Equatable, Sendable {
    case standard(duration: TimeInterval)
    case opacity(duration: TimeInterval)
}

public enum AppMotion {
    public static let microStateDuration: TimeInterval = 0.120
    public static let standardTransitionDuration: TimeInterval = 0.220
    public static let pageTransitionDuration: TimeInterval = 0.320

    public static func transition(reduceMotion: Bool) -> MotionTransition {
        reduceMotion ? .opacity(duration: microStateDuration) : .standard(duration: standardTransitionDuration)
    }

    public static func animation(reduceMotion: Bool) -> Animation {
        switch transition(reduceMotion: reduceMotion) {
        case let .standard(duration): .easeInOut(duration: duration)
        case let .opacity(duration): .easeInOut(duration: duration)
        }
    }
}
