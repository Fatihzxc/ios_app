import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

@MainActor
final class NutritionDayViewModelTests: XCTestCase {
    func testInitialLoadSelectsInjectedLocalTodayAndPublishesDistinctEmptyState() async throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let now = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 17,
            calendar: calendar
        )
        let expectedDay = try NutritionDayKey(containing: now, calendar: calendar)
        let repository = DayRepositoryStub(calendar: calendar)
        let viewModel = NutritionDayViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertEqual(viewModel.selectedDay, expectedDay)

        await viewModel.load()

        guard case let .empty(presentation) = viewModel.state else {
            XCTFail("A successfully loaded day without entries must be empty, not loading or error.")
            return
        }
        XCTAssertEqual(presentation.day, expectedDay)
        XCTAssertEqual(presentation.totalMacros, .zero)
        XCTAssertEqual(
            presentation.sections.map(\.category.kind),
            [.breakfast, .lunch, .dinner, .snack]
        )
        XCTAssertEqual(repository.requestedEntryDays, [expectedDay])
        assertEquatableSendable(viewModel.state)
    }

    func testPreviousNextAndPickerSelectionUseInjectedCalendarAcrossDST() async throws {
        let calendar = makeCalendar(timeZoneID: "America/New_York")
        let now = makeDate(
            year: 2026,
            month: 3,
            day: 9,
            hour: 12,
            calendar: calendar
        )
        let repository = DayRepositoryStub(calendar: calendar)
        let viewModel = NutritionDayViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )
        await viewModel.load()

        await viewModel.selectPreviousDay()
        let springForwardDay = try NutritionDayKey(
            containing: makeDate(
                year: 2026,
                month: 3,
                day: 8,
                hour: 12,
                calendar: calendar
            ),
            calendar: calendar
        )
        XCTAssertEqual(viewModel.selectedDay, springForwardDay)
        XCTAssertEqual(
            springForwardDay.end.timeIntervalSince(springForwardDay.start),
            23 * 60 * 60,
            "Day navigation must not subtract a fixed 86,400 seconds."
        )

        await viewModel.selectNextDay()
        XCTAssertEqual(
            viewModel.selectedDay,
            try NutritionDayKey(containing: now, calendar: calendar)
        )

        let pickerValue = makeDate(
            year: 2026,
            month: 11,
            day: 1,
            hour: 22,
            calendar: calendar
        )
        await viewModel.selectDay(containing: pickerValue)
        let autumnDay = try NutritionDayKey(containing: pickerValue, calendar: calendar)
        XCTAssertEqual(viewModel.selectedDay, autumnDay)
        XCTAssertEqual(
            autumnDay.end.timeIntervalSince(autumnDay.start),
            25 * 60 * 60,
            "Picker selection must share the calendar-normalized day path."
        )
        XCTAssertEqual(repository.requestedEntryDays.last, autumnDay)
    }

    func testRecoverableLoadErrorRetainsSelectedDayAndRetryLoadsThatSameDay() async throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let now = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 9,
            calendar: calendar
        )
        let expectedDay = try NutritionDayKey(containing: now, calendar: calendar)
        let repository = DayRepositoryStub(calendar: calendar)
        repository.entryError = StubFailure.load
        let viewModel = NutritionDayViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )

        await viewModel.load()

        guard case let .error(context) = viewModel.state else {
            XCTFail("Repository failure must publish a recoverable day-scoped error.")
            return
        }
        XCTAssertEqual(context.day, expectedDay)

        repository.entryError = nil
        await viewModel.retry()

        guard case let .empty(presentation) = viewModel.state else {
            XCTFail("Retry must recover the same selected day.")
            return
        }
        XCTAssertEqual(presentation.day, expectedDay)
        XCTAssertEqual(repository.requestedEntryDays, [expectedDay, expectedDay])
    }

    func testOnlyLatestOverlappingDayRequestMayPublishState() async throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let now = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 9,
            calendar: calendar
        )
        let firstDate = makeDate(
            year: 2026,
            month: 8,
            day: 20,
            hour: 12,
            calendar: calendar
        )
        let secondDate = makeDate(
            year: 2026,
            month: 8,
            day: 22,
            hour: 12,
            calendar: calendar
        )
        let firstDay = try NutritionDayKey(containing: firstDate, calendar: calendar)
        let secondDay = try NutritionDayKey(containing: secondDate, calendar: calendar)
        let repository = DayRepositoryStub(calendar: calendar)
        repository.suspendsEntryLoads = true
        let viewModel = NutritionDayViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )

        let firstTask = Task { await viewModel.selectDay(containing: firstDate) }
        await waitUntil { repository.pendingEntryDays.contains(firstDay) }
        let secondTask = Task { await viewModel.selectDay(containing: secondDate) }
        await waitUntil { repository.pendingEntryDays.contains(secondDay) }

        let secondSnapshot = try makeSnapshot(
            day: secondDay,
            entries: [makeEntry(
                id: uuid("00000000-0000-4000-8000-000000000911"),
                category: MealCategory(kind: .breakfast),
                name: "Yeni gün",
                day: secondDay,
                value: 2
            )]
        )
        repository.finishEntryLoad(for: secondDay, with: .success(secondSnapshot))
        await secondTask.value

        repository.finishEntryLoad(
            for: firstDay,
            with: .success(try makeSnapshot(day: firstDay, entries: []))
        )
        await firstTask.value

        guard case let .content(presentation) = viewModel.state else {
            XCTFail("The latest request must remain visible after an older request completes.")
            return
        }
        XCTAssertEqual(viewModel.selectedDay, secondDay)
        XCTAssertEqual(presentation.day, secondDay)
        XCTAssertEqual(presentation.sections[0].entries.map(\.id), [secondSnapshot.entries[0].id])
    }

    func testPresentationKeepsFourStandardSectionsThenDeterministicCustomSections() async throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let now = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 9,
            calendar: calendar
        )
        let day = try NutritionDayKey(containing: now, calendar: calendar)
        let entries = [
            try makeEntry(
                id: uuid("00000000-0000-4000-8000-000000000921"),
                category: MealCategory(kind: .custom, customName: "Gece"),
                name: "Gece kasesi",
                day: day,
                value: 1
            ),
            try makeEntry(
                id: uuid("00000000-0000-4000-8000-000000000922"),
                category: MealCategory(kind: .lunch),
                name: "Öğle kasesi",
                day: day,
                value: 2
            ),
            try makeEntry(
                id: uuid("00000000-0000-4000-8000-000000000923"),
                category: MealCategory(kind: .custom, customName: "Antrenman sonrası"),
                name: "Shake",
                day: day,
                value: 3
            ),
        ]
        let repository = DayRepositoryStub(calendar: calendar)
        repository.snapshotsByStart[day.start] = try makeSnapshot(day: day, entries: entries)
        let viewModel = NutritionDayViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )

        await viewModel.load()

        let presentation = try contentPresentation(from: viewModel.state)
        XCTAssertEqual(
            presentation.sections.prefix(4).map(\.category.kind),
            [.breakfast, .lunch, .dinner, .snack]
        )
        XCTAssertEqual(
            presentation.sections.dropFirst(4).map(\.category.customName),
            ["Antrenman sonrası", "Gece"]
        )
        XCTAssertEqual(
            presentation.sections[1].entries.map(\.id),
            [uuid("00000000-0000-4000-8000-000000000922")]
        )
    }

    func testPresentationDerivesCategoryTotalsDayTotalAndTargetedVersusUntargetedMacros() async throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let now = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 9,
            calendar: calendar
        )
        let day = try NutritionDayKey(containing: now, calendar: calendar)
        let breakfast = try makeEntry(
            id: uuid("00000000-0000-4000-8000-000000000931"),
            category: MealCategory(kind: .breakfast),
            name: "Kahvaltı",
            day: day,
            value: 10
        )
        let dinner = try makeEntry(
            id: uuid("00000000-0000-4000-8000-000000000932"),
            category: MealCategory(kind: .dinner),
            name: "Akşam",
            day: day,
            value: 25
        )
        let repository = DayRepositoryStub(calendar: calendar)
        repository.targets = NutritionMacroTargets(
            calories: nil,
            proteinG: 120,
            carbG: nil,
            fatG: 60
        )
        repository.snapshotsByStart[day.start] = try makeSnapshot(
            day: day,
            entries: [breakfast, dinner]
        )
        let viewModel = NutritionDayViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )

        await viewModel.load()

        let presentation = try contentPresentation(from: viewModel.state)
        XCTAssertEqual(presentation.totalMacros, try macros(35))
        XCTAssertEqual(presentation.sections[0].subtotal, try macros(10))
        XCTAssertEqual(presentation.sections[2].subtotal, try macros(25))
        XCTAssertEqual(
            presentation.targets.calories,
            .total(consumed: 35),
            "A macro without a valid target must display only its total."
        )
        guard case let .targeted(consumed, target, remaining, progress) =
            presentation.targets.proteinG else {
            XCTFail("Protein must use a target/progress presentation when a target exists.")
            return
        }
        XCTAssertEqual(consumed, 35)
        XCTAssertEqual(target, 120)
        XCTAssertEqual(remaining, 85)
        XCTAssertGreaterThan(progress, 0)
        XCTAssertLessThan(progress, 1)
    }

    func testDeleteIsOptimisticThenFailureRollsBackAndRetryUsesRepositorySnapshot() async throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let now = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 9,
            calendar: calendar
        )
        let day = try NutritionDayKey(containing: now, calendar: calendar)
        let first = try makeEntry(
            id: uuid("00000000-0000-4000-8000-000000000941"),
            category: MealCategory(kind: .breakfast),
            name: "Silinecek",
            day: day,
            value: 10
        )
        let second = try makeEntry(
            id: uuid("00000000-0000-4000-8000-000000000942"),
            category: MealCategory(kind: .breakfast),
            name: "Kalacak",
            day: day,
            value: 20
        )
        let original = try makeSnapshot(day: day, entries: [first, second])
        let afterDelete = try makeSnapshot(day: day, entries: [second])
        let repository = DayRepositoryStub(calendar: calendar)
        repository.snapshotsByStart[day.start] = original
        repository.suspendsDeletes = true
        let viewModel = NutritionDayViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )
        await viewModel.load()

        let deleteTask = Task { await viewModel.deleteEntry(id: first.id) }
        await waitUntil { repository.pendingDeleteID == first.id }

        let optimistic = try contentPresentation(from: viewModel.state)
        XCTAssertEqual(optimistic.sections[0].entries.map(\.id), [second.id])
        XCTAssertEqual(optimistic.totalMacros, try macros(20))
        XCTAssertEqual(viewModel.mutationState, .deleting(entryID: first.id))

        repository.finishDelete(with: .failure(StubFailure.delete))
        await deleteTask.value

        let rolledBack = try contentPresentation(from: viewModel.state)
        XCTAssertEqual(rolledBack.sections[0].entries.map(\.id), [first.id, second.id])
        XCTAssertEqual(rolledBack.totalMacros, try macros(30))
        XCTAssertEqual(viewModel.mutationState, .deleteError(entryID: first.id))

        repository.suspendsDeletes = false
        repository.deleteResult = .success(afterDelete)
        await viewModel.retryDelete()

        let retried = try contentPresentation(from: viewModel.state)
        XCTAssertEqual(retried.sections[0].entries.map(\.id), [second.id])
        XCTAssertEqual(retried.totalMacros, try macros(20))
        XCTAssertEqual(viewModel.mutationState, .idle)
        XCTAssertEqual(repository.deletedEntryIDs, [first.id, first.id])
    }

    func testASecondDeleteIsIgnoredWhileTheFirstMutationIsInFlight() async throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let now = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 9,
            calendar: calendar
        )
        let day = try NutritionDayKey(containing: now, calendar: calendar)
        let first = try makeEntry(
            id: uuid("00000000-0000-4000-8000-000000000951"),
            category: MealCategory(kind: .breakfast),
            name: "İlk",
            day: day,
            value: 10
        )
        let second = try makeEntry(
            id: uuid("00000000-0000-4000-8000-000000000952"),
            category: MealCategory(kind: .breakfast),
            name: "İkinci",
            day: day,
            value: 20
        )
        let repository = DayRepositoryStub(calendar: calendar)
        repository.snapshotsByStart[day.start] = try makeSnapshot(
            day: day,
            entries: [first, second]
        )
        repository.suspendsDeletes = true
        let viewModel = NutritionDayViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )
        await viewModel.load()

        let firstTask = Task { await viewModel.deleteEntry(id: first.id) }
        await waitUntil { repository.pendingDeleteIDs.contains(first.id) }
        let secondTask = Task { await viewModel.deleteEntry(id: second.id) }
        await allowMainActorWorkToSettle()

        let observedDeletedEntryIDs = repository.deletedEntryIDs
        let observedMutationState = viewModel.mutationState
        let observedOptimisticEntryIDs: [UUID]?
        if case let .content(presentation) = viewModel.state {
            observedOptimisticEntryIDs = presentation.sections[0].entries.map(\.id)
        } else {
            observedOptimisticEntryIDs = nil
        }

        if repository.pendingDeleteIDs.contains(second.id) {
            repository.finishDelete(for: second.id, with: .failure(StubFailure.delete))
        }
        repository.finishDelete(for: first.id, with: .failure(StubFailure.delete))
        await secondTask.value
        await firstTask.value

        XCTAssertEqual(
            observedDeletedEntryIDs,
            [first.id],
            "Only one destructive mutation may be sent while an earlier delete is unresolved."
        )
        XCTAssertEqual(observedMutationState, .deleting(entryID: first.id))
        XCTAssertEqual(observedOptimisticEntryIDs, [second.id])
    }

    func testAnOldDeleteCompletionCannotOverwriteANewerReloadOfTheSameDay() async throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let now = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 9,
            calendar: calendar
        )
        let day = try NutritionDayKey(containing: now, calendar: calendar)
        let first = try makeEntry(
            id: uuid("00000000-0000-4000-8000-000000000961"),
            category: MealCategory(kind: .breakfast),
            name: "Silinen",
            day: day,
            value: 10
        )
        let second = try makeEntry(
            id: uuid("00000000-0000-4000-8000-000000000962"),
            category: MealCategory(kind: .breakfast),
            name: "Korunan",
            day: day,
            value: 20
        )
        let newer = try makeEntry(
            id: uuid("00000000-0000-4000-8000-000000000963"),
            category: MealCategory(kind: .breakfast),
            name: "Yeni",
            day: day,
            value: 30
        )
        let repository = DayRepositoryStub(calendar: calendar)
        repository.snapshotsByStart[day.start] = try makeSnapshot(
            day: day,
            entries: [first, second]
        )
        repository.suspendsDeletes = true
        let viewModel = NutritionDayViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )
        await viewModel.load()

        let deleteTask = Task { await viewModel.deleteEntry(id: first.id) }
        await waitUntil { repository.pendingDeleteIDs.contains(first.id) }

        repository.snapshotsByStart[day.start] = try makeSnapshot(
            day: day,
            entries: [second, newer]
        )
        await viewModel.selectNextDay()
        await viewModel.selectPreviousDay()

        let reloaded = try contentPresentation(from: viewModel.state)
        XCTAssertEqual(reloaded.sections[0].entries.map(\.id), [second.id, newer.id])

        repository.finishDelete(
            for: first.id,
            with: .success(try makeSnapshot(day: day, entries: [second]))
        )
        await deleteTask.value

        let final = try contentPresentation(from: viewModel.state)
        XCTAssertEqual(
            final.sections[0].entries.map(\.id),
            [second.id, newer.id],
            "A stale mutation response must not overwrite a newer load of the same local day."
        )
        XCTAssertEqual(viewModel.mutationState, .idle)
    }

    func testDeleteIntentCannotRepublishThePreviousDayAfterNavigationStarts() async throws {
        let calendar = makeCalendar(timeZoneID: "Europe/Istanbul")
        let now = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 9,
            calendar: calendar
        )
        let day = try NutritionDayKey(containing: now, calendar: calendar)
        let entry = try makeEntry(
            id: uuid("00000000-0000-4000-8000-000000000971"),
            category: MealCategory(kind: .breakfast),
            name: "Önceki gün",
            day: day,
            value: 10
        )
        let repository = DayRepositoryStub(calendar: calendar)
        repository.snapshotsByStart[day.start] = try makeSnapshot(
            day: day,
            entries: [entry]
        )
        let viewModel = NutritionDayViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )
        await viewModel.load()

        repository.suspendsEntryLoads = true
        let nextDay = try XCTUnwrap(viewModel.adjacentDay(by: 1))
        let navigationTask = Task { await viewModel.selectNextDay() }
        await waitUntil { repository.pendingEntryDays.contains(nextDay) }
        XCTAssertEqual(viewModel.state, .loading)

        await viewModel.deleteEntry(id: entry.id)

        XCTAssertEqual(
            repository.deletedEntryIDs,
            [],
            "A row from the previous presentation must not mutate after day loading begins."
        )
        XCTAssertEqual(
            viewModel.state,
            .loading,
            "A stale row intent must not publish previous-day content under the new date."
        )
        XCTAssertEqual(viewModel.mutationState, .idle)

        repository.finishEntryLoad(
            for: nextDay,
            with: .success(try makeSnapshot(day: nextDay, entries: []))
        )
        await navigationTask.value
    }

    private func contentPresentation(
        from state: NutritionDayViewState
    ) throws -> NutritionDayPresentation {
        guard case let .content(presentation) = state else {
            throw StubFailure.expectedContent
        }
        return presentation
    }

    private func makeSnapshot(
        day: NutritionDayKey,
        entries: [MealEntrySnapshot]
    ) throws -> NutritionDayEntriesSnapshot {
        try NutritionDayEntriesSnapshot(day: day, log: nil, entries: entries)
    }

    private func makeEntry(
        id: UUID,
        category: MealCategory,
        name: String,
        day: NutritionDayKey,
        value: Decimal
    ) throws -> MealEntrySnapshot {
        MealEntrySnapshot(
            id: id,
            createdAt: day.start.addingTimeInterval(1),
            updatedAt: day.start.addingTimeInterval(1),
            category: category,
            source: .adhoc(name: name),
            quantity: 1,
            resolvedMacros: try macros(value),
            loggedAt: day.start.addingTimeInterval(2),
            nutritionDayID: uuid("00000000-0000-4000-8000-000000000999")
        )
    }

    private func macros(_ value: Decimal) throws -> NutritionMacros {
        try NutritionMacros(
            calories: value,
            proteinG: value,
            carbG: value,
            fatG: value
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

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not reached without a timing sleep.", file: file, line: line)
    }

    private func allowMainActorWorkToSettle() async {
        for _ in 0..<100 {
            await Task.yield()
        }
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}

private enum StubFailure: Error {
    case load
    case delete
    case expectedContent
    case unexpected
}

@MainActor
private final class DayRepositoryStub: NutritionDayViewRepository {
    let calendar: Calendar
    var targets: NutritionMacroTargets?
    var snapshotsByStart: [Date: NutritionDayEntriesSnapshot] = [:]
    var entryError: Error?
    var suspendsEntryLoads = false
    var suspendsDeletes = false
    var deleteResult: Result<NutritionDayEntriesSnapshot, Error>?

    private(set) var requestedEntryDays: [NutritionDayKey] = []
    private(set) var deletedEntryIDs: [UUID] = []
    private var entryContinuations: [
        Date: CheckedContinuation<NutritionDayEntriesSnapshot, Error>
    ] = [:]
    private var deleteContinuations: [
        UUID: CheckedContinuation<NutritionDayEntriesSnapshot, Error>
    ] = [:]
    private(set) var pendingDeleteIDs: Set<UUID> = []

    var pendingDeleteID: UUID? {
        pendingDeleteIDs.first
    }

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    var pendingEntryDays: Set<NutritionDayKey> {
        Set(entryContinuations.keys.compactMap {
            try? NutritionDayKey(containing: $0, calendar: calendar)
        })
    }

    func finishEntryLoad(
        for day: NutritionDayKey,
        with result: Result<NutritionDayEntriesSnapshot, Error>
    ) {
        entryContinuations.removeValue(forKey: day.start)?.resume(with: result)
    }

    func finishDelete(with result: Result<NutritionDayEntriesSnapshot, Error>) {
        guard let id = pendingDeleteIDs.first else { return }
        finishDelete(for: id, with: result)
    }

    func finishDelete(
        for id: UUID,
        with result: Result<NutritionDayEntriesSnapshot, Error>
    ) {
        pendingDeleteIDs.remove(id)
        deleteContinuations.removeValue(forKey: id)?.resume(with: result)
    }

    func fetchNutritionTargets() async throws -> NutritionMacroTargets? {
        targets
    }

    func fetchMealEntries(
        containing date: Date
    ) async throws -> NutritionDayEntriesSnapshot {
        let day = try NutritionDayKey(containing: date, calendar: calendar)
        requestedEntryDays.append(day)
        if let entryError { throw entryError }
        if suspendsEntryLoads {
            return try await withCheckedThrowingContinuation { continuation in
                entryContinuations[day.start] = continuation
            }
        }
        return try snapshot(for: day)
    }

    func deleteMealEntry(
        id: UUID
    ) async throws -> NutritionDayEntriesSnapshot {
        deletedEntryIDs.append(id)
        if suspendsDeletes {
            pendingDeleteIDs.insert(id)
            return try await withCheckedThrowingContinuation { continuation in
                deleteContinuations[id] = continuation
            }
        }
        if let deleteResult {
            return try deleteResult.get()
        }
        throw StubFailure.unexpected
    }

    func fetchNutritionDay(containing date: Date) async throws -> NutritionDaySnapshot? {
        let day = try NutritionDayKey(containing: date, calendar: calendar)
        return snapshotsByStart[day.start]?.log
    }

    func fetchOrCreateNutritionDay(containing date: Date) async throws -> NutritionDaySnapshot {
        throw StubFailure.unexpected
    }

    func fetchNutritionDays() async throws -> [NutritionDaySnapshot] {
        snapshotsByStart.values.compactMap(\.log)
    }

    func deleteNutritionDay(id: UUID) async throws {}

    func createMealEntry(
        _ request: MealEntryCreateRequest
    ) async throws -> NutritionDayEntriesSnapshot {
        throw StubFailure.unexpected
    }

    func updateMealEntry(
        id: UUID,
        update: MealEntryUpdate
    ) async throws -> NutritionDayEntriesSnapshot {
        throw StubFailure.unexpected
    }

    private func snapshot(
        for day: NutritionDayKey
    ) throws -> NutritionDayEntriesSnapshot {
        if let snapshot = snapshotsByStart[day.start] {
            return snapshot
        }
        return try NutritionDayEntriesSnapshot(day: day, log: nil, entries: [])
    }
}
