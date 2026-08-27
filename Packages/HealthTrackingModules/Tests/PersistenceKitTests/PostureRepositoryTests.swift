import CoreModels
import Foundation
@testable import MetricsKit
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class PostureRepositoryTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testCreateFetchUpdateDeletePreserveZeroAndStableOrdering() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        var ids = [
            uuid("00000000-0000-4000-8000-000000000441"),
            uuid("00000000-0000-4000-8000-000000000442"),
        ]
        var timestamps = [date(20_000), date(21_000), date(22_000)]
        let repository = SwiftDataMetricsRepository(
            modelContext: context,
            now: { timestamps.removeFirst() },
            makeID: { ids.removeFirst() }
        )
        let older = try await repository.createPostureMetric(
            try input(date: date(10_000), score: 0, region: "Boyun")
        )
        let newer = try await repository.createPostureMetric(
            try input(date: date(11_000), score: 4, region: "Sağ kol")
        )

        let createdIDs = try await repository.fetchPostureMetrics().map(\.id)
        XCTAssertEqual(createdIDs, [newer.id, older.id])
        XCTAssertEqual(older.symptomScore, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PostureMetric>()), 2)

        let updated = try await repository.updatePostureMetric(
            id: older.id,
            expectedUpdatedAt: older.updatedAt,
            input: try input(date: date(12_000), score: 1, region: " Boyun ")
        )
        XCTAssertEqual(updated.id, older.id)
        XCTAssertEqual(updated.updatedAt, date(22_000))
        XCTAssertEqual(updated.region, "Boyun")

        try await repository.deletePostureMetric(
            id: updated.id,
            expectedUpdatedAt: updated.updatedAt
        )
        let remainingIDs = try await repository.fetchPostureMetrics().map(\.id)
        XCTAssertEqual(remainingIDs, [newer.id])
    }

    func testDuplicateInvalidAndGeneratedCollisionFailClosed() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let duplicateID = uuid("00000000-0000-4000-8000-000000000443")
        writer.insert(posture(id: duplicateID, score: 2))
        writer.insert(posture(id: duplicateID, score: 3))
        try writer.save()
        let duplicateRepository = SwiftDataMetricsRepository(
            modelContext: ModelContext(container)
        )

        do {
            _ = try await duplicateRepository.fetchPostureMetrics()
            XCTFail("Expected duplicate posture IDs to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryIntegrityError,
                .duplicatePostureMetricIDs(id: duplicateID, count: 2)
            )
        }

        let invalidContainer = try ModelContainerFactory.make(for: .inMemory)
        let invalidWriter = ModelContext(invalidContainer)
        let invalidID = uuid("00000000-0000-4000-8000-000000000444")
        invalidWriter.insert(posture(id: invalidID, score: 11))
        try invalidWriter.save()
        do {
            _ = try await SwiftDataMetricsRepository(
                modelContext: ModelContext(invalidContainer)
            ).fetchPostureMetrics()
            XCTFail("Expected invalid posture payload to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryIntegrityError,
                .invalidPersistedPostureMetric(id: invalidID)
            )
        }

        let collisionContainer = try ModelContainerFactory.make(for: .inMemory)
        let collisionWriter = ModelContext(collisionContainer)
        let collisionID = uuid("00000000-0000-4000-8000-000000000445")
        collisionWriter.insert(posture(id: collisionID, score: 1))
        try collisionWriter.save()
        let collisionRepository = SwiftDataMetricsRepository(
            modelContext: ModelContext(collisionContainer),
            makeID: { collisionID }
        )
        do {
            _ = try await collisionRepository.createPostureMetric(
                try input(date: date(10_000), score: 2, region: nil)
            )
            XCTFail("Expected generated posture ID collision.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryIntegrityError,
                .postureMetricIDCollision(id: collisionID)
            )
        }
    }

    func testExternalEventUpsertIsIdempotentAndRejectsDifferentPayloadForSameID() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let eventID = uuid("00000000-0000-4000-8000-000000000446")
        var saveCount = 0
        let repository = SwiftDataMetricsRepository(
            modelContext: context,
            now: { self.date(20_000) },
            save: {
                saveCount += 1
                try context.save()
            }
        )
        let event = try input(date: date(12_000), score: nil, region: "OHP")

        let first = try await repository.upsertPostureMetric(id: eventID, input: event)
        let retried = try await repository.upsertPostureMetric(id: eventID, input: event)

        XCTAssertEqual(first, retried)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PostureMetric>()), 1)

        do {
            _ = try await repository.upsertPostureMetric(
                id: eventID,
                input: try input(date: date(12_001), score: 8, region: "OHP")
            )
            XCTFail("An existing stable event ID must not overwrite a different payload.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryIntegrityError,
                .postureMetricUpsertCollision(id: eventID)
            )
        }
        XCTAssertEqual(saveCount, 1)
    }

    func testPostureMutationRequiresExactIDAndCurrentTimestamp() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let existingID = uuid("00000000-0000-4000-8000-000000000447")
        let missingID = uuid("00000000-0000-4000-8000-000000000448")
        let updatedAt = date(15_000)
        writer.insert(posture(id: existingID, updatedAt: updatedAt, score: 2))
        try writer.save()
        let repository = SwiftDataMetricsRepository(
            modelContext: ModelContext(container)
        )

        do {
            _ = try await repository.updatePostureMetric(
                id: missingID,
                expectedUpdatedAt: updatedAt,
                input: try input(date: date(15_100), score: 3, region: nil)
            )
            XCTFail("Expected missing posture update to fail.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryMutationError,
                .postureMetricNotFound(id: missingID)
            )
        }

        do {
            try await repository.deletePostureMetric(
                id: existingID,
                expectedUpdatedAt: date(14_999)
            )
            XCTFail("Expected stale posture delete to fail.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryMutationError,
                .stalePostureMetric(
                    id: existingID,
                    expectedUpdatedAt: date(14_999),
                    actualUpdatedAt: updatedAt
                )
            )
        }
        let preservedIDs = try await repository.fetchPostureMetrics().map(\.id)
        XCTAssertEqual(preservedIDs, [existingID])
    }

    func testExternalEventSaveFailureRollsBackSoTheSameStableEventCanRetry() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let eventID = uuid("00000000-0000-4000-8000-000000000451")
        var failsNextSave = true
        let repository = SwiftDataMetricsRepository(
            modelContext: context,
            now: { self.date(18_000) },
            save: {
                if failsNextSave {
                    failsNextSave = false
                    throw FixtureFailure.save
                }
                try context.save()
            },
            rollback: { context.rollback() }
        )
        let event = try input(date: date(17_500), score: nil, region: "OHP")

        do {
            _ = try await repository.upsertPostureMetric(id: eventID, input: event)
            XCTFail("Expected the first external-event save to roll back.")
        } catch {
            XCTAssertEqual(error as? MetricsRepositoryOperationError, .saveFailed)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PostureMetric>()), 0)

        let retried = try await repository.upsertPostureMetric(id: eventID, input: event)

        XCTAssertEqual(retried.id, eventID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PostureMetric>()), 1)
    }

    func testPostureCreateUpdateAndDeleteFailuresRollbackExactly() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let existingID = uuid("00000000-0000-4000-8000-000000000449")
        let createdID = uuid("00000000-0000-4000-8000-000000000450")
        let originalUpdatedAt = date(16_000)
        let writer = ModelContext(container)
        writer.insert(posture(id: existingID, updatedAt: originalUpdatedAt, score: 2))
        try writer.save()
        let context = ModelContext(container)
        let repository = SwiftDataMetricsRepository(
            modelContext: context,
            now: { self.date(17_000) },
            makeID: { createdID },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.createPostureMetric(
                try input(date: date(16_500), score: 3, region: nil)
            )
            XCTFail("Expected posture create rollback.")
        } catch {
            XCTAssertEqual(error as? MetricsRepositoryOperationError, .saveFailed)
        }

        do {
            _ = try await repository.updatePostureMetric(
                id: existingID,
                expectedUpdatedAt: originalUpdatedAt,
                input: try input(date: date(16_500), score: 4, region: nil)
            )
            XCTFail("Expected posture update rollback.")
        } catch {
            XCTAssertEqual(error as? MetricsRepositoryOperationError, .saveFailed)
        }

        do {
            try await repository.deletePostureMetric(
                id: existingID,
                expectedUpdatedAt: originalUpdatedAt
            )
            XCTFail("Expected posture delete rollback.")
        } catch {
            XCTAssertEqual(error as? MetricsRepositoryOperationError, .saveFailed)
        }

        let preserved = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<PostureMetric>()).first
        )
        XCTAssertEqual(preserved.id, existingID)
        XCTAssertEqual(preserved.symptomScore, 2)
        XCTAssertEqual(preserved.updatedAt, originalUpdatedAt)
    }

    private func input(
        date: Date,
        score: Int?,
        region: String?
    ) throws -> PostureMetricInput {
        try PostureMetricInput(
            date: date,
            wallTestPass: nil,
            symptomScore: score,
            region: region,
            note: nil
        )
    }

    private func posture(
        id: UUID,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 9_000),
        score: Int?
    ) -> PostureMetric {
        PostureMetric(
            id: id,
            createdAt: date(8_000),
            updatedAt: updatedAt,
            date: date(8_500),
            wallTestPass: nil,
            symptomScore: score,
            region: "Boyun",
            note: nil
        )
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: value)
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
