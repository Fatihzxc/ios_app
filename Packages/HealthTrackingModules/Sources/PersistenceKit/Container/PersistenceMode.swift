import Foundation

public enum PersistenceMode: Equatable, Sendable {
    case inMemory
    case local(storeURL: URL)
    case cloud(storeURL: URL, privateDatabaseIdentifier: String)
}
