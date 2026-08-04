import SwiftData

public enum HealthTrackingMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [HealthTrackingSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
