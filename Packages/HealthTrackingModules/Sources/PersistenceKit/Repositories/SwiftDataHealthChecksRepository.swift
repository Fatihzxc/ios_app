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
        calendar: Calendar,
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
        if let resolved = try resolveExistingCompletion(
            predecessorID: id,
            expectedUpdatedAt: expectedUpdatedAt,
            rows: rows
        ) {
            return resolved
        }

        let row = try requiredRow(id: id, in: rows)
        try requireCurrent(row.model, expectedUpdatedAt: expectedUpdatedAt)
        guard row.model.status == .pending else {
            throw HealthChecksRepositoryMutationError.completionRequiresPending(
                id: id,
                actualStatus: row.model.status
            )
        }
        let original = row.snapshot
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
        let completed = try validatedSnapshot(from: row.model)
        let successor = try successorModel.map { model in
            try validatedSnapshot(from: model)
        }
        return HealthCheckCompletionMutation(
            completed: completed,
            successor: successor,
            undoToken: HealthCheckCompletionUndoToken(
                original: original,
                completedUpdatedAt: completed.updatedAt,
                successorID: successor?.id,
                successorUpdatedAt: successor?.updatedAt
            )
        )
    }

    public func undoCompletion(
        _ token: HealthCheckCompletionUndoToken
    ) async throws -> HealthCheckReminderSnapshot {
        let rows = try validatedRows()
        let original = token.original
        guard original.status == .pending,
              original.name == original.name.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !original.name.isEmpty,
              (token.successorID == nil) == (token.successorUpdatedAt == nil) else {
            throw HealthChecksRepositoryIntegrityError.invalidSuccessorLink(
                predecessorID: original.id
            )
        }

        let predecessor = try requiredRow(id: original.id, in: rows)
        try requireCurrent(
            predecessor.model,
            expectedUpdatedAt: token.completedUpdatedAt
        )
        guard predecessor.model.status == .done,
              predecessor.model.createdAt == original.createdAt,
              predecessor.model.name == original.name,
              predecessor.model.dueDate == original.dueDate,
              predecessor.model.recurrence == original.recurrence else {
            throw HealthChecksRepositoryIntegrityError.invalidSuccessorLink(
                predecessorID: original.id
            )
        }

        let links = try successorLinks(for: original.id)
        guard links.count <= 1 else {
            throw HealthChecksRepositoryIntegrityError.duplicateSuccessorLinks(
                predecessorID: original.id,
                count: links.count
            )
        }

        if let successorID = token.successorID,
           let successorUpdatedAt = token.successorUpdatedAt {
            guard let link = links.first,
                  UUID(uuidString: link.value) == successorID,
                  let successor = rows.first(where: { $0.model.id == successorID }),
                  successor.model.status == .pending else {
                throw HealthChecksRepositoryIntegrityError.invalidSuccessorLink(
                    predecessorID: original.id
                )
            }
            try requireCurrent(
                successor.model,
                expectedUpdatedAt: successorUpdatedAt
            )
            modelContext.delete(successor.model)
            modelContext.delete(link)
        } else if !links.isEmpty {
            throw HealthChecksRepositoryIntegrityError.invalidSuccessorLink(
                predecessorID: original.id
            )
        }

        predecessor.model.name = original.name
        predecessor.model.dueDate = original.dueDate
        predecessor.model.recurrence = original.recurrence
        predecessor.model.status = .pending
        predecessor.model.updatedAt = now()
        try saveOrRollback()
        return try validatedSnapshot(from: predecessor.model)
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
        guard !trimmedName.isEmpty, trimmedName == model.name else {
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
        expectedUpdatedAt: Date,
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
              let successor = rows.first(where: { $0.model.id == successorID }),
              successor.snapshot.status == .pending,
              successor.snapshot.updatedAt == completed.snapshot.updatedAt else {
            if links.isEmpty { return nil }
            throw HealthChecksRepositoryIntegrityError.invalidSuccessorLink(
                predecessorID: predecessorID
            )
        }
        return HealthCheckCompletionMutation(
            completed: completed.snapshot,
            successor: successor.snapshot,
            undoToken: HealthCheckCompletionUndoToken(
                original: HealthCheckReminderSnapshot(
                    id: completed.snapshot.id,
                    createdAt: completed.snapshot.createdAt,
                    updatedAt: expectedUpdatedAt,
                    name: completed.snapshot.name,
                    dueDate: completed.snapshot.dueDate,
                    recurrence: completed.snapshot.recurrence,
                    status: .pending
                ),
                completedUpdatedAt: completed.snapshot.updatedAt,
                successorID: successor.snapshot.id,
                successorUpdatedAt: successor.snapshot.updatedAt
            )
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
