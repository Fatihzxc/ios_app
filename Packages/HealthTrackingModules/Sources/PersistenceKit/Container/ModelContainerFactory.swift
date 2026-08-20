import CoreModels
import SwiftData

@MainActor
public enum ModelContainerFactory {
    public static func descriptor(for mode: PersistenceMode) throws -> PersistenceDescriptor {
        switch mode {
        case .inMemory:
            return PersistenceDescriptor(
                storeURL: nil,
                isStoredInMemoryOnly: true,
                privateDatabaseIdentifier: nil
            )
        case let .local(storeURL):
            return PersistenceDescriptor(
                storeURL: storeURL,
                isStoredInMemoryOnly: false,
                privateDatabaseIdentifier: nil
            )
        case let .cloud(storeURL, privateDatabaseIdentifier):
            guard !privateDatabaseIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PersistenceConfigurationError.invalidPrivateDatabaseIdentifier
            }
            return PersistenceDescriptor(
                storeURL: storeURL,
                isStoredInMemoryOnly: false,
                privateDatabaseIdentifier: privateDatabaseIdentifier
            )
        }
    }

    public static func make(for mode: PersistenceMode) throws -> ModelContainer {
        let descriptor = try descriptor(for: mode)
        let configuration: ModelConfiguration

        if descriptor.isStoredInMemoryOnly {
            configuration = ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else if let privateDatabaseIdentifier = descriptor.privateDatabaseIdentifier,
                  let storeURL = descriptor.storeURL {
            configuration = ModelConfiguration(
                url: storeURL,
                cloudKitDatabase: .private(privateDatabaseIdentifier)
            )
        } else if let storeURL = descriptor.storeURL {
            configuration = ModelConfiguration(
                url: storeURL,
                cloudKitDatabase: .none
            )
        } else {
            preconditionFailure("A non-memory persistence descriptor requires a store URL.")
        }

        let schema = Schema(versionedSchema: HealthTrackingSchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: HealthTrackingMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
