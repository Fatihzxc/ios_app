import CoreModels
import Foundation
@testable import PersistenceKit
@testable import SleepMoodKit
import SwiftData
import XCTest

@MainActor
final class LifestyleRepositoryTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testFetchUsesInjectedCalendarHalfOpenLocalDayAcrossDST() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let calendar = newYorkCalendar()
        let requestedDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12))
        )
        let dayStart = calendar.startOfDay(for: requestedDate)
        let dayEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: dayStart))
        XCTAssertEqual(dayEnd.timeIntervalSince(dayStart), 23 * 60 * 60)

        writer.insert(sleep(id: uuid("00000000-0000-4000-8000-000000000401"), date: dayStart))
        writer.insert(mood(id: uuid("00000000-0000-4000-8000-000000000402"), date: dayEnd.addingTimeInterval(-1)))
        writer.insert(sleep(id: uuid("00000000-0000-4000-8000-000000000403"), date: dayEnd))
        try writer.save()
        let repository = SwiftDataLifestyleRepository(
            modelContext: ModelContext(container),
            calendar: calendar
        )

        let day = try await repository.fetchLifestyleDay(containing: requestedDate)

        XCTAssertEqual(day.dayStart, dayStart)
        XCTAssertEqual(day.dayEnd, dayEnd)
        XCTAssertEqual(day.sleep?.id, uuid("00000000-0000-4000-8000-000000000401"))
        XCTAssertEqual(day.mood?.id, uuid("00000000-0000-4000-8000-000000000402"))
    }

    func testFetchUsesTwentyFiveHourFallBackDayWithoutLeakingTheNextDay() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let calendar = newYorkCalendar()
        let requestedDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2024, month: 11, day: 3, hour: 12))
        )
        let dayStart = calendar.startOfDay(for: requestedDate)
        let dayEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: dayStart))
        XCTAssertEqual(dayEnd.timeIntervalSince(dayStart), 25 * 60 * 60)

        writer.insert(sleep(id: uuid("00000000-0000-4000-8000-000000000404"), date: dayStart))
        writer.insert(mood(id: uuid("00000000-0000-4000-8000-000000000405"), date: dayEnd.addingTimeInterval(-1)))
        writer.insert(mood(id: uuid("00000000-0000-4000-8000-000000000406"), date: dayEnd))
        try writer.save()
        let repository = SwiftDataLifestyleRepository(
            modelContext: ModelContext(container),
            calendar: calendar
        )

        let day = try await repository.fetchLifestyleDay(containing: requestedDate)

        XCTAssertEqual(day.dayStart, dayStart)
        XCTAssertEqual(day.dayEnd, dayEnd)
        XCTAssertEqual(day.sleep?.id, uuid("00000000-0000-4000-8000-000000000404"))
        XCTAssertEqual(day.mood?.id, uuid("00000000-0000-4000-8000-000000000405"))
    }

    func testFetchUsesInjectedIstanbulBoundaryRatherThanSystemCalendar() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let calendar = istanbulCalendar()
        let requestedDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2024, month: 7, day: 5, hour: 23))
        )
        let expectedStart = calendar.startOfDay(for: requestedDate)
        let expectedEnd = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 1, to: expectedStart)
        )
        let repository = SwiftDataLifestyleRepository(
            modelContext: ModelContext(container),
            calendar: calendar
        )

        let day = try await repository.fetchLifestyleDay(containing: requestedDate)

        XCTAssertEqual(day.dayStart, expectedStart)
        XCTAssertEqual(day.dayEnd, expectedEnd)
        XCTAssertNil(day.sleep)
        XCTAssertNil(day.mood)
    }

    func testFetchReturnsEmptyOrOneAndFailsClosedForMultipleRowsPerSection() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let calendar = utcCalendar()
        let date = self.date(10_000)
        let repository = SwiftDataLifestyleRepository(
            modelContext: ModelContext(container),
            calendar: calendar
        )

        let empty = try await repository.fetchLifestyleDay(containing: date)
        XCTAssertNil(empty.sleep)
        XCTAssertNil(empty.mood)

        let writer = ModelContext(container)
        writer.insert(sleep(id: uuid("00000000-0000-4000-8000-000000000411"), date: date))
        try writer.save()
        let one = try await repository.fetchLifestyleDay(containing: date)
        XCTAssertEqual(one.sleep?.id, uuid("00000000-0000-4000-8000-000000000411"))

        writer.insert(sleep(id: uuid("00000000-0000-4000-8000-000000000412"), date: date))
        try writer.save()
        do {
            _ = try await repository.fetchLifestyleDay(containing: date)
            XCTFail("Expected duplicate same-day sleep rows to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? LifestyleRepositoryIntegrityError,
                .multipleSleepLogs(dayStart: calendar.startOfDay(for: date), count: 2)
            )
        }

        let moodContainer = try ModelContainerFactory.make(for: .inMemory)
        let moodWriter = ModelContext(moodContainer)
        moodWriter.insert(mood(id: uuid("00000000-0000-4000-8000-000000000413"), date: date))
        moodWriter.insert(mood(id: uuid("00000000-0000-4000-8000-000000000414"), date: date))
        try moodWriter.save()
        let moodRepository = SwiftDataLifestyleRepository(
            modelContext: ModelContext(moodContainer),
            calendar: calendar
        )
        do {
            _ = try await moodRepository.fetchLifestyleDay(containing: date)
            XCTFail("Expected duplicate same-day mood rows to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? LifestyleRepositoryIntegrityError,
                .multipleMoodLogs(dayStart: calendar.startOfDay(for: date), count: 2)
            )
        }
    }

    func testCombinedUpsertCreatesThenEditsSameDayWithoutDuplicates() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let calendar = utcCalendar()
        let date = self.date(20_000)
        var identifiers = [
            uuid("00000000-0000-4000-8000-000000000421"),
            uuid("00000000-0000-4000-8000-000000000422"),
        ]
        var timestamps = [self.date(21_000), self.date(22_000)]
        let repository = SwiftDataLifestyleRepository(
            modelContext: context,
            calendar: calendar,
            now: { timestamps.removeFirst() },
            makeID: { identifiers.removeFirst() }
        )
        let empty = try await repository.fetchLifestyleDay(containing: date)
        let firstInput = try LifestyleDayInput(
            date: date,
            sleep: try SleepEntryInput(durationHours: 7, quality: 8, note: "İlk"),
            mood: try MoodEntryInput(score: 7, tags: ["Sakin"], energy: 6, note: nil)
        )

        let created = try await repository.upsertLifestyleDay(firstInput, expected: empty)
        let sleepID = try XCTUnwrap(created.sleep?.id)
        let moodID = try XCTUnwrap(created.mood?.id)
        let edited = try await repository.upsertLifestyleDay(
            try LifestyleDayInput(
                date: date.addingTimeInterval(60),
                sleep: try SleepEntryInput(durationHours: 8, quality: 9, note: "Düzenlendi"),
                mood: try MoodEntryInput(score: 8, tags: ["Odak"], energy: 7, note: "İyi")
            ),
            expected: created
        )

        XCTAssertEqual(edited.sleep?.id, sleepID)
        XCTAssertEqual(edited.mood?.id, moodID)
        XCTAssertEqual(edited.sleep?.durationHours, 8)
        XCTAssertEqual(edited.mood?.tags, ["Odak"])
        XCTAssertEqual(edited.sleep?.updatedAt, self.date(22_000))
        XCTAssertEqual(edited.mood?.updatedAt, self.date(22_000))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SleepLog>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MoodLog>()), 1)
    }

    func testSingleSectionUpsertPreservesTheExistingOtherSectionExactly() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let entryDate = date(23_000)
        let originalTimestamp = date(23_100)
        let moodID = uuid("00000000-0000-4000-8000-000000000423")
        let sleepID = uuid("00000000-0000-4000-8000-000000000424")
        let writer = ModelContext(container)
        writer.insert(
            mood(
                id: moodID,
                date: entryDate,
                updatedAt: originalTimestamp,
                score: 6
            )
        )
        try writer.save()
        let context = ModelContext(container)
        let repository = SwiftDataLifestyleRepository(
            modelContext: context,
            calendar: utcCalendar(),
            now: { self.date(23_200) },
            makeID: { sleepID }
        )
        let expected = try await repository.fetchLifestyleDay(containing: entryDate)

        let saved = try await repository.upsertLifestyleDay(
            try LifestyleDayInput(
                date: entryDate,
                sleep: try SleepEntryInput(durationHours: 8, quality: 9, note: nil),
                mood: nil
            ),
            expected: expected
        )

        XCTAssertEqual(saved.sleep?.id, sleepID)
        XCTAssertEqual(saved.mood, expected.mood)
        let freshMood = try XCTUnwrap(context.fetch(FetchDescriptor<MoodLog>()).first)
        XCTAssertEqual(freshMood.id, moodID)
        XCTAssertEqual(freshMood.moodScore, 6)
        XCTAssertEqual(freshMood.updatedAt, originalTimestamp)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SleepLog>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MoodLog>()), 1)

        let moodOnly = try await repository.upsertLifestyleDay(
            try LifestyleDayInput(
                date: entryDate,
                sleep: nil,
                mood: try MoodEntryInput(
                    score: 7,
                    tags: ["Odak"],
                    energy: 8,
                    note: nil
                )
            ),
            expected: saved
        )

        XCTAssertEqual(moodOnly.sleep, saved.sleep)
        XCTAssertEqual(moodOnly.mood?.id, moodID)
        XCTAssertEqual(moodOnly.mood?.score, 7)
        XCTAssertEqual(moodOnly.mood?.tags, ["Odak"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SleepLog>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MoodLog>()), 1)
    }

    func testInvalidPersistedRowsFailClosedInsteadOfNormalizingSilently() async throws {
        let calendar = utcCalendar()
        let entryDate = date(25_000)
        let invalidSleepContainer = try ModelContainerFactory.make(for: .inMemory)
        let sleepWriter = ModelContext(invalidSleepContainer)
        let sleepID = uuid("00000000-0000-4000-8000-000000000425")
        sleepWriter.insert(sleep(id: sleepID, date: entryDate, durationHours: 0))
        try sleepWriter.save()
        let sleepRepository = SwiftDataLifestyleRepository(
            modelContext: ModelContext(invalidSleepContainer),
            calendar: calendar
        )
        do {
            _ = try await sleepRepository.fetchLifestyleDay(containing: entryDate)
            XCTFail("Expected invalid persisted sleep data to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? LifestyleRepositoryIntegrityError,
                .invalidPersistedSleepLog(id: sleepID)
            )
        }

        let invalidMoodContainer = try ModelContainerFactory.make(for: .inMemory)
        let moodWriter = ModelContext(invalidMoodContainer)
        let moodID = uuid("00000000-0000-4000-8000-000000000426")
        moodWriter.insert(
            MoodLog(
                id: moodID,
                createdAt: entryDate,
                updatedAt: entryDate,
                date: entryDate,
                moodScore: nil,
                moodTags: ["  "],
                energy: 5,
                note: nil
            )
        )
        try moodWriter.save()
        let moodRepository = SwiftDataLifestyleRepository(
            modelContext: ModelContext(invalidMoodContainer),
            calendar: calendar
        )
        do {
            _ = try await moodRepository.fetchLifestyleDay(containing: entryDate)
            XCTFail("Expected invalid persisted mood data to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? LifestyleRepositoryIntegrityError,
                .invalidPersistedMoodLog(id: moodID)
            )
        }
    }

    func testCombinedFailureRollsBackBothSectionsExactly() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let originalTimestamp = date(30_000)
        let entryDate = date(29_000)
        let writer = ModelContext(container)
        let sleepID = uuid("00000000-0000-4000-8000-000000000431")
        let moodID = uuid("00000000-0000-4000-8000-000000000432")
        writer.insert(
            sleep(
                id: sleepID,
                date: entryDate,
                updatedAt: originalTimestamp,
                durationHours: 6
            )
        )
        writer.insert(
            mood(
                id: moodID,
                date: entryDate,
                updatedAt: originalTimestamp,
                score: 5
            )
        )
        try writer.save()
        let context = ModelContext(container)
        let repository = SwiftDataLifestyleRepository(
            modelContext: context,
            calendar: utcCalendar(),
            now: { self.date(31_000) },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )
        let expected = try await repository.fetchLifestyleDay(containing: entryDate)

        do {
            _ = try await repository.upsertLifestyleDay(
                try LifestyleDayInput(
                    date: entryDate,
                    sleep: try SleepEntryInput(durationHours: 8, quality: 9, note: "Yeni"),
                    mood: try MoodEntryInput(score: 9, tags: ["Mutlu"], energy: 8, note: "Yeni")
                ),
                expected: expected
            )
            XCTFail("Expected the combined save to roll back.")
        } catch {
            XCTAssertEqual(error as? LifestyleRepositoryOperationError, .saveFailed)
        }

        let fresh = ModelContext(container)
        let preservedSleep = try XCTUnwrap(fresh.fetch(FetchDescriptor<SleepLog>()).first)
        let preservedMood = try XCTUnwrap(fresh.fetch(FetchDescriptor<MoodLog>()).first)
        XCTAssertEqual(preservedSleep.id, sleepID)
        XCTAssertEqual(preservedSleep.durationHours, 6)
        XCTAssertEqual(preservedSleep.updatedAt, originalTimestamp)
        XCTAssertEqual(preservedMood.id, moodID)
        XCTAssertEqual(preservedMood.moodScore, 5)
        XCTAssertEqual(preservedMood.updatedAt, originalTimestamp)
    }

    func testCombinedCreateFailureRollsBackBothNewRows() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let entryDate = date(35_000)
        let repository = SwiftDataLifestyleRepository(
            modelContext: context,
            calendar: utcCalendar(),
            now: { self.date(35_100) },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )
        let expected = try await repository.fetchLifestyleDay(containing: entryDate)

        do {
            _ = try await repository.upsertLifestyleDay(
                try LifestyleDayInput(
                    date: entryDate,
                    sleep: try SleepEntryInput(durationHours: 8, quality: 9, note: nil),
                    mood: try MoodEntryInput(
                        score: 8,
                        tags: ["Sakin"],
                        energy: 7,
                        note: nil
                    )
                ),
                expected: expected
            )
            XCTFail("Expected both new sections to roll back together.")
        } catch {
            XCTAssertEqual(error as? LifestyleRepositoryOperationError, .saveFailed)
        }

        let fresh = ModelContext(container)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<SleepLog>()), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<MoodLog>()), 0)
    }

    func testUpsertRejectsStaleSectionWithoutMutatingEitherRecord() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let entryDate = date(40_000)
        let originalTimestamp = date(41_000)
        let writer = ModelContext(container)
        let sleepID = uuid("00000000-0000-4000-8000-000000000441")
        let moodID = uuid("00000000-0000-4000-8000-000000000442")
        writer.insert(sleep(id: sleepID, date: entryDate, updatedAt: originalTimestamp))
        writer.insert(mood(id: moodID, date: entryDate, updatedAt: originalTimestamp))
        try writer.save()
        let loadingRepository = SwiftDataLifestyleRepository(
            modelContext: ModelContext(container),
            calendar: utcCalendar()
        )
        let loaded = try await loadingRepository.fetchLifestyleDay(containing: entryDate)

        let concurrentContext = ModelContext(container)
        let concurrentMood = try XCTUnwrap(concurrentContext.fetch(FetchDescriptor<MoodLog>()).first)
        concurrentMood.energy = 10
        concurrentMood.updatedAt = date(41_500)
        try concurrentContext.save()
        let repository = SwiftDataLifestyleRepository(
            modelContext: ModelContext(container),
            calendar: utcCalendar(),
            now: { self.date(42_000) }
        )

        do {
            _ = try await repository.upsertLifestyleDay(
                try LifestyleDayInput(
                    date: entryDate,
                    sleep: try SleepEntryInput(durationHours: 9, quality: 9, note: nil),
                    mood: try MoodEntryInput(score: 9, tags: [], energy: 9, note: nil)
                ),
                expected: loaded
            )
            XCTFail("Expected a stale mood failure.")
        } catch {
            XCTAssertEqual(
                error as? LifestyleRepositoryMutationError,
                .staleMood(
                    expectedUpdatedAt: originalTimestamp,
                    actualUpdatedAt: date(41_500)
                )
            )
        }

        let fresh = ModelContext(container)
        let preservedSleep = try XCTUnwrap(fresh.fetch(FetchDescriptor<SleepLog>()).first)
        let preservedMood = try XCTUnwrap(fresh.fetch(FetchDescriptor<MoodLog>()).first)
        XCTAssertEqual(preservedSleep.durationHours, 7)
        XCTAssertEqual(preservedSleep.updatedAt, originalTimestamp)
        XCTAssertEqual(preservedMood.energy, 10)
        XCTAssertEqual(preservedMood.updatedAt, date(41_500))
    }

    func testUpsertRejectsAnExpectedSnapshotFromAnotherLocalDay() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let calendar = utcCalendar()
        let firstDay = date(90_000)
        let secondDay = firstDay.addingTimeInterval(86_400)
        let repository = SwiftDataLifestyleRepository(
            modelContext: ModelContext(container),
            calendar: calendar
        )
        let expected = try await repository.fetchLifestyleDay(containing: firstDay)

        do {
            _ = try await repository.upsertLifestyleDay(
                try LifestyleDayInput(
                    date: secondDay,
                    sleep: try SleepEntryInput(durationHours: 8, quality: 8, note: nil),
                    mood: nil
                ),
                expected: expected
            )
            XCTFail("Expected a cross-day optimistic snapshot to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? LifestyleRepositoryMutationError,
                .dayMismatch(
                    expectedDayStart: calendar.startOfDay(for: firstDay),
                    inputDayStart: calendar.startOfDay(for: secondDay)
                )
            )
        }

        let fresh = ModelContext(container)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<SleepLog>()), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<MoodLog>()), 0)
    }

    private func sleep(
        id: UUID,
        date: Date,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 1_000),
        durationHours: Double = 7
    ) -> SleepLog {
        SleepLog(
            id: id,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            date: date,
            durationHours: durationHours,
            quality: 8,
            note: nil
        )
    }

    private func mood(
        id: UUID,
        date: Date,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 1_000),
        score: Int = 7
    ) -> MoodLog {
        MoodLog(
            id: id,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            date: date,
            moodScore: score,
            moodTags: ["Sakin"],
            energy: 6,
            note: nil
        )
    }

    private func newYorkCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func istanbulCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
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
}
