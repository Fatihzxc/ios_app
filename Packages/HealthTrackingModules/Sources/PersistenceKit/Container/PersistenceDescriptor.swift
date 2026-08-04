import Foundation

public struct PersistenceDescriptor: Equatable, Sendable {
    public let storeURL: URL?
    public let isStoredInMemoryOnly: Bool
    public let privateDatabaseIdentifier: String?

    public init(
        storeURL: URL?,
        isStoredInMemoryOnly: Bool,
        privateDatabaseIdentifier: String?
    ) {
        self.storeURL = storeURL
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.privateDatabaseIdentifier = privateDatabaseIdentifier
    }
}

public enum PersistenceConfigurationError: Error, Equatable, Sendable {
    case invalidPrivateDatabaseIdentifier
}
