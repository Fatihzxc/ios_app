import CoreModels
import Foundation
import SleepMoodKit
import SwiftData

@MainActor
public final class SwiftDataLifestyleRepository: LifestyleRepository {
    private struct DayBoundary {
        let start: Date
        let end: Date
    }

    private struct DayRows {
        let sleep: SleepLog?
        let mood: MoodLog?
        let snapshot: LifestyleDaySnapshot
    }

    private let modelContext: ModelContext
    private let calendar: Calendar
    private let now: @MainActor () -> Date
    private let makeID: @MainActor () -> UUID
    private let saveOperation: @MainActor () throws -> Void
    private let rollbackOperation: @MainActor () -> Void

    public init(
        modelContext: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
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

    public func fetchLifestyleDay(
        containing date: Date
    ) async throws -> LifestyleDaySnapshot {
        try readDay(containing: date).snapshot
    }

    public func upsertLifestyleDay(
        _ input: LifestyleDayInput,
        expected: LifestyleDaySnapshot
    ) async throws -> LifestyleDaySnapshot {
        let inputBoundary = try boundary(containing: input.date)
        guard expected.dayStart == inputBoundary.start,
              expected.dayEnd == inputBoundary.end else {
            throw LifestyleRepositoryMutationError.dayMismatch(
                expectedDayStart: expected.dayStart,
                inputDayStart: inputBoundary.start
            )
        }

        let current = try readDay(containing: input.date)
        try validateExpected(expected, against: current.snapshot)

        var occupiedIDs = try allIdentifiers()
        let timestamp = now()
        var resultingSleep = current.sleep
        var resultingMood = current.mood

        if let sleep = input.sleep {
            if let model = current.sleep {
                model.date = input.date
                model.durationHours = sleep.durationHours
                model.quality = sleep.quality
                model.note = sleep.note
                model.updatedAt = timestamp
                resultingSleep = model
            } else {
                let id = makeID()
                guard occupiedIDs.insert(id).inserted else {
                    throw LifestyleRepositoryIntegrityError.generatedIDCollision(id: id)
                }
                let model = SleepLog(
                    id: id,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    date: input.date,
                    durationHours: sleep.durationHours,
                    quality: sleep.quality,
                    note: sleep.note
                )
                modelContext.insert(model)
                resultingSleep = model
            }
        }

        if let mood = input.mood {
            if let model = current.mood {
                model.date = input.date
                model.moodScore = mood.score
                model.moodTags = mood.tags
                model.energy = mood.energy
                model.note = mood.note
                model.updatedAt = timestamp
                resultingMood = model
            } else {
                let id = makeID()
                guard occupiedIDs.insert(id).inserted else {
                    rollbackOperation()
                    throw LifestyleRepositoryIntegrityError.generatedIDCollision(id: id)
                }
                let model = MoodLog(
                    id: id,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    date: input.date,
                    moodScore: mood.score,
                    moodTags: mood.tags,
                    energy: mood.energy,
                    note: mood.note
                )
                modelContext.insert(model)
                resultingMood = model
            }
        }

        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw LifestyleRepositoryOperationError.saveFailed
        }

        return LifestyleDaySnapshot(
            dayStart: inputBoundary.start,
            dayEnd: inputBoundary.end,
            sleep: try resultingSleep.map {
                try validatedSleepSnapshot(from: $0)
            },
            mood: try resultingMood.map {
                try validatedMoodSnapshot(from: $0)
            }
        )
    }

    private func boundary(containing date: Date) throws -> DayBoundary {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start),
              end > start else {
            throw LifestyleRepositoryOperationError.loadFailed
        }
        return DayBoundary(start: start, end: end)
    }

    private func readDay(containing date: Date) throws -> DayRows {
        let boundary = try boundary(containing: date)
        let start = boundary.start
        let end = boundary.end
        let sleepRows: [SleepLog]
        let moodRows: [MoodLog]
        do {
            sleepRows = try modelContext.fetch(
                FetchDescriptor<SleepLog>(
                    predicate: #Predicate { log in
                        log.date >= start && log.date < end
                    }
                )
            )
            moodRows = try modelContext.fetch(
                FetchDescriptor<MoodLog>(
                    predicate: #Predicate { log in
                        log.date >= start && log.date < end
                    }
                )
            )
        } catch {
            throw LifestyleRepositoryOperationError.loadFailed
        }

        guard sleepRows.count <= 1 else {
            throw LifestyleRepositoryIntegrityError.multipleSleepLogs(
                dayStart: start,
                count: sleepRows.count
            )
        }
        guard moodRows.count <= 1 else {
            throw LifestyleRepositoryIntegrityError.multipleMoodLogs(
                dayStart: start,
                count: moodRows.count
            )
        }

        let sleep = sleepRows.first
        let mood = moodRows.first
        let snapshot = LifestyleDaySnapshot(
            dayStart: start,
            dayEnd: end,
            sleep: try sleep.map {
                try validatedSleepSnapshot(from: $0)
            },
            mood: try mood.map {
                try validatedMoodSnapshot(from: $0)
            }
        )
        return DayRows(
            sleep: sleep,
            mood: mood,
            snapshot: snapshot
        )
    }

    private func validateExpected(
        _ expected: LifestyleDaySnapshot,
        against actual: LifestyleDaySnapshot
    ) throws {
        guard expected.sleep?.id == actual.sleep?.id,
              expected.sleep?.updatedAt == actual.sleep?.updatedAt else {
            throw LifestyleRepositoryMutationError.staleSleep(
                expectedUpdatedAt: expected.sleep?.updatedAt,
                actualUpdatedAt: actual.sleep?.updatedAt
            )
        }
        guard expected.mood?.id == actual.mood?.id,
              expected.mood?.updatedAt == actual.mood?.updatedAt else {
            throw LifestyleRepositoryMutationError.staleMood(
                expectedUpdatedAt: expected.mood?.updatedAt,
                actualUpdatedAt: actual.mood?.updatedAt
            )
        }
    }

    private func allIdentifiers() throws -> Set<UUID> {
        do {
            let sleepIDs = try modelContext.fetch(FetchDescriptor<SleepLog>()).map(\.id)
            let moodIDs = try modelContext.fetch(FetchDescriptor<MoodLog>()).map(\.id)
            return Set(sleepIDs + moodIDs)
        } catch {
            throw LifestyleRepositoryOperationError.loadFailed
        }
    }

    private func validatedSleepSnapshot(
        from model: SleepLog
    ) throws -> SleepLogSnapshot {
        let input: SleepEntryInput
        do {
            input = try SleepEntryInput(
                durationHours: model.durationHours,
                quality: model.quality,
                note: model.note
            )
        } catch {
            throw LifestyleRepositoryIntegrityError.invalidPersistedSleepLog(id: model.id)
        }
        guard input.note == model.note else {
            throw LifestyleRepositoryIntegrityError.invalidPersistedSleepLog(id: model.id)
        }
        return SleepLogSnapshot(
            id: model.id,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            date: model.date,
            durationHours: input.durationHours,
            quality: input.quality,
            note: input.note
        )
    }

    private func validatedMoodSnapshot(
        from model: MoodLog
    ) throws -> MoodLogSnapshot {
        let input: MoodEntryInput
        do {
            input = try MoodEntryInput(
                score: model.moodScore,
                tags: model.moodTags,
                energy: model.energy,
                note: model.note
            )
        } catch {
            throw LifestyleRepositoryIntegrityError.invalidPersistedMoodLog(id: model.id)
        }
        guard input.tags == model.moodTags,
              input.note == model.note else {
            throw LifestyleRepositoryIntegrityError.invalidPersistedMoodLog(id: model.id)
        }
        return MoodLogSnapshot(
            id: model.id,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            date: model.date,
            score: input.score,
            tags: input.tags,
            energy: input.energy,
            note: input.note
        )
    }
}
