import CoreModels
import Foundation
@testable import MetricsKit
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class BodyMetricRepositoryTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testBatchCreatePersistsEveryValueAtomicallyAndReturnsUndoToken() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        var identifiers = [
            uuid("00000000-0000-4000-8000-000000000311"),
            uuid("00000000-0000-4000-8000-000000000312"),
            uuid("00000000-0000-4000-8000-000000000313"),
        ]
        let timestamp = Date(timeIntervalSinceReferenceDate: 2_000)
        let repository = SwiftDataMetricsRepository(
            modelContext: context,
            now: { timestamp },
            makeID: { identifiers.removeFirst() }
        )
        let date = Date(timeIntervalSinceReferenceDate: 1_500)
        let input = try BodyMetricBatchInput(
            date: date,
            weightKilograms: 82,
            waistCentimeters: 91,
            customMetrics: [
                try BodyMetricValueInput.custom(name: "Boyun", value: 39, unit: "cm")
            ]
        )

        let mutation = try await repository.createBodyMetrics(input)
        let fetched = try await repository.fetchBodyMetrics()

        XCTAssertEqual(mutation.snapshots.count, 3)
        XCTAssertEqual(Set(mutation.undoToken.ids), Set(mutation.snapshots.map(\.id)))
        XCTAssertEqual(fetched.map(\.id), mutation.snapshots.map(\.id))
        XCTAssertEqual(
            fetched.map(\.type.rawValue).sorted(),
            BodyMetricType.allCases.map(\.rawValue).sorted()
        )
        XCTAssertTrue(fetched.allSatisfy { $0.createdAt == timestamp })
        XCTAssertTrue(fetched.allSatisfy { $0.updatedAt == timestamp })
        XCTAssertTrue(fetched.allSatisfy { $0.date == date })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetric>()), 3)
        assertEquatableSendable(mutation.snapshots[0])
    }

    func testFetchUsesNewestCreatedUUIDOrderingAndRejectsInvalidRows() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let firstID = uuid("00000000-0000-4000-8000-000000000320")
        let secondID = uuid("00000000-0000-4000-8000-000000000321")
        let olderID = uuid("00000000-0000-4000-8000-000000000322")
        writer.insert(metric(id: secondID, date: date(200), createdAt: date(500)))
        writer.insert(metric(id: olderID, date: date(100), createdAt: date(600)))
        writer.insert(metric(id: firstID, date: date(200), createdAt: date(500)))
        try writer.save()
        let repository = SwiftDataMetricsRepository(modelContext: ModelContext(container))

        let orderedIDs = try await repository.fetchBodyMetrics().map(\.id)
        XCTAssertEqual(orderedIDs, [firstID, secondID, olderID])

        let invalidID = uuid("00000000-0000-4000-8000-000000000323")
        writer.insert(metric(id: invalidID, value: 0))
        try writer.save()

        do {
            _ = try await repository.fetchBodyMetrics()
            XCTFail("Expected invalid persisted metrics to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryIntegrityError,
                .invalidPersistedBodyMetric(id: invalidID)
            )
        }
    }

    func testDuplicateIDsAndGeneratedCollisionsFailWithoutMutation() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let duplicateID = uuid("00000000-0000-4000-8000-000000000331")
        let collisionID = uuid("00000000-0000-4000-8000-000000000332")
        writer.insert(metric(id: duplicateID, value: 80))
        writer.insert(metric(id: duplicateID, value: 81))
        writer.insert(metric(id: collisionID, value: 82))
        try writer.save()
        let repository = SwiftDataMetricsRepository(
            modelContext: ModelContext(container),
            makeID: { collisionID }
        )

        do {
            _ = try await repository.fetchBodyMetrics()
            XCTFail("Expected duplicate IDs to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryIntegrityError,
                .duplicateBodyMetricIDs(id: duplicateID, count: 2)
            )
        }

        let cleanContainer = try ModelContainerFactory.make(for: .inMemory)
        let cleanWriter = ModelContext(cleanContainer)
        cleanWriter.insert(metric(id: collisionID, value: 82))
        try cleanWriter.save()
        var generatedIDs = [
            uuid("00000000-0000-4000-8000-000000000333"),
            collisionID,
        ]
        let collisionRepository = SwiftDataMetricsRepository(
            modelContext: ModelContext(cleanContainer),
            makeID: { generatedIDs.removeFirst() }
        )
        do {
            _ = try await collisionRepository.createBodyMetrics(
                try BodyMetricBatchInput(
                    date: date(1_000),
                    weightKilograms: 83,
                    waistCentimeters: 90,
                    customMetrics: []
                )
            )
            XCTFail("Expected a generated ID collision.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryIntegrityError,
                .bodyMetricIDCollision(id: collisionID)
            )
        }
        XCTAssertEqual(try cleanWriter.fetchCount(FetchDescriptor<BodyMetric>()), 1)
    }

    func testUpdateAndDeleteMissingExactIDFailWithoutCrossRecordMutation() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let existingID = uuid("00000000-0000-4000-8000-000000000334")
        let missingID = uuid("00000000-0000-4000-8000-000000000335")
        let updatedAt = date(2_000)
        writer.insert(metric(id: existingID, updatedAt: updatedAt, value: 80))
        try writer.save()
        let repository = SwiftDataMetricsRepository(modelContext: ModelContext(container))

        do {
            _ = try await repository.updateBodyMetric(
                id: missingID,
                expectedUpdatedAt: updatedAt,
                date: date(2_500),
                value: try .weight(kilograms: 81)
            )
            XCTFail("Expected exact-ID update lookup to fail.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryMutationError,
                .bodyMetricNotFound(id: missingID)
            )
        }

        do {
            try await repository.deleteBodyMetric(
                id: missingID,
                expectedUpdatedAt: updatedAt
            )
            XCTFail("Expected exact-ID delete lookup to fail.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryMutationError,
                .bodyMetricNotFound(id: missingID)
            )
        }

        let preserved = try await repository.fetchBodyMetrics()
        XCTAssertEqual(preserved.map(\.id), [existingID])
        XCTAssertEqual(preserved.first?.value, 80)
    }

    func testUpdateAndDeleteRequireCurrentUpdatedAtAndPreserveOtherRows() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let metricID = uuid("00000000-0000-4000-8000-000000000341")
        let untouchedID = uuid("00000000-0000-4000-8000-000000000342")
        let originalUpdatedAt = date(2_000)
        writer.insert(metric(id: metricID, updatedAt: originalUpdatedAt, value: 80))
        writer.insert(metric(id: untouchedID, updatedAt: originalUpdatedAt, value: 70))
        try writer.save()
        let updatedAt = date(3_000)
        let repository = SwiftDataMetricsRepository(
            modelContext: ModelContext(container),
            now: { updatedAt }
        )

        do {
            _ = try await repository.updateBodyMetric(
                id: metricID,
                expectedUpdatedAt: date(1_999),
                date: date(2_500),
                value: try .weight(kilograms: 81)
            )
            XCTFail("Expected a stale update failure.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryMutationError,
                .staleBodyMetric(
                    id: metricID,
                    expectedUpdatedAt: date(1_999),
                    actualUpdatedAt: originalUpdatedAt
                )
            )
        }

        let updated = try await repository.updateBodyMetric(
            id: metricID,
            expectedUpdatedAt: originalUpdatedAt,
            date: date(2_500),
            value: try .weight(kilograms: 81)
        )
        XCTAssertEqual(updated.value, 81)
        XCTAssertEqual(updated.updatedAt, updatedAt)

        do {
            try await repository.deleteBodyMetric(
                id: metricID,
                expectedUpdatedAt: originalUpdatedAt
            )
            XCTFail("Expected stale delete to fail.")
        } catch {
            XCTAssertEqual(
                error as? MetricsRepositoryMutationError,
                .staleBodyMetric(
                    id: metricID,
                    expectedUpdatedAt: originalUpdatedAt,
                    actualUpdatedAt: updatedAt
                )
            )
        }

        try await repository.deleteBodyMetric(
            id: metricID,
            expectedUpdatedAt: updatedAt
        )
        let remainingIDs = try await repository.fetchBodyMetrics().map(\.id)
        XCTAssertEqual(remainingIDs, [untouchedID])
    }

    func testCreateUpdateAndDeleteFailuresRollbackExactly() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let existingID = uuid("00000000-0000-4000-8000-000000000351")
        let createdID = uuid("00000000-0000-4000-8000-000000000352")
        let originalUpdatedAt = date(2_000)
        let writer = ModelContext(container)
        writer.insert(metric(id: existingID, updatedAt: originalUpdatedAt, value: 80))
        try writer.save()
        let context = ModelContext(container)
        let repository = SwiftDataMetricsRepository(
            modelContext: context,
            now: { self.date(3_000) },
            makeID: { createdID },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.createBodyMetrics(
                try BodyMetricBatchInput(
                    date: date(2_500),
                    weightKilograms: 81,
                    waistCentimeters: nil,
                    customMetrics: []
                )
            )
            XCTFail("Expected create rollback.")
        } catch {
            XCTAssertEqual(error as? MetricsRepositoryOperationError, .saveFailed)
        }
        XCTAssertEqual(try writer.fetchCount(FetchDescriptor<BodyMetric>()), 1)

        do {
            _ = try await repository.updateBodyMetric(
                id: existingID,
                expectedUpdatedAt: originalUpdatedAt,
                date: date(2_500),
                value: try .weight(kilograms: 81)
            )
            XCTFail("Expected update rollback.")
        } catch {
            XCTAssertEqual(error as? MetricsRepositoryOperationError, .saveFailed)
        }

        do {
            try await repository.deleteBodyMetric(
                id: existingID,
                expectedUpdatedAt: originalUpdatedAt
            )
            XCTFail("Expected delete rollback.")
        } catch {
            XCTAssertEqual(error as? MetricsRepositoryOperationError, .saveFailed)
        }

        let preserved = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<BodyMetric>()).first
        )
        XCTAssertEqual(preserved.id, existingID)
        XCTAssertEqual(preserved.value, 80)
        XCTAssertEqual(preserved.updatedAt, originalUpdatedAt)
    }

    func testUndoCreationDeletesExactlyTokenIDsAndIsIdempotent() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let untouchedID = uuid("00000000-0000-4000-8000-000000000361")
        let writer = ModelContext(container)
        writer.insert(metric(id: untouchedID, value: 70))
        try writer.save()
        var identifiers = [
            uuid("00000000-0000-4000-8000-000000000362"),
            uuid("00000000-0000-4000-8000-000000000363"),
        ]
        let repository = SwiftDataMetricsRepository(
            modelContext: ModelContext(container),
            makeID: { identifiers.removeFirst() }
        )
        let mutation = try await repository.createBodyMetrics(
            try BodyMetricBatchInput(
                date: date(2_500),
                weightKilograms: 81,
                waistCentimeters: 90,
                customMetrics: []
            )
        )

        try await repository.undoBodyMetricCreation(mutation.undoToken)
        try await repository.undoBodyMetricCreation(mutation.undoToken)

        let remainingIDs = try await repository.fetchBodyMetrics().map(\.id)
        XCTAssertEqual(remainingIDs, [untouchedID])
    }

    private func metric(
        id: UUID,
        date: Date = Date(timeIntervalSinceReferenceDate: 1_000),
        createdAt: Date = Date(timeIntervalSinceReferenceDate: 1_000),
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 1_000),
        value: Double = 80
    ) -> BodyMetric {
        BodyMetric(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            date: date,
            type: .weight,
            customName: nil,
            value: value,
            unit: "kg"
        )
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: value)
    }

    private func uuid(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID: \(value)")
        }
        return id
    }

    private func assertEquatableSendable<T: Equatable & Sendable>(_ value: T) {
        XCTAssertEqual(value, value)
    }
}
