import CoreModels
import Foundation
import MetricsKit
import SwiftData

@MainActor
public final class SwiftDataMetricsRepository: MetricsRepository {
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

    public func fetchBodyMetrics() async throws -> [BodyMetricSnapshot] {
        try validatedRows().map(\.snapshot)
            .sorted(by: BodyMetricOrdering.newestFirst)
    }

    public func createBodyMetrics(
        _ input: BodyMetricBatchInput
    ) async throws -> BodyMetricCreationMutation {
        let existing = try validatedRows()
        let existingIDs = Set(existing.map { $0.model.id })
        var generatedIDs: [UUID] = []
        generatedIDs.reserveCapacity(input.values.count)
        var generatedSet = Set<UUID>()

        for _ in input.values {
            let id = makeID()
            guard !existingIDs.contains(id), generatedSet.insert(id).inserted else {
                throw MetricsRepositoryIntegrityError.bodyMetricIDCollision(id: id)
            }
            generatedIDs.append(id)
        }

        let timestamp = now()
        let models = zip(generatedIDs, input.values).map { id, value in
            BodyMetric(
                id: id,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: input.date,
                type: value.type,
                customName: value.customName,
                value: value.value,
                unit: value.unit
            )
        }
        for model in models {
            modelContext.insert(model)
        }

        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw MetricsRepositoryOperationError.saveFailed
        }

        let snapshots = try models.map { model in
            try validatedSnapshot(from: model)
        }
            .sorted(by: BodyMetricOrdering.newestFirst)
        return BodyMetricCreationMutation(
            snapshots: snapshots,
            undoToken: BodyMetricCreationUndoToken(ids: generatedIDs)
        )
    }

    public func updateBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        date: Date,
        value: BodyMetricValueInput
    ) async throws -> BodyMetricSnapshot {
        let rows = try validatedRows()
        guard let row = rows.first(where: { $0.model.id == id }) else {
            throw MetricsRepositoryMutationError.bodyMetricNotFound(id: id)
        }
        guard row.model.updatedAt == expectedUpdatedAt else {
            throw MetricsRepositoryMutationError.staleBodyMetric(
                id: id,
                expectedUpdatedAt: expectedUpdatedAt,
                actualUpdatedAt: row.model.updatedAt
            )
        }

        row.model.date = date
        row.model.type = value.type
        row.model.customName = value.customName
        row.model.value = value.value
        row.model.unit = value.unit
        row.model.updatedAt = now()

        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw MetricsRepositoryOperationError.saveFailed
        }
        return try validatedSnapshot(from: row.model)
    }

    public func deleteBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws {
        let rows = try validatedRows()
        guard let row = rows.first(where: { $0.model.id == id }) else {
            throw MetricsRepositoryMutationError.bodyMetricNotFound(id: id)
        }
        guard row.model.updatedAt == expectedUpdatedAt else {
            throw MetricsRepositoryMutationError.staleBodyMetric(
                id: id,
                expectedUpdatedAt: expectedUpdatedAt,
                actualUpdatedAt: row.model.updatedAt
            )
        }

        modelContext.delete(row.model)
        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw MetricsRepositoryOperationError.saveFailed
        }
    }

    public func undoBodyMetricCreation(
        _ token: BodyMetricCreationUndoToken
    ) async throws {
        let rows = try validatedRows()
        let tokenIDs = Set(token.ids)
        let matches = rows.filter { tokenIDs.contains($0.model.id) }
        guard !matches.isEmpty else { return }
        matches.forEach { modelContext.delete($0.model) }
        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw MetricsRepositoryOperationError.saveFailed
        }
    }

    private struct ValidatedRow {
        let model: BodyMetric
        let snapshot: BodyMetricSnapshot
    }

    private func validatedRows() throws -> [ValidatedRow] {
        let models: [BodyMetric]
        do {
            models = try modelContext.fetch(FetchDescriptor<BodyMetric>())
        } catch {
            throw MetricsRepositoryOperationError.loadFailed
        }

        let grouped = Dictionary(grouping: models, by: \.id)
        if let duplicate = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key.uuidString < $1.key.uuidString })
            .first {
            throw MetricsRepositoryIntegrityError.duplicateBodyMetricIDs(
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

    private func validatedSnapshot(from model: BodyMetric) throws -> BodyMetricSnapshot {
        let input: BodyMetricValueInput
        do {
            input = try BodyMetricValueInput(
                type: model.type,
                customName: model.customName,
                value: model.value,
                unit: model.unit
            )
        } catch {
            throw MetricsRepositoryIntegrityError.invalidPersistedBodyMetric(id: model.id)
        }

        guard input.customName == model.customName,
              input.unit == model.unit else {
            throw MetricsRepositoryIntegrityError.invalidPersistedBodyMetric(id: model.id)
        }

        return BodyMetricSnapshot(
            id: model.id,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            date: model.date,
            type: input.type,
            customName: input.customName,
            value: input.value,
            unit: input.unit
        )
    }
}
