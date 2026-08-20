import CoreModels
import Foundation
import SwiftData
import XCTest

@MainActor
final class SchemaV2MigrationTests: XCTestCase {
    func testV2AddsOnlyWorkoutSessionProgressWhileV1InventoryStaysFrozen() {
        let v1Names = Set(HealthTrackingSchemaV1.models.map { String(describing: $0) })
        let v2Names = Set(HealthTrackingSchemaV2.models.map { String(describing: $0) })

        XCTAssertEqual(HealthTrackingSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(HealthTrackingSchemaV1.models.count, 23)
        XCTAssertEqual(HealthTrackingSchemaV2.versionIdentifier, Schema.Version(1, 1, 0))
        XCTAssertEqual(HealthTrackingSchemaV2.models.count, 24)
        XCTAssertEqual(v2Names.subtracting(v1Names), ["WorkoutSessionProgress"])
        XCTAssertTrue(v1Names.isSubset(of: v2Names))
        XCTAssertEqual(HealthTrackingMigrationPlan.schemas.count, 2)
        XCTAssertEqual(HealthTrackingMigrationPlan.stages.count, 1)
    }

    func testProgressModelRoundTripsAllScalarState() throws {
        let container = try makeContainer(schema: HealthTrackingSchemaV2.self)
        let context = ModelContext(container)
        let date = Date(timeIntervalSinceReferenceDate: 12_000)
        let progressID = uuid("00000000-0000-0000-0000-000000000010")
        let sessionID = uuid("00000000-0000-0000-0000-000000000011")
        let exerciseID = uuid("00000000-0000-0000-0000-000000000012")
        let warmupID = uuid("00000000-0000-0000-0000-000000000013")
        let cooldownID = uuid("00000000-0000-0000-0000-000000000014")
        let progress = WorkoutSessionProgress(
            id: progressID,
            createdAt: date,
            updatedAt: date,
            workoutSessionId: sessionID,
            stage: .movement,
            currentExerciseTemplateId: exerciseID,
            completedWarmupItemIdsData: try WorkoutSessionProgressCodec.encode([warmupID]),
            completedCooldownItemIdsData: try WorkoutSessionProgressCodec.encode([cooldownID]),
            warmupDisposition: .completed,
            cooldownDisposition: .skipped
        )
        context.insert(progress)
        try context.save()

        let loaded = try XCTUnwrap(
            ModelContext(container).fetch(
                FetchDescriptor<WorkoutSessionProgress>(
                    predicate: #Predicate { $0.id == progressID }
                )
            ).first
        )

        XCTAssertEqual(loaded.id, progressID)
        XCTAssertEqual(loaded.createdAt, date)
        XCTAssertEqual(loaded.updatedAt, date)
        XCTAssertEqual(loaded.workoutSessionId, sessionID)
        XCTAssertEqual(loaded.stage, .movement)
        XCTAssertEqual(loaded.currentExerciseTemplateId, exerciseID)
        XCTAssertEqual(
            try WorkoutSessionProgressCodec.decode(loaded.completedWarmupItemIdsData),
            [warmupID]
        )
        XCTAssertEqual(
            try WorkoutSessionProgressCodec.decode(loaded.completedCooldownItemIdsData),
            [cooldownID]
        )
        XCTAssertEqual(loaded.warmupDisposition, .completed)
        XCTAssertEqual(loaded.cooldownDisposition, .skipped)
    }

    func testRealV1DiskStoreOpensAsV2AndRetainsFoundationRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("migration.store")
        let profileID = uuid("00000000-0000-0000-0000-000000000021")
        let programID = uuid("00000000-0000-0000-0000-000000000022")
        let sessionID = uuid("00000000-0000-0000-0000-000000000023")
        let setID = uuid("00000000-0000-0000-0000-000000000024")

        try writeV1Store(
            at: storeURL,
            profileID: profileID,
            programID: programID,
            sessionID: sessionID,
            setID: setID
        )

        let container = try makeContainer(
            schema: HealthTrackingSchemaV2.self,
            storeURL: storeURL,
            migrationPlan: HealthTrackingMigrationPlan.self
        )
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetch(FetchDescriptor<UserProfile>()).map(\.id), [profileID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Program>()).map(\.id), [programID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id), [sessionID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).map(\.id), [setID])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSessionProgress>()), 0)
    }

    private func writeV1Store(
        at storeURL: URL,
        profileID: UUID,
        programID: UUID,
        sessionID: UUID,
        setID: UUID
    ) throws {
        let container = try makeContainer(
            schema: HealthTrackingSchemaV1.self,
            storeURL: storeURL
        )
        let context = ModelContext(container)
        let profile = UserProfile(id: profileID, displayName: "Ada")
        let program = Program(id: programID, name: "Foundation", isActive: true)
        let session = WorkoutSession(
            id: sessionID,
            status: .inProgress,
            workoutDayTemplateId: UUID()
        )
        let setLog = SetLog(
            id: setID,
            exerciseTemplateId: UUID(),
            setIndex: 1,
            weightKg: 10,
            reps: 8,
            workoutSession: session
        )
        context.insert(profile)
        context.insert(program)
        context.insert(session)
        context.insert(setLog)
        try context.save()
    }

    private func makeContainer<Version: VersionedSchema>(
        schema: Version.Type,
        storeURL: URL? = nil,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil
    ) throws -> ModelContainer {
        let modelSchema = Schema(versionedSchema: schema)
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(
            for: modelSchema,
            migrationPlan: migrationPlan,
            configurations: [configuration]
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
