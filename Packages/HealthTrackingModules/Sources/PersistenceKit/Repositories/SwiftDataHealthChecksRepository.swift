import CoreModels
import Foundation
import HealthChecksKit
import SwiftData

@MainActor
public final class SwiftDataHealthChecksRepository: HealthChecksRepository {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let now: @MainActor () -> Date
    private let makeID: @MainActor () -> UUID
    private let saveOperation: @MainActor () throws -> Void
    private let rollbackOperation: @MainActor () -> Void

    public init(
        modelContext: ModelContext,
        calendar: Calendar = .current,
        now: @escaping @MainActor () -> Date = { .now },
        makeID: @escaping @MainActor () -> UUID = { UUID() },
        save: (@MainActor () throws -> Void)? = nil,
        rollback: (@MainActor () -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
        saveOperation = save ?? { try modelContext.save() }
        rollbackOperation = rollback ?? { modelContext.rollback() }
    }

    public func fetchReminders() async throws -> [HealthCheckReminderSnapshot] {
        try validatedRows().map(\.snapshot)
            .sorted(by: HealthCheckReminderOrdering.dueFirst)
    }

    public func createReminder(
        _ input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        let rows = try validatedRows()
        let id = makeID()
        guard !rows.contains(where: { $0.model.id == id }) else {
            throw HealthChecksRepositoryIntegrityError.reminderIDCollision(id: id)
        }
        let timestamp = now()
        let model = HealthCheckReminder(
            id: id,
            createdAt: timestamp,
            updatedAt: timestamp,
            name: input.name,
            dueDate: input.dueDate,
            recurrence: input.recurrence,
            status: .pending
        )
        modelContext.insert(model)
        try saveOrRollback()
        return try validatedSnapshot(from: model)
    }

    public func updateReminder(
        id: UUID,
        expectedUpdatedAt: Date,
        input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        let row = try requiredRow(id: id, in: validatedRows())
        try requireCurrent(row.model, expectedUpdatedAt: expectedUpdatedAt)
        row.model.name = input.name
        row.model.dueDate = input.dueDate
        row.model.recurrence = input.recurrence
        row.model.updatedAt = now()
        try saveOrRollback()
        return try validatedSnapshot(from: row.model)
    }

    public func deleteReminder(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws {
        let row = try requiredRow(id: id, in: validatedRows())
        try requireCurrent(row.model, expectedUpdatedAt: expectedUpdatedAt)
        let links = try successorLinks(for: id)
        guard links.count <= 1 else {
            throw HealthChecksRepositoryIntegrityError.duplicateSuccessorLinks(
                predecessorID: id,
                count: links.count
            )
        }
        links.forEach(modelContext.delete)
        modelContext.delete(row.model)
        try saveOrRollback()
    }

    public func completeReminder(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws -> HealthCheckCompletionMutation {
        let rows = try validatedRows()
        if let resolved = try resolveExistingCompletion(predecessorID: id, rows: rows) {
            return resolved
        }

        let row = try requiredRow(id: id, in: rows)
        try requireCurrent(row.model, expectedUpdatedAt: expectedUpdatedAt)
        let nextDueDate = try HealthCheckRecurrenceEngine.nextDueDate(
            after: row.model.dueDate,
            recurrence: row.model.recurrence,
            calendar: calendar
        )
        let timestamp = now()
        row.model.status = .done
        row.model.updatedAt = timestamp

        var successorModel: HealthCheckReminder?
        if let nextDueDate {
            let successorID = makeID()
            guard !rows.contains(where: { $0.model.id == successorID }) else {
                rollbackOperation()
                throw HealthChecksRepositoryIntegrityError.reminderIDCollision(
                    id: successorID
                )
            }
            let successor = HealthCheckReminder(
                id: successorID,
                createdAt: timestamp,
                updatedAt: timestamp,
                name: row.model.name,
                dueDate: nextDueDate,
                recurrence: row.model.recurrence,
                status: .pending
            )
            successorModel = successor
            modelContext.insert(successor)
            modelContext.insert(
                AppSetting(
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    key: Self.successorLinkKey(predecessorID: id),
                    value: successorID.uuidString.lowercased()
                )
            )
        }

        try saveOrRollback()
        return HealthCheckCompletionMutation(
            completed: try validatedSnapshot(from: row.model),
            successor: try successorModel.map { model in
                try validatedSnapshot(from: model)
            }
        )
    }

    private func validatedRows() throws -> [ValidatedRow] {
        let models = try modelContext.fetch(FetchDescriptor<HealthCheckReminder>())
        let grouped = Dictionary(grouping: models, by: \.id)
        if let duplicate = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key.uuidString < $1.key.uuidString })
            .first {
            throw HealthChecksRepositoryIntegrityError.duplicateReminderIDs(
                id: duplicate.key,
                count: duplicate.value.count
            )
        }
        return try models.map { model in
            ValidatedRow(model: model, snapshot: try validatedSnapshot(from: model))
        }
    }

    private func validatedSnapshot(
        from model: HealthCheckReminder
    ) throws -> HealthCheckReminderSnapshot {
        let trimmedName = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw HealthChecksRepositoryIntegrityError.invalidPersistedReminder(
                id: model.id
            )
        }
        return HealthCheckReminderSnapshot(
            id: model.id,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            name: trimmedName,
            dueDate: model.dueDate,
            recurrence: model.recurrence,
            status: model.status
        )
    }

    private func requiredRow(
        id: UUID,
        in rows: [ValidatedRow]
    ) throws -> ValidatedRow {
        guard let row = rows.first(where: { $0.model.id == id }) else {
            throw HealthChecksRepositoryMutationError.reminderNotFound(id: id)
        }
        return row
    }

    private func requireCurrent(
        _ model: HealthCheckReminder,
        expectedUpdatedAt: Date
    ) throws {
        guard model.updatedAt == expectedUpdatedAt else {
            throw HealthChecksRepositoryMutationError.staleReminder(
                id: model.id,
                expectedUpdatedAt: expectedUpdatedAt,
                actualUpdatedAt: model.updatedAt
            )
        }
    }

    private func resolveExistingCompletion(
        predecessorID: UUID,
        rows: [ValidatedRow]
    ) throws -> HealthCheckCompletionMutation? {
        let links = try successorLinks(for: predecessorID)
        guard links.count <= 1 else {
            throw HealthChecksRepositoryIntegrityError.duplicateSuccessorLinks(
                predecessorID: predecessorID,
                count: links.count
            )
        }
        guard let link = links.first,
              let successorID = UUID(uuidString: link.value),
              let completed = rows.first(where: { $0.model.id == predecessorID }),
              completed.snapshot.status == .done,
              let successor = rows.first(where: { $0.model.id == successorID }) else {
            if links.isEmpty { return nil }
            throw HealthChecksRepositoryIntegrityError.invalidSuccessorLink(
                predecessorID: predecessorID
            )
        }
        return HealthCheckCompletionMutation(
            completed: completed.snapshot,
            successor: successor.snapshot
        )
    }

    private func successorLinks(for predecessorID: UUID) throws -> [AppSetting] {
        let key = Self.successorLinkKey(predecessorID: predecessorID)
        return try modelContext.fetch(FetchDescriptor<AppSetting>())
            .filter { $0.key == key }
    }

    private static func successorLinkKey(predecessorID: UUID) -> String {
        "health-check.successor.v1.\(predecessorID.uuidString.lowercased())"
    }

    private func saveOrRollback() throws {
        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw HealthChecksRepositoryOperationError.saveFailed
        }
    }

    private struct ValidatedRow {
        let model: HealthCheckReminder
        let snapshot: HealthCheckReminderSnapshot
    }
}
