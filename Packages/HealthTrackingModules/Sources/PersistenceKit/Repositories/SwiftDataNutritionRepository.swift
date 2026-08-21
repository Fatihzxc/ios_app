import CoreModels
import Foundation
import NutritionKit
import SwiftData

@MainActor
public final class SwiftDataNutritionRepository: NutritionDayRepository {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let now: @MainActor () -> Date
    private let makeID: @MainActor () -> UUID
    private let fetchDaysOperation: @MainActor (
        FetchDescriptor<DailyNutritionLog>
    ) throws -> [DailyNutritionLog]
    private let fetchEntriesOperation: @MainActor (
        FetchDescriptor<MealEntry>
    ) throws -> [MealEntry]
    private let saveOperation: @MainActor () throws -> Void
    private let rollbackOperation: @MainActor () -> Void

    public init(
        modelContext: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @MainActor () -> Date = { .now },
        makeID: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
        fetchDaysOperation = { try modelContext.fetch($0) }
        fetchEntriesOperation = { try modelContext.fetch($0) }
        saveOperation = { try modelContext.save() }
        rollbackOperation = { modelContext.rollback() }
    }

    init(
        modelContext: ModelContext,
        calendar: Calendar,
        now: @escaping @MainActor () -> Date,
        makeID: @escaping @MainActor () -> UUID,
        save: @escaping @MainActor () throws -> Void,
        rollback: @escaping @MainActor () -> Void
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
        fetchDaysOperation = { try modelContext.fetch($0) }
        fetchEntriesOperation = { try modelContext.fetch($0) }
        saveOperation = save
        rollbackOperation = rollback
    }

    init(
        modelContext: ModelContext,
        calendar: Calendar,
        now: @escaping @MainActor () -> Date,
        makeID: @escaping @MainActor () -> UUID,
        fetchDays: @escaping @MainActor (
            FetchDescriptor<DailyNutritionLog>
        ) throws -> [DailyNutritionLog],
        fetchEntries: @escaping @MainActor (
            FetchDescriptor<MealEntry>
        ) throws -> [MealEntry],
        save: @escaping @MainActor () throws -> Void,
        rollback: @escaping @MainActor () -> Void
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
        fetchDaysOperation = fetchDays
        fetchEntriesOperation = fetchEntries
        saveOperation = save
        rollbackOperation = rollback
    }

    public func fetchNutritionDay(
        containing date: Date
    ) async throws -> NutritionDaySnapshot? {
        let day = try NutritionDayKey(containing: date, calendar: calendar)
        let matches = try matchingDays(for: day)
        guard matches.count <= 1 else {
            throw duplicateDayError(day: day, matches: matches)
        }
        guard let existing = matches.first else { return nil }
        try validateUniqueDayID(existing)
        return snapshot(existing, day: day)
    }

    public func fetchOrCreateNutritionDay(
        containing date: Date
    ) async throws -> NutritionDaySnapshot {
        let day = try NutritionDayKey(containing: date, calendar: calendar)
        let matches = try matchingDays(for: day)
        guard matches.count <= 1 else {
            throw duplicateDayError(day: day, matches: matches)
        }

        if let existing = matches.first {
            try validateUniqueDayID(existing)
            guard existing.date != day.start else {
                return snapshot(existing, day: day)
            }
            existing.date = day.start
            existing.updatedAt = now()
            try saveMutation(or: .saveFailed)
            return snapshot(existing, day: day)
        }

        let id = makeID()
        guard try matchingDays(id: id).isEmpty else {
            throw NutritionRepositoryIntegrityError.nutritionDayIDCollision(id: id)
        }
        let timestamp = now()
        let created = DailyNutritionLog(
            id: id,
            createdAt: timestamp,
            updatedAt: timestamp,
            date: day.start
        )
        modelContext.insert(created)
        try saveMutation(or: .saveFailed)
        return snapshot(created, day: day)
    }

    public func fetchNutritionDays() async throws -> [NutritionDaySnapshot] {
        let logs = try fetchDays(FetchDescriptor<DailyNutritionLog>())
        try validateUniqueDayIDs(logs)
        var grouped: [NutritionDayKey: [DailyNutritionLog]] = [:]
        for log in logs {
            let day = try NutritionDayKey(containing: log.date, calendar: calendar)
            grouped[day, default: []].append(log)
        }
        if let (day, matches) = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { lhs, rhs in
                if lhs.key.start != rhs.key.start {
                    return lhs.key.start < rhs.key.start
                }
                return lhs.key.end < rhs.key.end
            })
            .first {
            throw duplicateDayError(day: day, matches: matches)
        }
        return grouped
            .compactMap { day, matches in
                matches.first.map { snapshot($0, day: day) }
            }
            .sorted { lhs, rhs in
                if lhs.day.start != rhs.day.start {
                    return lhs.day.start < rhs.day.start
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func deleteNutritionDay(id: UUID) async throws {
        let matches = try matchingDays(id: id)
        guard !matches.isEmpty else {
            throw NutritionRepositoryMutationError.nutritionDayNotFound(id: id)
        }
        guard matches.count == 1, let day = matches.first else {
            throw NutritionRepositoryIntegrityError.duplicateNutritionDayIDs(
                id: id,
                count: matches.count
            )
        }

        let entries = try fetchEntries(FetchDescriptor<MealEntry>())
            .filter { $0.dailyNutritionLog?.id == id }
        entries.forEach { modelContext.delete($0) }
        modelContext.delete(day)
        try saveMutation(or: .deleteFailed)
    }

    private func matchingDays(for day: NutritionDayKey) throws -> [DailyNutritionLog] {
        let start = day.start
        let end = day.end
        return try fetchDays(
            FetchDescriptor<DailyNutritionLog>(
                predicate: #Predicate { log in
                    log.date >= start && log.date < end
                }
            )
        )
    }

    private func matchingDays(id: UUID) throws -> [DailyNutritionLog] {
        let requestedID = id
        return try fetchDays(
            FetchDescriptor<DailyNutritionLog>(
                predicate: #Predicate { $0.id == requestedID }
            )
        )
    }

    private func fetchDays(
        _ descriptor: FetchDescriptor<DailyNutritionLog>
    ) throws -> [DailyNutritionLog] {
        do {
            return try fetchDaysOperation(descriptor)
        } catch {
            throw NutritionRepositoryOperationError.loadFailed
        }
    }

    private func fetchEntries(
        _ descriptor: FetchDescriptor<MealEntry>
    ) throws -> [MealEntry] {
        do {
            return try fetchEntriesOperation(descriptor)
        } catch {
            throw NutritionRepositoryOperationError.loadFailed
        }
    }

    private func validateUniqueDayIDs(_ logs: [DailyNutritionLog]) throws {
        let duplicate = Dictionary(grouping: logs, by: \.id)
            .filter { $0.value.count > 1 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .first
        if let (id, matches) = duplicate {
            throw NutritionRepositoryIntegrityError.duplicateNutritionDayIDs(
                id: id,
                count: matches.count
            )
        }
    }

    private func validateUniqueDayID(_ log: DailyNutritionLog) throws {
        let matches = try matchingDays(id: log.id)
        guard matches.count == 1 else {
            throw NutritionRepositoryIntegrityError.duplicateNutritionDayIDs(
                id: log.id,
                count: matches.count
            )
        }
    }

    private func duplicateDayError(
        day: NutritionDayKey,
        matches: [DailyNutritionLog]
    ) -> NutritionRepositoryIntegrityError {
        .duplicateNutritionDays(
            dayStart: day.start,
            ids: matches.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func snapshot(
        _ log: DailyNutritionLog,
        day: NutritionDayKey
    ) -> NutritionDaySnapshot {
        NutritionDaySnapshot(
            id: log.id,
            createdAt: log.createdAt,
            updatedAt: log.updatedAt,
            day: day,
            mealEntryIDs: (log.mealEntries ?? [])
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func saveMutation(
        or operationError: NutritionRepositoryOperationError
    ) throws {
        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw operationError
        }
    }
}
