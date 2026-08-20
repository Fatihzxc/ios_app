import Foundation

public enum SeedLoadingError: Error, Equatable, Sendable {
    case saveFailed
    case duplicateMarkers(count: Int)
    case missingRequiredWorkoutDay(id: UUID)
}

@MainActor
public protocol SeedLoading: AnyObject {
    func seedIfNeeded(installedAt: Date) throws
}
