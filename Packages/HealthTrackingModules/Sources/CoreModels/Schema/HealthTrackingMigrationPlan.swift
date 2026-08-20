import SwiftData

public enum HealthTrackingMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [HealthTrackingSchemaV1.self, HealthTrackingSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: HealthTrackingSchemaV1.self,
                toVersion: HealthTrackingSchemaV2.self
            )
        ]
    }
}
