import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

@MainActor
final class ManualEntryViewModelTests: XCTestCase {
    func testFoodModeFiltersToUserFoodsAndPersistsSelectedQuantity() async throws {
        let fixture = try makeFixture(requestIDSuffix: "a1")
        let userFood = try food(
            id: uuid("00000000-0000-4000-8000-000000000a11"),
            name: "Yoğurt",
            source: .userCreated
        )
        let seededFood = try food(
            id: uuid("00000000-0000-4000-8000-000000000a12"),
            name: "Sistem besini",
            source: .healthKit
        )
        fixture.repository.foods = [seededFood, userFood]
        let canonical = try snapshot(
            day: fixture.day,
            requestID: fixture.requestID,
            category: fixture.category,
            source: .food(id: userFood.id, name: userFood.name),
            quantity: 1.5,
            macros: userFood.macros
        )
        fixture.repository.createResults = [.success(canonical)]

        await fixture.viewModel.begin(mode: .food, intent: fixture.intent)

        XCTAssertEqual(fixture.viewModel.phase, .foodSelection)
        XCTAssertEqual(fixture.viewModel.foods.map(\.id), [userFood.id])
        fixture.viewModel.selectFood(id: userFood.id)
        try fixture.viewModel.setQuantity(1.5)
        var published: [NutritionDayEntriesSnapshot] = []
        await fixture.viewModel.saveFood { value, _ in published.append(value) }

        XCTAssertEqual(fixture.viewModel.phase, .completed)
        XCTAssertEqual(published, [canonical])
        let request = try XCTUnwrap(fixture.repository.createRequests.first)
        XCTAssertEqual(request.requestID, fixture.requestID)
        XCTAssertEqual(request.date, fixture.day.start)
        XCTAssertEqual(request.category, fixture.category)
        guard case let .food(foodID, quantity) = request.source else {
            return XCTFail("Manual food entry must persist the selected Food source.")
        }
        XCTAssertEqual(foodID, userFood.id)
        XCTAssertEqual(quantity, 1.5)
    }

    func testAdhocMacrosAreFinalConsumedTotalsAndAreNotScaledAgain() async throws {
        let fixture = try makeFixture(requestIDSuffix: "a2")
        let consumedTotals = try NutritionMacros(
            calories: 345,
            proteinG: 27,
            carbG: 31,
            fatG: 11
        )
        let canonical = try snapshot(
            day: fixture.day,
            requestID: fixture.requestID,
            category: fixture.category,
            source: .adhoc(name: "Ev yapımı tabak"),
            quantity: 2,
            macros: consumedTotals
        )
        fixture.repository.createResults = [.success(canonical)]
        await fixture.viewModel.begin(mode: .adhoc, intent: fixture.intent)
        var published: [NutritionDayEntriesSnapshot] = []

        await fixture.viewModel.saveAdhoc(
            name: " Ev yapımı tabak ",
            quantity: 2,
            resolvedMacros: consumedTotals
        ) { value, _ in
            published.append(value)
        }

        XCTAssertEqual(fixture.viewModel.phase, .completed)
        XCTAssertEqual(published, [canonical])
        let request = try XCTUnwrap(fixture.repository.createRequests.first)
        guard case let .adhoc(name, quantity, resolvedMacros) = request.source else {
            return XCTFail("Manual ad-hoc entry must preserve an ad-hoc source snapshot.")
        }
        XCTAssertEqual(name, "Ev yapımı tabak")
        XCTAssertEqual(quantity, 2)
        XCTAssertEqual(
            resolvedMacros,
            consumedTotals,
            "The entered macro values are final consumed totals, not per-quantity values."
        )
    }

    func testFailedSaveRetriesWithTheSameRequestID() async throws {
        let fixture = try makeFixture(requestIDSuffix: "a3")
        let macros = try NutritionMacros(
            calories: 200,
            proteinG: 20,
            carbG: 15,
            fatG: 6
        )
        let canonical = try snapshot(
            day: fixture.day,
            requestID: fixture.requestID,
            category: fixture.category,
            source: .adhoc(name: "Tekrar"),
            quantity: 1,
            macros: macros
        )
        fixture.repository.createResults = [
            .failure(ManualEntryStubFailure.save),
            .success(canonical),
        ]
        await fixture.viewModel.begin(mode: .adhoc, intent: fixture.intent)
        var published: [NutritionDayEntriesSnapshot] = []

        await fixture.viewModel.saveAdhoc(
            name: "Tekrar",
            quantity: 1,
            resolvedMacros: macros
        ) { value, _ in published.append(value) }

        XCTAssertEqual(fixture.viewModel.phase, .saveError)
        XCTAssertEqual(fixture.viewModel.requestID, fixture.requestID)
        await fixture.viewModel.retrySave { value, _ in published.append(value) }

        XCTAssertEqual(fixture.viewModel.phase, .completed)
        XCTAssertEqual(
            fixture.repository.createRequests.map(\.requestID),
            [fixture.requestID, fixture.requestID]
        )
        XCTAssertEqual(published, [canonical])
    }

    func testStaleLoadAndSaveCompletionsCannotOverwriteANewerIntent() async throws {
        let calendar = makeCalendar()
        let firstDay = try day(number: 22, calendar: calendar)
        let secondDay = try day(number: 23, calendar: calendar)
        let breakfast = try MealCategory(kind: .breakfast)
        let dinner = try MealCategory(kind: .dinner)
        let firstContext = try context(day: firstDay)
        let secondContext = try context(day: secondDay)
        let repository = ManualEntryRepositoryStub(calendar: calendar)
        repository.suspendsContextLoads = true
        let requestID = uuid("00000000-0000-4000-8000-000000000aa4")
        let viewModel = NutritionManualEntryViewModel(
            repository: repository,
            foodRepository: repository,
            calendar: calendar,
            makeID: { requestID }
        )
        let firstIntent = NutritionQuickAddIntent(
            id: uuid("00000000-0000-4000-8000-000000000ab1"),
            day: firstDay,
            category: breakfast
        )
        let secondIntent = NutritionQuickAddIntent(
            id: uuid("00000000-0000-4000-8000-000000000ab2"),
            day: secondDay,
            category: dinner
        )

        let firstLoad = Task { await viewModel.begin(mode: .food, intent: firstIntent) }
        await waitUntil { repository.pendingContextDays.contains(firstDay) }
        let secondLoad = Task { await viewModel.begin(mode: .adhoc, intent: secondIntent) }
        await waitUntil { repository.pendingContextDays.contains(secondDay) }
        repository.finishContextLoad(for: secondDay, with: .success(secondContext))
        await secondLoad.value
        repository.finishContextLoad(for: firstDay, with: .success(firstContext))
        await firstLoad.value

        XCTAssertEqual(viewModel.intent, secondIntent)
        XCTAssertEqual(viewModel.mode, .adhoc)
        XCTAssertEqual(viewModel.phase, .adhocEntry)

        repository.suspendsContextLoads = false
        repository.suspendsCreates = true
        repository.contextsByDay[firstDay] = .success(firstContext)
        let macros = try NutritionMacros(
            calories: 90,
            proteinG: 9,
            carbG: 8,
            fatG: 3
        )
        var published: [NutritionDayEntriesSnapshot] = []
        let staleSave = Task {
            await viewModel.saveAdhoc(
                name: "Eski istek",
                quantity: 1,
                resolvedMacros: macros
            ) { value, _ in published.append(value) }
        }
        await waitUntil { repository.createRequests.count == 1 }
        await viewModel.begin(mode: .food, intent: firstIntent)
        let staleCanonical = try snapshot(
            day: secondDay,
            requestID: requestID,
            category: dinner,
            source: .adhoc(name: "Eski istek"),
            quantity: 1,
            macros: macros
        )
        repository.finishCreate(with: .success(staleCanonical))
        await staleSave.value

        XCTAssertEqual(viewModel.intent, firstIntent)
        XCTAssertEqual(viewModel.mode, .food)
        XCTAssertEqual(viewModel.phase, .foodSelection)
        XCTAssertFalse(published.contains(staleCanonical))
    }

    private struct Fixture {
        let day: NutritionDayKey
        let category: MealCategory
        let intent: NutritionQuickAddIntent
        let requestID: UUID
        let repository: ManualEntryRepositoryStub
        let viewModel: NutritionManualEntryViewModel
    }

    private func makeFixture(requestIDSuffix: String) throws -> Fixture {
        let calendar = makeCalendar()
        let selectedDay = try day(number: 22, calendar: calendar)
        let category = try MealCategory(kind: .breakfast)
        let intent = NutritionQuickAddIntent(
            id: uuid("00000000-0000-4000-8000-000000000ae0"),
            day: selectedDay,
            category: category
        )
        let requestID = uuid("00000000-0000-4000-8000-000000000a\(requestIDSuffix)")
        let repository = ManualEntryRepositoryStub(calendar: calendar)
        repository.contextsByDay[selectedDay] = .success(try context(day: selectedDay))
        let viewModel = NutritionManualEntryViewModel(
            repository: repository,
            foodRepository: repository,
            calendar: calendar,
            makeID: { requestID }
        )
        return Fixture(
            day: selectedDay,
            category: category,
            intent: intent,
            requestID: requestID,
            repository: repository,
            viewModel: viewModel
        )
    }

    private func context(day: NutritionDayKey) throws -> NutritionQuickAddContext {
        NutritionQuickAddContext(
            daySnapshot: try NutritionDayEntriesSnapshot(day: day, log: nil, entries: []),
            targets: NutritionMacroTargets(
                calories: nil,
                proteinG: 120,
                carbG: nil,
                fatG: nil
            ),
            activeRecipes: [],
            usage: []
        )
    }

    private func food(id: UUID, name: String, source: FoodSource) throws -> FoodSnapshot {
        FoodSnapshot(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            name: name,
            brand: nil,
            servingSize: 1,
            servingUnit: "porsiyon",
            macros: try NutritionMacros(
                calories: 120,
                proteinG: 12,
                carbG: 10,
                fatG: 4
            ),
            fiberG: nil,
            source: source
        )
    }

    private func snapshot(
        day: NutritionDayKey,
        requestID: UUID,
        category: MealCategory,
        source: MealEntrySourceSnapshot,
        quantity: Decimal,
        macros: NutritionMacros
    ) throws -> NutritionDayEntriesSnapshot {
        let timestamp = day.start.addingTimeInterval(60)
        return try NutritionDayEntriesSnapshot(
            day: day,
            log: nil,
            entries: [
                MealEntrySnapshot(
                    id: requestID,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    category: category,
                    source: source,
                    quantity: quantity,
                    resolvedMacros: macros,
                    loggedAt: timestamp,
                    nutritionDayID: uuid("00000000-0000-4000-8000-000000000ad0")
                ),
            ]
        )
    }

    private func day(number: Int, calendar: Calendar) throws -> NutritionDayKey {
        let date = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 8,
                    day: number,
                    hour: 12
                )
            )
        )
        return try NutritionDayKey(containing: date, calendar: calendar)
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
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
}

private enum ManualEntryStubFailure: Error {
    case load
    case save
    case unsupported
}

@MainActor
private final class ManualEntryRepositoryStub:
    NutritionQuickAddRepository,
    FoodLibraryRepository
{
    let calendar: Calendar
    var contextsByDay: [NutritionDayKey: Result<NutritionQuickAddContext, Error>] = [:]
    var foods: [FoodSnapshot] = []
    var createResults: [Result<NutritionDayEntriesSnapshot, Error>] = []
    var suspendsContextLoads = false
    var suspendsCreates = false

    private(set) var createRequests: [MealEntryCreateRequest] = []
    private var contextContinuations: [
        NutritionDayKey: CheckedContinuation<NutritionQuickAddContext, Error>
    ] = [:]
    private var createContinuation: CheckedContinuation<NutritionDayEntriesSnapshot, Error>?

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    var pendingContextDays: Set<NutritionDayKey> {
        Set(contextContinuations.keys)
    }

    func finishContextLoad(
        for day: NutritionDayKey,
        with result: Result<NutritionQuickAddContext, Error>
    ) {
        contextContinuations.removeValue(forKey: day)?.resume(with: result)
    }

    func finishCreate(with result: Result<NutritionDayEntriesSnapshot, Error>) {
        let continuation = createContinuation
        createContinuation = nil
        continuation?.resume(with: result)
    }

    func fetchQuickAddContext(containing date: Date) async throws -> NutritionQuickAddContext {
        let day = try NutritionDayKey(containing: date, calendar: calendar)
        if suspendsContextLoads {
            return try await withCheckedThrowingContinuation { continuation in
                contextContinuations[day] = continuation
            }
        }
        guard let result = contextsByDay[day] else { throw ManualEntryStubFailure.load }
        return try result.get()
    }

    func createMealEntry(
        _ request: MealEntryCreateRequest
    ) async throws -> NutritionDayEntriesSnapshot {
        createRequests.append(request)
        if suspendsCreates {
            return try await withCheckedThrowingContinuation { continuation in
                createContinuation = continuation
            }
        }
        guard !createResults.isEmpty else { throw ManualEntryStubFailure.save }
        return try createResults.removeFirst().get()
    }

    func fetchFoods(matching query: String) async throws -> [FoodSnapshot] {
        foods
    }

    func createFood(_ input: FoodInput) async throws -> FoodSnapshot {
        throw ManualEntryStubFailure.unsupported
    }

    func updateFood(id: UUID, input: FoodInput) async throws -> FoodSnapshot {
        throw ManualEntryStubFailure.unsupported
    }

    func deleteFood(id: UUID) async throws {
        throw ManualEntryStubFailure.unsupported
    }
}
