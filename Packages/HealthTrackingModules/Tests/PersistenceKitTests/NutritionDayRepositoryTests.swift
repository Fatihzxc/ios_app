import CoreModels
import Foundation
@testable import NutritionKit
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class NutritionDayRepositoryTests: XCTestCase {
    private enum FixtureFailure: Error, Equatable {
        case load
        case save
    }

    func testMissingDayIsCreatedOnceAndDifferentHoursFetchTheSameSnapshot() async throws {
        let fixture = try makeFixture(timeZoneID: "Europe/Istanbul")
        let morning = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 6,
            calendar: fixture.calendar
        )
        let evening = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 22,
            calendar: fixture.calendar
        )

        let missing = try await fixture.repository.fetchNutritionDay(containing: morning)
        XCTAssertNil(missing)
        let created = try await fixture.repository.fetchOrCreateNutritionDay(containing: morning)
        let fetched = try await fixture.repository.fetchNutritionDay(containing: evening)
        let repeated = try await fixture.repository.fetchOrCreateNutritionDay(containing: evening)

        XCTAssertEqual(created, fetched)
        XCTAssertEqual(created, repeated)
        XCTAssertEqual(created.id, fixture.generatedID)
        XCTAssertEqual(created.createdAt, fixture.now)
        XCTAssertEqual(created.updatedAt, fixture.now)
        XCTAssertEqual(created.day.start, fixture.calendar.startOfDay(for: morning))
        XCTAssertEqual(
            try ModelContext(fixture.container).fetchCount(
                FetchDescriptor<DailyNutritionLog>()
            ),
            1
        )
        assertEquatableSendable(created)
    }

    func testSpringAndAutumnDSTDaysRemainDistinctCalendarIntervals() async throws {
        let fixture = try makeFixture(timeZoneID: "America/New_York")
        let dates = [
            makeDate(year: 2026, month: 3, day: 8, hour: 12, calendar: fixture.calendar),
            makeDate(year: 2026, month: 3, day: 9, hour: 12, calendar: fixture.calendar),
            makeDate(year: 2026, month: 11, day: 1, hour: 12, calendar: fixture.calendar),
            makeDate(year: 2026, month: 11, day: 2, hour: 12, calendar: fixture.calendar),
        ]

        for date in dates {
            _ = try await fixture.repository.fetchOrCreateNutritionDay(containing: date)
        }
        let snapshots = try await fixture.repository.fetchNutritionDays()

        XCTAssertEqual(snapshots.count, 4)
        XCTAssertEqual(snapshots.map(\.day.start), snapshots.map(\.day.start).sorted())
        XCTAssertEqual(
            snapshots[0].day.end.timeIntervalSince(snapshots[0].day.start),
            23 * 60 * 60
        )
        XCTAssertEqual(
            snapshots[2].day.end.timeIntervalSince(snapshots[2].day.start),
            25 * 60 * 60
        )
    }

    func testExistingNonNormalizedDateIsNormalizedInsideTheCalendarDay() async throws {
        let fixture = try makeFixture(timeZoneID: "Europe/Istanbul")
        let afternoon = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 15,
            calendar: fixture.calendar
        )
        let writer = ModelContext(fixture.container)
        let existing = DailyNutritionLog(
            id: fixture.generatedID,
            createdAt: fixture.now,
            updatedAt: fixture.now.addingTimeInterval(-60),
            date: afternoon
        )
        writer.insert(existing)
        try writer.save()

        let snapshot = try await fixture.repository.fetchOrCreateNutritionDay(
            containing: afternoon
        )

        XCTAssertEqual(snapshot.id, existing.id)
        XCTAssertEqual(snapshot.day.start, fixture.calendar.startOfDay(for: afternoon))
        let stored = try ModelContext(fixture.container).fetch(
            FetchDescriptor<DailyNutritionLog>()
        )
        XCTAssertEqual(stored.first?.date, fixture.calendar.startOfDay(for: afternoon))
        XCTAssertEqual(stored.first?.updatedAt, fixture.now)
    }

    func testDuplicateLogicalDayFailsWithStableSortedIDsWithoutMutatingRows() async throws {
        let fixture = try makeFixture(timeZoneID: "UTC")
        let date = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 12,
            calendar: fixture.calendar
        )
        let firstID = uuid("00000000-0000-4000-8000-000000000101")
        let secondID = uuid("00000000-0000-4000-8000-000000000102")
        let writer = ModelContext(fixture.container)
        writer.insert(DailyNutritionLog(id: secondID, date: date))
        writer.insert(DailyNutritionLog(id: firstID, date: date.addingTimeInterval(-60)))
        try writer.save()
        let day = try NutritionDayKey(containing: date, calendar: fixture.calendar)

        do {
            _ = try await fixture.repository.fetchNutritionDay(containing: date)
            XCTFail("Expected duplicate local-day integrity failure.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryIntegrityError,
                .duplicateNutritionDays(dayStart: day.start, ids: [firstID, secondID])
            )
        }

        XCTAssertEqual(
            try ModelContext(fixture.container).fetchCount(
                FetchDescriptor<DailyNutritionLog>()
            ),
            2
        )
    }

    func testFetchAllUsesDayThenUUIDOrderingAndReturnsImmutableSnapshots() async throws {
        let fixture = try makeFixture(timeZoneID: "UTC")
        let writer = ModelContext(fixture.container)
        let older = DailyNutritionLog(
            id: uuid("00000000-0000-4000-8000-000000000111"),
            date: makeDate(
                year: 2026,
                month: 8,
                day: 20,
                hour: 0,
                calendar: fixture.calendar
            )
        )
        let newer = DailyNutritionLog(
            id: uuid("00000000-0000-4000-8000-000000000112"),
            date: makeDate(
                year: 2026,
                month: 8,
                day: 21,
                hour: 0,
                calendar: fixture.calendar
            )
        )
        writer.insert(newer)
        writer.insert(older)
        try writer.save()

        let snapshots = try await fixture.repository.fetchNutritionDays()

        XCTAssertEqual(snapshots.map(\.id), [older.id, newer.id])
        older.date = newer.date.addingTimeInterval(10 * 24 * 60 * 60)
        XCTAssertEqual(snapshots.map(\.id), [older.id, newer.id])
        XCTAssertNotEqual(snapshots[0].day.start, older.date)
    }

    func testFetchAllRejectsDuplicateIDsAcrossDifferentLogicalDays() async throws {
        let fixture = try makeFixture(timeZoneID: "UTC")
        let duplicateID = uuid("00000000-0000-4000-8000-000000000113")
        let writer = ModelContext(fixture.container)
        writer.insert(
            DailyNutritionLog(
                id: duplicateID,
                date: makeDate(
                    year: 2026,
                    month: 8,
                    day: 20,
                    hour: 12,
                    calendar: fixture.calendar
                )
            )
        )
        writer.insert(
            DailyNutritionLog(
                id: duplicateID,
                date: makeDate(
                    year: 2026,
                    month: 8,
                    day: 21,
                    hour: 12,
                    calendar: fixture.calendar
                )
            )
        )
        try writer.save()

        do {
            _ = try await fixture.repository.fetchNutritionDays()
            XCTFail("Expected duplicate nutrition-day IDs to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryIntegrityError,
                .duplicateNutritionDayIDs(id: duplicateID, count: 2)
            )
        }
    }

    func testSingleDayFetchRejectsIDDuplicatedOnAnotherLogicalDay() async throws {
        let fixture = try makeFixture(timeZoneID: "UTC")
        let duplicateID = uuid("00000000-0000-4000-8000-000000000114")
        let requestedDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 12,
            calendar: fixture.calendar
        )
        let writer = ModelContext(fixture.container)
        writer.insert(
            DailyNutritionLog(
                id: duplicateID,
                date: makeDate(
                    year: 2026,
                    month: 8,
                    day: 20,
                    hour: 12,
                    calendar: fixture.calendar
                )
            )
        )
        writer.insert(DailyNutritionLog(id: duplicateID, date: requestedDate))
        try writer.save()

        do {
            _ = try await fixture.repository.fetchNutritionDay(containing: requestedDate)
            XCTFail("Expected a cross-day duplicate nutrition-day ID failure.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryIntegrityError,
                .duplicateNutritionDayIDs(id: duplicateID, count: 2)
            )
        }
    }

    func testFetchOrCreateRejectsCrossDayDuplicateIDBeforeNormalizingTargetRow() async throws {
        let fixture = try makeFixture(timeZoneID: "UTC")
        let duplicateID = uuid("00000000-0000-4000-8000-000000000115")
        let earlierDate = makeDate(
            year: 2026,
            month: 8,
            day: 20,
            hour: 12,
            calendar: fixture.calendar
        )
        let targetDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 15,
            calendar: fixture.calendar
        )
        let originalUpdatedAt = targetDate.addingTimeInterval(-60)
        let writer = ModelContext(fixture.container)
        writer.insert(DailyNutritionLog(id: duplicateID, date: earlierDate))
        writer.insert(
            DailyNutritionLog(
                id: duplicateID,
                updatedAt: originalUpdatedAt,
                date: targetDate
            )
        )
        try writer.save()

        do {
            _ = try await fixture.repository.fetchOrCreateNutritionDay(
                containing: targetDate
            )
            XCTFail("Expected a cross-day duplicate nutrition-day ID failure.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryIntegrityError,
                .duplicateNutritionDayIDs(id: duplicateID, count: 2)
            )
        }

        let stored = try ModelContext(fixture.container).fetch(
            FetchDescriptor<DailyNutritionLog>()
        )
        XCTAssertEqual(stored.map(\.date).sorted(), [earlierDate, targetDate])
        XCTAssertEqual(
            stored.first(where: { $0.date == targetDate })?.updatedAt,
            originalUpdatedAt
        )
    }

    func testDeleteRemovesChildrenBeforeNullifyDayAndRejectsMissingID() async throws {
        let fixture = try makeFixture(timeZoneID: "UTC")
        let writer = ModelContext(fixture.container)
        let log = DailyNutritionLog(id: fixture.generatedID, date: fixture.now)
        let entry = MealEntry(
            id: uuid("00000000-0000-4000-8000-000000000121"),
            quantity: 1,
            loggedAt: fixture.now,
            dailyNutritionLog: log
        )
        writer.insert(log)
        writer.insert(entry)
        try writer.save()

        try await fixture.repository.deleteNutritionDay(id: log.id)

        let reader = ModelContext(fixture.container)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<MealEntry>()), 0)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<DailyNutritionLog>()), 0)
        do {
            try await fixture.repository.deleteNutritionDay(id: log.id)
            XCTFail("Expected a missing-day mutation error.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryMutationError,
                .nutritionDayNotFound(id: log.id)
            )
        }
    }

    func testDeleteRejectsDuplicateIDsWithoutMutatingEitherDay() async throws {
        let fixture = try makeFixture(timeZoneID: "UTC")
        let duplicateID = uuid("00000000-0000-4000-8000-000000000122")
        let writer = ModelContext(fixture.container)
        writer.insert(
            DailyNutritionLog(
                id: duplicateID,
                date: makeDate(
                    year: 2026,
                    month: 8,
                    day: 20,
                    hour: 12,
                    calendar: fixture.calendar
                )
            )
        )
        writer.insert(
            DailyNutritionLog(
                id: duplicateID,
                date: makeDate(
                    year: 2026,
                    month: 8,
                    day: 21,
                    hour: 12,
                    calendar: fixture.calendar
                )
            )
        )
        try writer.save()

        do {
            try await fixture.repository.deleteNutritionDay(id: duplicateID)
            XCTFail("Expected duplicate nutrition-day IDs to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryIntegrityError,
                .duplicateNutritionDayIDs(id: duplicateID, count: 2)
            )
        }

        XCTAssertEqual(
            try ModelContext(fixture.container).fetchCount(
                FetchDescriptor<DailyNutritionLog>()
            ),
            2
        )
    }

    func testCreateSaveFailureRollsBackWithoutLeavingAPartialDay() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let calendar = makeCalendar(timeZoneID: "UTC")
        var rollbackWasCalled = false
        let repository = SwiftDataNutritionRepository(
            modelContext: writer,
            calendar: calendar,
            now: { Date(timeIntervalSinceReferenceDate: 100) },
            makeID: { self.uuid("00000000-0000-4000-8000-000000000131") },
            save: { throw FixtureFailure.save },
            rollback: {
                rollbackWasCalled = true
                writer.rollback()
            }
        )

        do {
            _ = try await repository.fetchOrCreateNutritionDay(
                containing: Date(timeIntervalSinceReferenceDate: 100)
            )
            XCTFail("Expected the injected save failure.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryOperationError,
                .saveFailed
            )
        }

        XCTAssertTrue(rollbackWasCalled)
        XCTAssertEqual(
            try ModelContext(container).fetchCount(FetchDescriptor<DailyNutritionLog>()),
            0
        )
    }

    func testGeneratedIDCollisionFailsBeforeInsertingAnotherDay() async throws {
        let fixture = try makeFixture(timeZoneID: "UTC")
        let existingDate = makeDate(
            year: 2026,
            month: 8,
            day: 20,
            hour: 12,
            calendar: fixture.calendar
        )
        let requestedDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 12,
            calendar: fixture.calendar
        )
        let writer = ModelContext(fixture.container)
        writer.insert(DailyNutritionLog(id: fixture.generatedID, date: existingDate))
        try writer.save()

        do {
            _ = try await fixture.repository.fetchOrCreateNutritionDay(
                containing: requestedDate
            )
            XCTFail("Expected the generated nutrition-day ID collision.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryIntegrityError,
                .nutritionDayIDCollision(id: fixture.generatedID)
            )
        }

        let stored = try ModelContext(fixture.container).fetch(
            FetchDescriptor<DailyNutritionLog>()
        )
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.date, existingDate)
    }

    func testDayFetchFailureMapsToStableLoadError() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let calendar = makeCalendar(timeZoneID: "UTC")
        let repository = SwiftDataNutritionRepository(
            modelContext: context,
            calendar: calendar,
            now: { Date(timeIntervalSinceReferenceDate: 100) },
            makeID: { self.uuid("00000000-0000-4000-8000-000000000141") },
            fetchDays: { _ in throw FixtureFailure.load },
            fetchEntries: { try context.fetch($0) },
            save: { try context.save() },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.fetchNutritionDays()
            XCTFail("Expected the injected day-load failure.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryOperationError,
                .loadFailed
            )
        }
    }

    func testEntryFetchFailureMapsToStableLoadErrorWithoutDeletingTheDay() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let calendar = makeCalendar(timeZoneID: "UTC")
        let day = DailyNutritionLog(
            id: uuid("00000000-0000-4000-8000-000000000142"),
            date: Date(timeIntervalSinceReferenceDate: 100)
        )
        context.insert(day)
        try context.save()
        let repository = SwiftDataNutritionRepository(
            modelContext: context,
            calendar: calendar,
            now: { Date(timeIntervalSinceReferenceDate: 100) },
            makeID: { self.uuid("00000000-0000-4000-8000-000000000143") },
            fetchDays: { try context.fetch($0) },
            fetchEntries: { _ in throw FixtureFailure.load },
            save: { try context.save() },
            rollback: { context.rollback() }
        )

        do {
            try await repository.deleteNutritionDay(id: day.id)
            XCTFail("Expected the injected meal-entry-load failure.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryOperationError,
                .loadFailed
            )
        }

        XCTAssertEqual(
            try ModelContext(container).fetchCount(FetchDescriptor<DailyNutritionLog>()),
            1
        )
    }

    func testNormalizationSaveFailureRollsBackDateAndTimestamp() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let calendar = makeCalendar(timeZoneID: "UTC")
        let afternoon = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 15,
            calendar: calendar
        )
        let originalUpdatedAt = afternoon.addingTimeInterval(-60)
        let writer = ModelContext(container)
        writer.insert(
            DailyNutritionLog(
                id: uuid("00000000-0000-4000-8000-000000000144"),
                updatedAt: originalUpdatedAt,
                date: afternoon
            )
        )
        try writer.save()
        let context = ModelContext(container)
        let repository = SwiftDataNutritionRepository(
            modelContext: context,
            calendar: calendar,
            now: { afternoon },
            makeID: { self.uuid("00000000-0000-4000-8000-000000000145") },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.fetchOrCreateNutritionDay(containing: afternoon)
            XCTFail("Expected normalization save failure.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryOperationError,
                .saveFailed
            )
        }

        let stored = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<DailyNutritionLog>()).first
        )
        XCTAssertEqual(stored.date, afternoon)
        XCTAssertEqual(stored.updatedAt, originalUpdatedAt)
    }

    func testDeleteSaveFailureRollsBackParentAndChildDeletes() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let calendar = makeCalendar(timeZoneID: "UTC")
        let day = DailyNutritionLog(
            id: uuid("00000000-0000-4000-8000-000000000146"),
            date: Date(timeIntervalSinceReferenceDate: 100)
        )
        context.insert(day)
        context.insert(
            MealEntry(
                id: uuid("00000000-0000-4000-8000-000000000147"),
                quantity: 1,
                loggedAt: day.date,
                dailyNutritionLog: day
            )
        )
        try context.save()
        let repository = SwiftDataNutritionRepository(
            modelContext: context,
            calendar: calendar,
            now: { day.date },
            makeID: { self.uuid("00000000-0000-4000-8000-000000000148") },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )

        do {
            try await repository.deleteNutritionDay(id: day.id)
            XCTFail("Expected delete save failure.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryOperationError,
                .deleteFailed
            )
        }

        let reader = ModelContext(container)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<DailyNutritionLog>()), 1)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<MealEntry>()), 1)
    }

    private func makeFixture(
        timeZoneID: String
    ) throws -> (
        container: ModelContainer,
        calendar: Calendar,
        now: Date,
        generatedID: UUID,
        repository: SwiftDataNutritionRepository
    ) {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let calendar = makeCalendar(timeZoneID: timeZoneID)
        let now = Date(timeIntervalSinceReferenceDate: 900_000)
        let generatedID = uuid("00000000-0000-4000-8000-000000000100")
        var nextID = 100
        return (
            container,
            calendar,
            now,
            generatedID,
            SwiftDataNutritionRepository(
                modelContext: ModelContext(container),
                calendar: calendar,
                now: { now },
                makeID: {
                    defer { nextID += 1 }
                    return self.uuid(
                        String(
                            format: "00000000-0000-4000-8000-%012d",
                            nextID
                        )
                    )
                }
            )
        )
    }

    private func makeCalendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
