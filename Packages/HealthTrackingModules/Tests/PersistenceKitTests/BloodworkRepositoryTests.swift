import CoreModels
import Foundation
@testable import HealthChecksKit
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class BloodworkRepositoryTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testCRUDTrimsValuesAndReturnsStableDateIDOrdering() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        var identifiers = [uuid(602), uuid(601)]
        var timestamps = [date(10_000), date(11_000), date(12_000)]
        let repository = SwiftDataBloodworkRepository(
            modelContext: context,
            now: { timestamps.removeFirst() },
            makeID: { identifiers.removeFirst() }
        )

        let older = try await repository.createResult(
            try input(date: date(20_000), marker: "  Ferritin ", value: 18, unit: " ng/mL ")
        ).snapshot
        let newer = try await repository.createResult(
            try input(date: date(30_000), marker: "D vitamini", value: 24, unit: "ng/mL")
        ).snapshot

        XCTAssertEqual(older.marker, "Ferritin")
        XCTAssertEqual(older.unit, "ng/mL")
        XCTAssertEqual(try await repository.fetchResults().map(\.id), [newer.id, older.id])

        let updated = try await repository.updateResult(
            id: older.id,
            expectedUpdatedAt: older.updatedAt,
            input: try input(
                date: date(40_000),
                marker: " Ferritin ",
                value: 22,
                unit: " ng/mL ",
                note: " Tekrar "
            )
        )
        XCTAssertEqual(updated.updatedAt, date(12_000))
        XCTAssertEqual(updated.note, "Tekrar")
        XCTAssertEqual(try await repository.fetchResults().map(\.id), [updated.id, newer.id])

        try await repository.deleteResult(
            id: updated.id,
            expectedUpdatedAt: updated.updatedAt
        )
        XCTAssertEqual(try await repository.fetchResults().map(\.id), [newer.id])
    }

    func testDuplicateInvalidRowsAndGeneratedCollisionFailClosed() async throws {
        let duplicateContainer = try ModelContainerFactory.make(for: .inMemory)
        let duplicateWriter = ModelContext(duplicateContainer)
        let duplicateID = uuid(603)
        duplicateWriter.insert(result(id: duplicateID, marker: "Bir"))
        duplicateWriter.insert(result(id: duplicateID, marker: "İki"))
        try duplicateWriter.save()

        do {
            _ = try await SwiftDataBloodworkRepository(
                modelContext: ModelContext(duplicateContainer)
            ).fetchResults()
            XCTFail("Duplicate bloodwork IDs must fail closed.")
        } catch {
            XCTAssertEqual(
                error as? BloodworkRepositoryIntegrityError,
                .duplicateResultIDs(id: duplicateID, count: 2)
            )
        }

        let invalidContainer = try ModelContainerFactory.make(for: .inMemory)
        let invalidWriter = ModelContext(invalidContainer)
        let invalidID = uuid(604)
        invalidWriter.insert(result(id: invalidID, marker: "  "))
        try invalidWriter.save()
        do {
            _ = try await SwiftDataBloodworkRepository(
                modelContext: ModelContext(invalidContainer)
            ).fetchResults()
            XCTFail("Invalid persisted values must fail closed.")
        } catch {
            XCTAssertEqual(
                error as? BloodworkRepositoryIntegrityError,
                .invalidPersistedResult(id: invalidID)
            )
        }

        let collisionContainer = try ModelContainerFactory.make(for: .inMemory)
        let collisionWriter = ModelContext(collisionContainer)
        let collisionID = uuid(605)
        collisionWriter.insert(result(id: collisionID))
        try collisionWriter.save()
        do {
            _ = try await SwiftDataBloodworkRepository(
                modelContext: ModelContext(collisionContainer),
                makeID: { collisionID }
            ).createResult(
                try input(date: date(50_000), marker: "Yeni", value: 1, unit: "birim")
            )
            XCTFail("A generated ID collision must not overwrite a row.")
        } catch {
            XCTAssertEqual(
                error as? BloodworkRepositoryIntegrityError,
                .resultIDCollision(id: collisionID)
            )
        }
    }

    func testUpdateAndDeleteRequireExistingIDAndExactTimestamp() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let resultID = uuid(606)
        let actualUpdatedAt = date(60_000)
        context.insert(result(id: resultID, updatedAt: actualUpdatedAt))
        try context.save()
        let repository = SwiftDataBloodworkRepository(modelContext: context)
        let changed = try input(
            date: date(61_000),
            marker: "Ferritin",
            value: 30,
            unit: "ng/mL"
        )

        do {
            _ = try await repository.updateResult(
                id: uuid(607),
                expectedUpdatedAt: actualUpdatedAt,
                input: changed
            )
            XCTFail("A missing update target must fail.")
        } catch {
            XCTAssertEqual(
                error as? BloodworkRepositoryMutationError,
                .resultNotFound(id: uuid(607))
            )
        }

        let stale = date(59_000)
        do {
            _ = try await repository.updateResult(
                id: resultID,
                expectedUpdatedAt: stale,
                input: changed
            )
            XCTFail("A stale update must fail.")
        } catch {
            XCTAssertEqual(
                error as? BloodworkRepositoryMutationError,
                .staleResult(
                    id: resultID,
                    expectedUpdatedAt: stale,
                    actualUpdatedAt: actualUpdatedAt
                )
            )
        }

        do {
            try await repository.deleteResult(
                id: resultID,
                expectedUpdatedAt: stale
            )
            XCTFail("A stale delete must fail.")
        } catch {
            XCTAssertEqual(
                error as? BloodworkRepositoryMutationError,
                .staleResult(
                    id: resultID,
                    expectedUpdatedAt: stale,
                    actualUpdatedAt: actualUpdatedAt
                )
            )
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BloodworkResult>()), 1)
    }

    func testCreateUpdateDeleteAndUndoFailuresRollback() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let existingID = uuid(608)
        let originalUpdatedAt = date(70_000)
        context.insert(
            result(
                id: existingID,
                updatedAt: originalUpdatedAt,
                marker: "Korunacak"
            )
        )
        try context.save()
        let repository = SwiftDataBloodworkRepository(
            modelContext: context,
            now: { self.date(71_000) },
            makeID: { self.uuid(609) },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.createResult(
                try input(date: date(72_000), marker: "Eklenmeyecek", value: 1, unit: "birim")
            )
            XCTFail("Create must roll back.")
        } catch {
            XCTAssertEqual(error as? BloodworkRepositoryOperationError, .saveFailed)
        }
        do {
            _ = try await repository.updateResult(
                id: existingID,
                expectedUpdatedAt: originalUpdatedAt,
                input: try input(
                    date: date(73_000),
                    marker: "Değişmeyecek",
                    value: 2,
                    unit: "birim"
                )
            )
            XCTFail("Update must roll back.")
        } catch {
            XCTAssertEqual(error as? BloodworkRepositoryOperationError, .saveFailed)
        }
        do {
            try await repository.deleteResult(
                id: existingID,
                expectedUpdatedAt: originalUpdatedAt
            )
            XCTFail("Delete must roll back.")
        } catch {
            XCTAssertEqual(error as? BloodworkRepositoryOperationError, .saveFailed)
        }
        do {
            try await repository.undoResultCreation(
                BloodworkCreationUndoToken(
                    id: existingID,
                    expectedUpdatedAt: originalUpdatedAt
                )
            )
            XCTFail("Undo must roll back.")
        } catch {
            XCTAssertEqual(error as? BloodworkRepositoryOperationError, .saveFailed)
        }

        let preserved = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<BloodworkResult>()).first
        )
        XCTAssertEqual(preserved.id, existingID)
        XCTAssertEqual(preserved.marker, "Korunacak")
        XCTAssertEqual(preserved.updatedAt, originalUpdatedAt)
        XCTAssertEqual(
            try ModelContext(container).fetchCount(FetchDescriptor<BloodworkResult>()),
            1
        )
    }

    func testUndoRequiresCreationTimestampAndIsIdempotentAfterSuccess() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let repository = SwiftDataBloodworkRepository(
            modelContext: context,
            now: { self.date(80_000) },
            makeID: { self.uuid(610) }
        )
        let mutation = try await repository.createResult(
            try input(date: date(79_000), marker: "Ferritin", value: 12, unit: "ng/mL")
        )

        do {
            try await repository.undoResultCreation(
                BloodworkCreationUndoToken(
                    id: mutation.snapshot.id,
                    expectedUpdatedAt: date(81_000)
                )
            )
            XCTFail("Undo must not delete a row changed after creation.")
        } catch {
            XCTAssertEqual(
                error as? BloodworkRepositoryMutationError,
                .staleResult(
                    id: mutation.snapshot.id,
                    expectedUpdatedAt: date(81_000),
                    actualUpdatedAt: mutation.snapshot.updatedAt
                )
            )
        }

        try await repository.undoResultCreation(mutation.undoToken)
        try await repository.undoResultCreation(mutation.undoToken)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BloodworkResult>()), 0)
    }

    private func input(
        date: Date,
        marker: String,
        value: Double,
        unit: String,
        note: String? = nil
    ) throws -> BloodworkResultInput {
        try BloodworkResultInput(
            date: date,
            marker: marker,
            value: value,
            unit: unit,
            note: note
        )
    }

    private func result(
        id: UUID,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 9_000),
        marker: String = "Ferritin",
        value: Double = 20,
        unit: String = "ng/mL"
    ) -> BloodworkResult {
        BloodworkResult(
            id: id,
            createdAt: date(8_000),
            updatedAt: updatedAt,
            date: date(8_500),
            marker: marker,
            value: value,
            unit: unit,
            note: nil
        )
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-4000-8000-%012d",
                suffix
            )
        )!
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: value)
    }
}
