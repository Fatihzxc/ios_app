import Foundation

public enum SeedLoadingError: Error, Equatable, Sendable {
    case saveFailed
    case duplicateMarkers(count: Int)
}

@MainActor
public protocol SeedLoading: AnyObject {
    func seedIfNeeded(installedAt: Date) throws
}
