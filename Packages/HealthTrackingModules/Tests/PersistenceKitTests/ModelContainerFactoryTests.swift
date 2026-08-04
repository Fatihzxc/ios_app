import CoreModels
import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class ModelContainerFactoryTests: XCTestCase {
    func testV1SchemaHasApprovedVersionAndExactModelInventory() {
        XCTAssertEqual(HealthTrackingSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(HealthTrackingSchemaV1.models.count, 23)
        XCTAssertEqual(
            Set(HealthTrackingSchemaV1.models.map { String(describing: $0) }),
            [
                "UserProfile", "Program", "ProgramPhase", "WorkoutDayTemplate", "ExerciseTemplate",
                "WarmupItem", "CooldownItem", "WorkoutSession", "SetLog", "ProgramState",
                "BodyMetric", "ProgressPhoto", "SleepLog", "MoodLog", "PostureMetric",
                "HealthCheckReminder", "BloodworkResult", "Food", "Recipe", "DailyNutritionLog",
                "MealEntry", "AppReminder", "AppSetting"
            ]
        )
        XCTAssertEqual(HealthTrackingMigrationPlan.schemas.count, 1)
        XCTAssertTrue(HealthTrackingMigrationPlan.stages.isEmpty)
    }

    func testDescriptorsExpressEachPersistenceMode() throws {
        let localURL = URL(fileURLWithPath: "/tmp/health-tracking-local.store")

        XCTAssertEqual(
            try ModelContainerFactory.descriptor(for: .inMemory),
            PersistenceDescriptor(
                storeURL: nil,
                isStoredInMemoryOnly: true,
                privateDatabaseIdentifier: nil
            )
        )
        XCTAssertEqual(
            try ModelContainerFactory.descriptor(for: .local(storeURL: localURL)),
            PersistenceDescriptor(
                storeURL: localURL,
                isStoredInMemoryOnly: false,
                privateDatabaseIdentifier: nil
            )
        )
        XCTAssertEqual(
            try ModelContainerFactory.descriptor(
                for: .cloud(
                    storeURL: localURL,
                    privateDatabaseIdentifier: "iCloud.com.example.HealthTracking"
                )
            ),
            PersistenceDescriptor(
                storeURL: localURL,
                isStoredInMemoryOnly: false,
                privateDatabaseIdentifier: "iCloud.com.example.HealthTracking"
            )
        )
    }

    func testFactoryBuildsInMemoryAndLocalContainers() throws {
        _ = try ModelContainerFactory.make(for: .inMemory)

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        _ = try ModelContainerFactory.make(for: .local(storeURL: storeURL))
    }

    func testCloudModeRejectsBlankPrivateDatabaseIdentifier() {
        XCTAssertThrowsError(
            try ModelContainerFactory.descriptor(
                for: .cloud(
                    storeURL: URL(fileURLWithPath: "/tmp/health-tracking-cloud.store"),
                    privateDatabaseIdentifier: " \n\t "
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? PersistenceConfigurationError,
                .invalidPrivateDatabaseIdentifier
            )
        }
    }

    func testCloudSchemaProbeIsPassOrEntitlementBlocked() throws {
        do {
            _ = try ModelContainerFactory.make(
                for: .cloud(
                    storeURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("store"),
                    privateDatabaseIdentifier: "iCloud.com.fatihzxc.HealthTrackingApp"
                )
            )
        } catch {
            let message = String(describing: error).lowercased()
            let isSchemaFailure = ["schema", "default", "migration", "relationship", "attribute"]
                .contains { message.contains($0) }
            if isSchemaFailure {
                XCTFail("Cloud schema probe reported a schema/default error: \(error)")
                return
            }

            let isCapabilityFailure = [
                "entitlement",
                "icloud container",
                "cloudkit container",
                "not signed",
                "capability"
            ].contains { message.contains($0) }

            guard isCapabilityFailure else {
                XCTFail("Cloud schema probe failed before entitlement validation: \(error)")
                return
            }

            throw XCTSkip("BLOCKED Cloud capability probe: \(error)")
        }
    }
}
