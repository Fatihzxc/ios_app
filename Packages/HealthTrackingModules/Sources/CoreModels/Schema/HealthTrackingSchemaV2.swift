import SwiftData

public enum HealthTrackingSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 1, 0)
    }

    public static var models: [any PersistentModel.Type] {
        HealthTrackingSchemaV1.models + [WorkoutSessionProgress.self]
    }
}
