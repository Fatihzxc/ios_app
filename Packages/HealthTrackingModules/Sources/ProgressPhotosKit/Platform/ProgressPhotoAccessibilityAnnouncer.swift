import Foundation
import UIKit

@MainActor
public protocol ProgressPhotoAccessibilityAnnouncing {
    func announce(_ message: String)
}

@MainActor
public struct SystemProgressPhotoAccessibilityAnnouncer:
    ProgressPhotoAccessibilityAnnouncing {
    public init() {}

    public func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
