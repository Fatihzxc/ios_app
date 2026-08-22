import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

@MainActor
final class QuickAddViewModelTests: XCTestCase {
    func testLoadRanksExactCategoryAndAUserCategoryOverrideSurvivesSelection() async throws {
        let calendar = makeCalendar()
        let day = try makeDay(day: 22, calendar: calendar)
        let breakfast = try MealCategory(kind: .breakfast)
        let custom = try MealCategory(kind: .custom, customName: "Gece")
        let breakfastRecipe = try recipe(
            id: uuid("00000000-0000-4000-8000-000000000501"),
            name: "Kahvaltı",
            category: breakfast,
            value: 10
        )
        let customRecipe = try recipe(
            id: uuid("00000000-0000-4000-8000-000000000502"),
            name: "Gece kasesi",
            category: custom,
            value: 20
        )
        let context = try makeContext(
            day: day,
            activeRecipes: [customRecipe, breakfastRecipe],
            usage: []
        )
        let repository = QuickAddRepositoryStub(calendar: calendar)
        repository.contextsByDay[day] = .success(context)
        let requestID = uuid("00000000-0000-4000-8000-0000000005f1")
        let viewModel = NutritionQuickAddViewModel(
            repository: repository,
            calendar: calendar,
            makeID: { requestID },
            now: { day.start.addingTimeInterval(12 * 60 * 60) }
        )
        let intent = NutritionQuickAddIntent(
            id: uuid("00000000-0000-4000-8000-0000000005e1"),
            day: day,
            category: breakfast
        )

        await viewModel.begin(intent)

        XCTAssertEqual(viewModel.phase, .selecting)
        XCTAssertEqual(viewModel.recipes.map(\.id), [breakfastRecipe.id])
        XCTAssertEqual(viewModel.category, breakfast)

        viewModel.selectCategory(custom)
        XCTAssertEqual(viewModel.recipes.map(\.id), [customRecipe.id])
        viewModel.selectRecipe(id: customRecipe.id)

        XCTAssertEqual(viewModel.phase, .confirming)
        XCTAssertEqual(viewModel.category, custom)
        XCTAssertEqual(viewModel.selectedRecipe?.id, customRecipe.id)
        XCTAssertEqual(viewModel.quantity, 1)
        XCTAssertEqual(viewModel.requestID, requestID)
    }

    func testConfirmPublishesOptimisticTotalsImmediatelyThenCanonicalSnapshot() async throws {
        let calendar = makeCalendar()
        let day = try makeDay(day: 22, calendar: calendar)
        let category = try MealCategory(kind: .breakfast)
        let recipe = try recipe(
            id: uuid("00000000-0000-4000-8000-000000000511"),
            name: "Yulaf",
            category: category,
            value: 25
        )
        let context = try makeContext(day: day, activeRecipes: [recipe], usage: [])
        let repository = QuickAddRepositoryStub(calendar: calendar)
        repository.contextsByDay[day] = .success(context)
        repository.suspendsCreates = true
        let requestID = uuid("00000000-0000-4000-8000-0000000005f2")
        let now = day.start.addingTimeInterval(8 * 60 * 60)
        let viewModel = NutritionQuickAddViewModel(
            repository: repository,
            calendar: calendar,
            makeID: { requestID },
            now: { now }
        )
        await viewModel.begin(
            NutritionQuickAddIntent(
                id: uuid("00000000-0000-4000-8000-0000000005e2"),
                day: day,
                category: category
            )
        )
        viewModel.selectRecipe(id: recipe.id)
        var published: [NutritionDayEntriesSnapshot] = []

        let confirm = Task {
            await viewModel.confirm { snapshot, _ in
                published.append(snapshot)
            }
        }
        await waitUntil { repository.createRequests.count == 1 }

        XCTAssertEqual(viewModel.phase, .saving)
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(published[0].entries.map(\.id), [requestID])
        XCTAssertEqual(published[0].totalMacros, recipe.totalMacros)
        XCTAssertEqual(viewModel.projectedSnapshot, published[0])
        let request = try XCTUnwrap(repository.createRequests.first)
        XCTAssertEqual(request.requestID, requestID)
        XCTAssertEqual(request.category, category)
        guard case let .recipe(recipeID, servings) = request.source else {
            XCTFail("Quick add must persist a recipe request.")
            return
        }
        XCTAssertEqual(recipeID, recipe.id)
        XCTAssertEqual(servings, 1)

        let canonical = try makeSnapshot(
            day: day,
            entries: [try entry(
                id: requestID,
                recipe: recipe,
                category: category,
                day: day,
                loggedAt: now.addingTimeInterval(1)
            )]
        )
        repository.finishCreate(with: .success(canonical))
        await confirm.value

        XCTAssertEqual(viewModel.phase, .completed)
        XCTAssertEqual(published, [published[0], canonical])
        XCTAssertEqual(viewModel.projectedSnapshot, canonical)
    }

    func testDoubleConfirmStartsOneMutationAndKeepsTheSelectionRequestID() async throws {
        let fixture = try makeFixture(requestIDSuffix: "f3")
        fixture.repository.suspendsCreates = true
        await fixture.viewModel.begin(fixture.intent)
        fixture.viewModel.selectRecipe(id: fixture.recipe.id)
        let requestID = try XCTUnwrap(fixture.viewModel.requestID)

        let first = Task { await fixture.viewModel.confirm { _, _ in } }
        await waitUntil { fixture.repository.createRequests.count == 1 }
        await fixture.viewModel.confirm { _, _ in }

        XCTAssertEqual(fixture.repository.createRequests.count, 1)
        XCTAssertEqual(fixture.repository.createRequests.first?.requestID, requestID)
        let canonical = try makeSnapshot(
            day: fixture.day,
            entries: [try entry(
                id: requestID,
                recipe: fixture.recipe,
                category: fixture.category,
                day: fixture.day,
                loggedAt: fixture.day.start.addingTimeInterval(100)
            )]
        )
        fixture.repository.finishCreate(with: .success(canonical))
        await first.value
        XCTAssertEqual(fixture.viewModel.phase, .completed)
    }

    func testFailureRollsBackExactlyAndRetryUsesTheSameRequestIDAndContext() async throws {
        let fixture = try makeFixture(requestIDSuffix: "f4")
        let canonicalID = uuid("00000000-0000-4000-8000-0000000005f4")
        let canonical = try makeSnapshot(
            day: fixture.day,
            entries: [try entry(
                id: canonicalID,
                recipe: fixture.recipe,
                category: fixture.category,
                day: fixture.day,
                loggedAt: fixture.day.start.addingTimeInterval(200)
            )]
        )
        fixture.repository.createResults = [
            .failure(QuickAddStubFailure.save),
            .success(canonical),
        ]
        await fixture.viewModel.begin(fixture.intent)
        fixture.viewModel.selectRecipe(id: fixture.recipe.id)
        let selectionRequestID = try XCTUnwrap(fixture.viewModel.requestID)
        var published: [NutritionDayEntriesSnapshot] = []

        await fixture.viewModel.confirm { snapshot, _ in published.append(snapshot) }

        XCTAssertEqual(fixture.viewModel.phase, .saveError)
        XCTAssertEqual(published.count, 2)
        XCTAssertEqual(published[0].entries.map(\.id), [selectionRequestID])
        XCTAssertEqual(published[1], fixture.context.daySnapshot)
        XCTAssertEqual(fixture.viewModel.projectedSnapshot, fixture.context.daySnapshot)
        XCTAssertEqual(fixture.viewModel.selectedRecipe?.id, fixture.recipe.id)
        XCTAssertEqual(fixture.viewModel.category, fixture.category)
        XCTAssertEqual(fixture.viewModel.quantity, 1)
        XCTAssertEqual(fixture.viewModel.requestID, selectionRequestID)

        await fixture.viewModel.retrySave { snapshot, _ in published.append(snapshot) }

        XCTAssertEqual(fixture.repository.createRequests.map(\.requestID), [
            selectionRequestID,
            selectionRequestID,
        ])
        XCTAssertEqual(fixture.viewModel.phase, .completed)
        XCTAssertEqual(published.last, canonical)
    }

    func testOlderLoadAndConfirmCompletionsCannotOverwriteANewerIntent() async throws {
        let calendar = makeCalendar()
        let firstDay = try makeDay(day: 22, calendar: calendar)
        let secondDay = try makeDay(day: 23, calendar: calendar)
        let breakfast = try MealCategory(kind: .breakfast)
        let dinner = try MealCategory(kind: .dinner)
        let firstRecipe = try recipe(
            id: uuid("00000000-0000-4000-8000-000000000531"),
            name: "İlk",
            category: breakfast,
            value: 10
        )
        let secondRecipe = try recipe(
            id: uuid("00000000-0000-4000-8000-000000000532"),
            name: "Yeni",
            category: dinner,
            value: 20
        )
        let firstContext = try makeContext(
            day: firstDay,
            activeRecipes: [firstRecipe],
            usage: []
        )
        let secondContext = try makeContext(
            day: secondDay,
            activeRecipes: [secondRecipe],
            usage: []
        )
        let repository = QuickAddRepositoryStub(calendar: calendar)
        repository.suspendsContextLoads = true
        let viewModel = NutritionQuickAddViewModel(
            repository: repository,
            calendar: calendar,
            makeID: { self.uuid("00000000-0000-4000-8000-0000000005f5") },
            now: { firstDay.start.addingTimeInterval(8 * 60 * 60) }
        )
        let firstIntent = NutritionQuickAddIntent(
            id: uuid("00000000-0000-4000-8000-0000000005e5"),
            day: firstDay,
            category: breakfast
        )
        let secondIntent = NutritionQuickAddIntent(
            id: uuid("00000000-0000-4000-8000-0000000005e6"),
            day: secondDay,
            category: dinner
        )

        let firstLoad = Task { await viewModel.begin(firstIntent) }
        await waitUntil { repository.pendingContextDays.contains(firstDay) }
        let secondLoad = Task { await viewModel.begin(secondIntent) }
        await waitUntil { repository.pendingContextDays.contains(secondDay) }
        repository.finishContextLoad(for: secondDay, with: .success(secondContext))
        await secondLoad.value
        repository.finishContextLoad(for: firstDay, with: .success(firstContext))
        await firstLoad.value

        XCTAssertEqual(viewModel.intent, secondIntent)
        XCTAssertEqual(viewModel.category, dinner)
        XCTAssertEqual(viewModel.recipes.map(\.id), [secondRecipe.id])

        repository.suspendsContextLoads = false
        repository.suspendsCreates = true
        viewModel.selectRecipe(id: secondRecipe.id)
        var published: [NutritionDayEntriesSnapshot] = []
        let staleConfirm = Task {
            await viewModel.confirm { snapshot, _ in published.append(snapshot) }
        }
        await waitUntil { repository.createRequests.count == 1 }
        repository.contextsByDay[firstDay] = .success(firstContext)
        await viewModel.begin(firstIntent)
        let staleCanonical = try makeSnapshot(
            day: secondDay,
            entries: [try entry(
                id: uuid("00000000-0000-4000-8000-0000000005f5"),
                recipe: secondRecipe,
                category: dinner,
                day: secondDay,
                loggedAt: secondDay.start.addingTimeInterval(100)
            )]
        )
        repository.finishCreate(with: .success(staleCanonical))
        await staleConfirm.value

        XCTAssertEqual(viewModel.intent, firstIntent)
        XCTAssertEqual(viewModel.phase, .selecting)
        XCTAssertEqual(viewModel.recipes.map(\.id), [firstRecipe.id])
        XCTAssertNotEqual(published.last, staleCanonical)
    }

    private struct Fixture {
        let day: NutritionDayKey
        let category: MealCategory
        let recipe: RecipeSnapshot
        let context: NutritionQuickAddContext
        let repository: QuickAddRepositoryStub
        let viewModel: NutritionQuickAddViewModel
        let intent: NutritionQuickAddIntent
    }

    private func makeFixture(requestIDSuffix: String) throws -> Fixture {
        let calendar = makeCalendar()
        let day = try makeDay(day: 22, calendar: calendar)
        let category = try MealCategory(kind: .breakfast)
        let recipe = try recipe(
            id: uuid("00000000-0000-4000-8000-000000000521"),
            name: "Yulaf",
            category: category,
            value: 30
        )
        let context = try makeContext(day: day, activeRecipes: [recipe], usage: [])
        let repository = QuickAddRepositoryStub(calendar: calendar)
        repository.contextsByDay[day] = .success(context)
        let requestID = uuid("00000000-0000-4000-8000-0000000005\(requestIDSuffix)")
        let viewModel = NutritionQuickAddViewModel(
            repository: repository,
            calendar: calendar,
            makeID: { requestID },
            now: { day.start.addingTimeInterval(8 * 60 * 60) }
        )
        return Fixture(
            day: day,
            category: category,
            recipe: recipe,
            context: context,
            repository: repository,
            viewModel: viewModel,
            intent: NutritionQuickAddIntent(
                id: uuid("00000000-0000-4000-8000-0000000005e0"),
                day: day,
                category: category
            )
        )
    }

    private func makeContext(
        day: NutritionDayKey,
        activeRecipes: [RecipeSnapshot],
        usage: [RecipeUsageEvent]
    ) throws -> NutritionQuickAddContext {
        NutritionQuickAddContext(
            daySnapshot: try makeSnapshot(day: day, entries: []),
            targets: NutritionMacroTargets(
                calories: nil,
                proteinG: 120,
                carbG: nil,
                fatG: nil
            ),
            activeRecipes: activeRecipes,
            usage: usage
        )
    }

    private func makeSnapshot(
        day: NutritionDayKey,
        entries: [MealEntrySnapshot]
    ) throws -> NutritionDayEntriesSnapshot {
        try NutritionDayEntriesSnapshot(day: day, log: nil, entries: entries)
    }

    private func recipe(
        id: UUID,
        name: String,
        category: MealCategory,
        value: Decimal
    ) throws -> RecipeSnapshot {
        RecipeSnapshot(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            name: name,
            category: category,
            servings: 1,
            isDirectMacros: true,
            totalMacros: try NutritionMacros(
                calories: value,
                proteinG: value,
                carbG: value,
                fatG: value
            ),
            note: nil
        )
    }

    private func entry(
        id: UUID,
        recipe: RecipeSnapshot,
        category: MealCategory,
        day: NutritionDayKey,
        loggedAt: Date
    ) throws -> MealEntrySnapshot {
        MealEntrySnapshot(
            id: id,
            createdAt: loggedAt,
            updatedAt: loggedAt,
            category: category,
            source: .recipe(id: recipe.id, name: recipe.name),
            quantity: 1,
            resolvedMacros: recipe.totalMacros,
            loggedAt: loggedAt,
            nutritionDayID: uuid("00000000-0000-4000-8000-0000000005d0")
        )
    }

    private func makeDay(day: Int, calendar: Calendar) throws -> NutritionDayKey {
        let date = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 8,
                    day: day,
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

private enum QuickAddStubFailure: Error {
    case load
    case save
    case unexpected
}

@MainActor
private final class QuickAddRepositoryStub: NutritionQuickAddRepository {
    let calendar: Calendar
    var contextsByDay: [NutritionDayKey: Result<NutritionQuickAddContext, Error>] = [:]
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
        guard let result = contextsByDay[day] else { throw QuickAddStubFailure.load }
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
        guard !createResults.isEmpty else { throw QuickAddStubFailure.unexpected }
        return try createResults.removeFirst().get()
    }
}
