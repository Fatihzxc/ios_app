import CoreModels
import Foundation
import HealthChecksKit
import SwiftData

@MainActor
public final class SwiftDataBloodworkRepository: BloodworkRepository {
    private let modelContext: ModelContext
    private let now: @MainActor () -> Date
    private let makeID: @MainActor () -> UUID
    private let saveOperation: @MainActor () throws -> Void
    private let rollbackOperation: @MainActor () -> Void

    public init(
        modelContext: ModelContext,
        now: @escaping @MainActor () -> Date = { .now },
        makeID: @escaping @MainActor () -> UUID = { UUID() },
        save: (@MainActor () throws -> Void)? = nil,
        rollback: (@MainActor () -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.now = now
        self.makeID = makeID
        saveOperation = save ?? { try modelContext.save() }
        rollbackOperation = rollback ?? { modelContext.rollback() }
    }

    public func fetchResults() async throws -> [BloodworkResultSnapshot] {
        try validatedRows().map(\.snapshot)
            .sorted(by: BloodworkResultOrdering.newestFirst)
    }

    public func createResult(
        _ input: BloodworkResultInput
    ) async throws -> BloodworkCreationMutation {
        let existing = try validatedRows()
        let id = makeID()
        guard !existing.contains(where: { $0.model.id == id }) else {
            throw BloodworkRepositoryIntegrityError.resultIDCollision(id: id)
        }

        let timestamp = now()
        let model = BloodworkResult(
            id: id,
            createdAt: timestamp,
            updatedAt: timestamp,
            date: input.date,
            marker: input.marker,
            value: input.value,
            unit: input.unit,
            note: input.note
        )
        modelContext.insert(model)
        try saveOrRollback()
        let snapshot = try validatedSnapshot(from: model)
        return BloodworkCreationMutation(
            snapshot: snapshot,
            undoToken: BloodworkCreationUndoToken(
                id: id,
                expectedUpdatedAt: timestamp
            )
        )
    }

    public func updateResult(
        id: UUID,
        expectedUpdatedAt: Date,
        input: BloodworkResultInput
    ) async throws -> BloodworkResultSnapshot {
        let rows = try validatedRows()
        guard let row = rows.first(where: { $0.model.id == id }) else {
            throw BloodworkRepositoryMutationError.resultNotFound(id: id)
        }
        try requireCurrent(row.model, expectedUpdatedAt: expectedUpdatedAt)

        row.model.date = input.date
        row.model.marker = input.marker
        row.model.value = input.value
        row.model.unit = input.unit
        row.model.note = input.note
        row.model.updatedAt = now()
        try saveOrRollback()
        return try validatedSnapshot(from: row.model)
    }

    public func deleteResult(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws {
        let rows = try validatedRows()
        guard let row = rows.first(where: { $0.model.id == id }) else {
            throw BloodworkRepositoryMutationError.resultNotFound(id: id)
        }
        try requireCurrent(row.model, expectedUpdatedAt: expectedUpdatedAt)

        modelContext.delete(row.model)
        try saveOrRollback()
    }

    public func undoResultCreation(
        _ token: BloodworkCreationUndoToken
    ) async throws {
        let rows = try validatedRows()
        guard let row = rows.first(where: { $0.model.id == token.id }) else {
            return
        }
        try requireCurrent(
            row.model,
            expectedUpdatedAt: token.expectedUpdatedAt
        )

        modelContext.delete(row.model)
        try saveOrRollback()
    }

    private struct ValidatedRow {
        let model: BloodworkResult
        let snapshot: BloodworkResultSnapshot
    }

    private func validatedRows() throws -> [ValidatedRow] {
        let models: [BloodworkResult]
        do {
            models = try modelContext.fetch(FetchDescriptor<BloodworkResult>())
        } catch {
            throw BloodworkRepositoryOperationError.loadFailed
        }

        let grouped = Dictionary(grouping: models, by: \.id)
        if let duplicate = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key.uuidString < $1.key.uuidString })
            .first {
            throw BloodworkRepositoryIntegrityError.duplicateResultIDs(
                id: duplicate.key,
                count: duplicate.value.count
            )
        }

        return try models.map { model in
            ValidatedRow(
                model: model,
                snapshot: try validatedSnapshot(from: model)
            )
        }
    }

    private func validatedSnapshot(
        from model: BloodworkResult
    ) throws -> BloodworkResultSnapshot {
        let input: BloodworkResultInput
        do {
            input = try BloodworkResultInput(
                date: model.date,
                marker: model.marker,
                value: model.value,
                unit: model.unit,
                note: model.note
            )
        } catch {
            throw BloodworkRepositoryIntegrityError.invalidPersistedResult(id: model.id)
        }
        guard input.marker == model.marker,
              input.unit == model.unit,
              input.note == model.note else {
            throw BloodworkRepositoryIntegrityError.invalidPersistedResult(id: model.id)
        }

        return BloodworkResultSnapshot(
            id: model.id,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            date: input.date,
            marker: input.marker,
            value: input.value,
            unit: input.unit,
            note: input.note
        )
    }

    private func requireCurrent(
        _ model: BloodworkResult,
        expectedUpdatedAt: Date
    ) throws {
        guard model.updatedAt == expectedUpdatedAt else {
            throw BloodworkRepositoryMutationError.staleResult(
                id: model.id,
                expectedUpdatedAt: expectedUpdatedAt,
                actualUpdatedAt: model.updatedAt
            )
        }
    }

    private func saveOrRollback() throws {
        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw BloodworkRepositoryOperationError.saveFailed
        }
    }
}
