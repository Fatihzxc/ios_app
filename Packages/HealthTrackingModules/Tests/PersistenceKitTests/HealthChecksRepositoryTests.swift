import CoreModels
import Foundation
@testable import HealthChecksKit
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class HealthChecksRepositoryTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testReminderCRUDTrimsInputAndReturnsStableDueDateOrdering() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        var ids = [uuid(502), uuid(501)]
        var timestamps = [date(20_000), date(21_000), date(22_000)]
        let repository = SwiftDataHealthChecksRepository(
            modelContext: context,
            calendar: calendar("Europe/Istanbul"),
            now: { timestamps.removeFirst() },
            makeID: { ids.removeFirst() }
        )

        let later = try await repository.createReminder(
            try input(name: "  Ferritin  ", dueDate: date(40_000), recurrence: .monthly)
        )
        let earlier = try await repository.createReminder(
            try input(name: "D vitamini", dueDate: date(30_000), recurrence: .none)
        )

        XCTAssertEqual(later.name, "Ferritin")
        let fetchedIDs = try await repository.fetchReminders().map(\.id)
        XCTAssertEqual(fetchedIDs, [earlier.id, later.id])

        let updated = try await repository.updateReminder(
            id: later.id,
            expectedUpdatedAt: later.updatedAt,
            input: try input(
                name: "  Genel check-up ",
                dueDate: date(25_000),
                recurrence: .yearly
            )
        )
        XCTAssertEqual(updated.name, "Genel check-up")
        XCTAssertEqual(updated.updatedAt, date(22_000))
        let updatedOrder = try await repository.fetchReminders().map(\.id)
        XCTAssertEqual(updatedOrder, [updated.id, earlier.id])

        try await repository.deleteReminder(
            id: updated.id,
            expectedUpdatedAt: updated.updatedAt
        )
        let remainingIDs = try await repository.fetchReminders().map(\.id)
        XCTAssertEqual(remainingIDs, [earlier.id])
    }

    func testDuplicateIDsInvalidRowsAndGeneratedCollisionFailClosed() async throws {
        let duplicateContainer = try ModelContainerFactory.make(for: .inMemory)
        let duplicateWriter = ModelContext(duplicateContainer)
        let duplicateID = uuid(503)
        duplicateWriter.insert(reminder(id: duplicateID, name: "Bir"))
        duplicateWriter.insert(reminder(id: duplicateID, name: "İki"))
        try duplicateWriter.save()

        do {
            _ = try await SwiftDataHealthChecksRepository(
                modelContext: ModelContext(duplicateContainer),
                calendar: calendar("Europe/Istanbul")
            ).fetchReminders()
            XCTFail("Duplicate reminder IDs must fail closed.")
        } catch {
            XCTAssertEqual(
                error as? HealthChecksRepositoryIntegrityError,
                .duplicateReminderIDs(id: duplicateID, count: 2)
            )
        }

        let invalidContainer = try ModelContainerFactory.make(for: .inMemory)
        let invalidWriter = ModelContext(invalidContainer)
        let invalidID = uuid(504)
        invalidWriter.insert(reminder(id: invalidID, name: "  "))
        try invalidWriter.save()
        do {
            _ = try await SwiftDataHealthChecksRepository(
                modelContext: ModelContext(invalidContainer),
                calendar: calendar("Europe/Istanbul")
            ).fetchReminders()
            XCTFail("Invalid persisted reminder values must fail closed.")
        } catch {
            XCTAssertEqual(
                error as? HealthChecksRepositoryIntegrityError,
                .invalidPersistedReminder(id: invalidID)
            )
        }

        let collisionContainer = try ModelContainerFactory.make(for: .inMemory)
        let collisionWriter = ModelContext(collisionContainer)
        let collisionID = uuid(505)
        collisionWriter.insert(reminder(id: collisionID))
        try collisionWriter.save()
        do {
            _ = try await SwiftDataHealthChecksRepository(
                modelContext: ModelContext(collisionContainer),
                calendar: calendar("Europe/Istanbul"),
                makeID: { collisionID }
            ).createReminder(
                try input(name: "Yeni", dueDate: date(50_000), recurrence: .none)
            )
            XCTFail("A generated reminder ID collision must not overwrite data.")
        } catch {
            XCTAssertEqual(
                error as? HealthChecksRepositoryIntegrityError,
                .reminderIDCollision(id: collisionID)
            )
        }
    }

    func testMutationRequiresExactIDAndCurrentTimestamp() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let existingID = uuid(506)
        let missingID = uuid(507)
        let updatedAt = date(60_000)
        writer.insert(reminder(id: existingID, updatedAt: updatedAt))
        try writer.save()
        let repository = SwiftDataHealthChecksRepository(
            modelContext: ModelContext(container),
            calendar: calendar("Europe/Istanbul")
        )

        do {
            _ = try await repository.updateReminder(
                id: missingID,
                expectedUpdatedAt: updatedAt,
                input: try input(name: "Eksik", dueDate: date(61_000), recurrence: .none)
            )
            XCTFail("An exact missing ID must not mutate another reminder.")
        } catch {
            XCTAssertEqual(
                error as? HealthChecksRepositoryMutationError,
                .reminderNotFound(id: missingID)
            )
        }

        do {
            try await repository.deleteReminder(
                id: existingID,
                expectedUpdatedAt: date(59_999)
            )
            XCTFail("A stale delete must fail without changing the reminder.")
        } catch {
            XCTAssertEqual(
                error as? HealthChecksRepositoryMutationError,
                .staleReminder(
                    id: existingID,
                    expectedUpdatedAt: date(59_999),
                    actualUpdatedAt: updatedAt
                )
            )
        }
        let preservedIDs = try await repository.fetchReminders().map(\.id)
        XCTAssertEqual(preservedIDs, [existingID])
    }

    func testCompletingNoneMarksDoneWithoutGeneratingSuccessor() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let reminderID = uuid(508)
        let updatedAt = date(70_000)
        writer.insert(
            reminder(
                id: reminderID,
                updatedAt: updatedAt,
                dueDate: date(71_000),
                recurrence: .none
            )
        )
        try writer.save()
        let repository = SwiftDataHealthChecksRepository(
            modelContext: ModelContext(container),
            calendar: calendar("Europe/Istanbul"),
            now: { self.date(72_000) },
            makeID: { self.uuid(509) }
        )

        let mutation = try await repository.completeReminder(
            id: reminderID,
            expectedUpdatedAt: updatedAt
        )

        XCTAssertEqual(mutation.completed.status, .done)
        XCTAssertEqual(mutation.completed.updatedAt, date(72_000))
        XCTAssertNil(mutation.successor)
        XCTAssertEqual(
            try ModelContext(container).fetchCount(FetchDescriptor<HealthCheckReminder>()),
            1
        )
        XCTAssertEqual(
            try ModelContext(container).fetchCount(FetchDescriptor<AppSetting>()),
            0
        )
    }

    func testRecurringCompletionIsAtomicAndRetryResolvesTheOpaqueLink() async throws {
        let zoneCalendar = calendar("Europe/Istanbul")
        let dueDate = localDate(2027, 1, 31, 9, 45, calendar: zoneCalendar)
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let predecessorID = uuid(510)
        let successorID = uuid(511)
        let originalUpdatedAt = date(80_000)
        writer.insert(
            reminder(
                id: predecessorID,
                updatedAt: originalUpdatedAt,
                name: "Genel check-up",
                dueDate: dueDate,
                recurrence: .monthly
            )
        )
        try writer.save()
        let context = ModelContext(container)
        var generatedIDs = [successorID, uuid(512)]
        var saveCount = 0
        let repository = SwiftDataHealthChecksRepository(
            modelContext: context,
            calendar: zoneCalendar,
            now: { self.date(81_000) },
            makeID: { generatedIDs.removeFirst() },
            save: {
                saveCount += 1
                try context.save()
            }
        )

        let first = try await repository.completeReminder(
            id: predecessorID,
            expectedUpdatedAt: originalUpdatedAt
        )
        let retried = try await repository.completeReminder(
            id: predecessorID,
            expectedUpdatedAt: originalUpdatedAt
        )

        XCTAssertEqual(first, retried)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(first.completed.status, .done)
        let successor = try XCTUnwrap(first.successor)
        XCTAssertEqual(successor.id, successorID)
        XCTAssertEqual(successor.name, "Genel check-up")
        XCTAssertEqual(successor.status, .pending)
        XCTAssertEqual(successor.recurrence, .monthly)
        assertLocal(
            successor.dueDate,
            equals: [2027, 2, 28, 9, 45],
            calendar: zoneCalendar
        )

        let reader = ModelContext(container)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<HealthCheckReminder>()), 2)
        let links = try reader.fetch(FetchDescriptor<AppSetting>())
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.value, successorID.uuidString.lowercased())
        XCTAssertFalse(links.first?.key.contains("Genel") == true)
        XCTAssertFalse(links.first?.value.contains("Genel") == true)
    }

    func testDuplicateSuccessorLinkFailsClosedInsteadOfCreatingAnotherReminder() async throws {
        let zoneCalendar = calendar("Europe/Istanbul")
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let predecessorID = uuid(513)
        let originalUpdatedAt = date(90_000)
        writer.insert(
            reminder(
                id: predecessorID,
                updatedAt: originalUpdatedAt,
                recurrence: .monthly
            )
        )
        try writer.save()
        let repository = SwiftDataHealthChecksRepository(
            modelContext: writer,
            calendar: zoneCalendar,
            now: { self.date(91_000) },
            makeID: { self.uuid(514) }
        )
        _ = try await repository.completeReminder(
            id: predecessorID,
            expectedUpdatedAt: originalUpdatedAt
        )
        let existingLink = try XCTUnwrap(
            writer.fetch(FetchDescriptor<AppSetting>()).first
        )
        writer.insert(AppSetting(key: existingLink.key, value: existingLink.value))
        try writer.save()

        do {
            _ = try await repository.completeReminder(
                id: predecessorID,
                expectedUpdatedAt: originalUpdatedAt
            )
            XCTFail("Duplicate successor links must fail closed.")
        } catch {
            XCTAssertEqual(
                error as? HealthChecksRepositoryIntegrityError,
                .duplicateSuccessorLinks(predecessorID: predecessorID, count: 2)
            )
        }
        XCTAssertEqual(
            try writer.fetchCount(FetchDescriptor<HealthCheckReminder>()),
            2
        )
    }

    func testCompletionSaveFailureRollsBackStatusSuccessorAndLinkForExactRetry() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let reminderID = uuid(515)
        let originalUpdatedAt = date(100_000)
        context.insert(
            reminder(
                id: reminderID,
                updatedAt: originalUpdatedAt,
                recurrence: .yearly
            )
        )
        try context.save()
        var failsNextSave = true
        let repository = SwiftDataHealthChecksRepository(
            modelContext: context,
            calendar: calendar("Europe/Istanbul"),
            now: { self.date(101_000) },
            makeID: { self.uuid(516) },
            save: {
                if failsNextSave {
                    failsNextSave = false
                    throw FixtureFailure.save
                }
                try context.save()
            },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.completeReminder(
                id: reminderID,
                expectedUpdatedAt: originalUpdatedAt
            )
            XCTFail("The first completion must expose a retryable atomic failure.")
        } catch {
            XCTAssertEqual(error as? HealthChecksRepositoryOperationError, .saveFailed)
        }
        let afterFailure = ModelContext(container)
        XCTAssertEqual(
            try afterFailure.fetch(FetchDescriptor<HealthCheckReminder>()).first?.status,
            .pending
        )
        XCTAssertEqual(
            try afterFailure.fetchCount(FetchDescriptor<HealthCheckReminder>()),
            1
        )
        XCTAssertEqual(try afterFailure.fetchCount(FetchDescriptor<AppSetting>()), 0)

        let retried = try await repository.completeReminder(
            id: reminderID,
            expectedUpdatedAt: originalUpdatedAt
        )
        XCTAssertEqual(retried.completed.status, .done)
        XCTAssertEqual(retried.successor?.id, uuid(516))
    }

    func testDeleteCleansOnlyItsOwnedSuccessorMetadata() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let predecessorID = uuid(517)
        let originalUpdatedAt = date(110_000)
        context.insert(
            reminder(
                id: predecessorID,
                updatedAt: originalUpdatedAt,
                recurrence: .quarterly
            )
        )
        try context.save()
        let repository = SwiftDataHealthChecksRepository(
            modelContext: context,
            calendar: calendar("Europe/Istanbul"),
            now: { self.date(111_000) },
            makeID: { self.uuid(518) }
        )
        let completion = try await repository.completeReminder(
            id: predecessorID,
            expectedUpdatedAt: originalUpdatedAt
        )
        context.insert(AppSetting(key: "unrelated.setting", value: "keep"))
        try context.save()

        try await repository.deleteReminder(
            id: predecessorID,
            expectedUpdatedAt: completion.completed.updatedAt
        )

        let reader = ModelContext(container)
        XCTAssertEqual(
            try reader.fetch(FetchDescriptor<HealthCheckReminder>()).map(\.id),
            [uuid(518)]
        )
        let settings = try reader.fetch(FetchDescriptor<AppSetting>())
        XCTAssertEqual(settings.map(\.key), ["unrelated.setting"])
    }

    func testCreateUpdateAndDeleteFailuresRollbackWithoutCrossRecordMutation() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let existingID = uuid(519)
        let originalUpdatedAt = date(120_000)
        context.insert(
            reminder(
                id: existingID,
                updatedAt: originalUpdatedAt,
                name: "Korunacak"
            )
        )
        try context.save()
        let repository = SwiftDataHealthChecksRepository(
            modelContext: context,
            calendar: calendar("Europe/Istanbul"),
            now: { self.date(121_000) },
            makeID: { self.uuid(520) },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.createReminder(
                try input(name: "Eklenmeyecek", dueDate: date(122_000), recurrence: .none)
            )
            XCTFail("Create must roll back.")
        } catch {
            XCTAssertEqual(error as? HealthChecksRepositoryOperationError, .saveFailed)
        }
        do {
            _ = try await repository.updateReminder(
                id: existingID,
                expectedUpdatedAt: originalUpdatedAt,
                input: try input(name: "Değişmeyecek", dueDate: date(123_000), recurrence: .none)
            )
            XCTFail("Update must roll back.")
        } catch {
            XCTAssertEqual(error as? HealthChecksRepositoryOperationError, .saveFailed)
        }
        do {
            try await repository.deleteReminder(
                id: existingID,
                expectedUpdatedAt: originalUpdatedAt
            )
            XCTFail("Delete must roll back.")
        } catch {
            XCTAssertEqual(error as? HealthChecksRepositoryOperationError, .saveFailed)
        }

        let preserved = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<HealthCheckReminder>()).first
        )
        XCTAssertEqual(preserved.id, existingID)
        XCTAssertEqual(preserved.name, "Korunacak")
        XCTAssertEqual(preserved.updatedAt, originalUpdatedAt)
        XCTAssertEqual(
            try ModelContext(container).fetchCount(FetchDescriptor<HealthCheckReminder>()),
            1
        )
    }

    private func input(
        name: String,
        dueDate: Date,
        recurrence: HealthCheckRecurrence
    ) throws -> HealthCheckReminderInput {
        try HealthCheckReminderInput(
            name: name,
            dueDate: dueDate,
            recurrence: recurrence
        )
    }

    private func reminder(
        id: UUID,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 10_000),
        name: String = "Kontrol",
        dueDate: Date = Date(timeIntervalSinceReferenceDate: 11_000),
        recurrence: HealthCheckRecurrence = .none,
        status: HealthCheckStatus = .pending
    ) -> HealthCheckReminder {
        HealthCheckReminder(
            id: id,
            createdAt: date(9_000),
            updatedAt: updatedAt,
            name: name,
            dueDate: dueDate,
            recurrence: recurrence,
            status: status
        )
    }

    private func calendar(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func assertLocal(
        _ date: Date,
        equals expected: [Int],
        calendar: Calendar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        XCTAssertEqual(
            [
                components.year,
                components.month,
                components.day,
                components.hour,
                components.minute,
            ].compactMap { $0 },
            expected,
            file: file,
            line: line
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
