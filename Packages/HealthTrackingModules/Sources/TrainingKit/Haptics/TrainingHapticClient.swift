import Foundation

public enum TrainingHapticFeedback: Equatable, Sendable {
    case mediumImpact
    case selection
    case success
    case warning
    case error
}

public enum TrainingHapticEvent: Equatable, Sendable {
    case setSaved
    case stepperChanged
    case personalRecord(isNew: Bool)
    case phaseTransition(isConfirmed: Bool)
    case safetyStop
    case deload
    case validationError
    case repositoryError
}

@MainActor
public protocol TrainingHapticClient: AnyObject {
    func play(_ feedback: TrainingHapticFeedback)
}

@MainActor
public protocol TrainingHapticPreferenceStore: AnyObject {
    func loadHapticsEnabled() throws -> Bool
    func saveHapticsEnabled(_ isEnabled: Bool) throws
}
