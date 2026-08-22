import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

@MainActor
final class QuickAddViewModelTests: XCTestCase {
    func testLoadUsesExplicitCategoryAndPublishesRankedRecipes() async throws {
        let fixture = try makeFixture()
        let second = try makeRecipe(
            id: uuid("00000000-0000-4000-8000-00000000a002"),
            name: "İkinci"
        )
        fixture.repository.recipesByCategory[fixture.category] = [
            fixture.recipe,
            second,
        ]

        await fixture.viewModel.load()

        XCTAssertEqual(fixture.viewModel.state, .recipes)
        XCTAssertEqual(fixture.viewModel.category, fixture.category)
        XCTAssertEqual(
            fixture.viewModel.recipes.map(\.id),
            [fixture.recipe.id, second.id]
        )
        XCTAssertEqual(fixture.repository.requestedCategories, [fixture.category])
        XCTAssertEqual(fixture.repository.requestedEntryDates, [fixture.day.start])
        assertEquatableSendable(fixture.viewModel.state)
    }

    func testSelectingRecipeDefaultsToOneServingAndCategoryOverrideSurvivesConfirm() async throws {
        let fixture = try makeFixture()
        await fixture.viewModel.load()
        fixture.viewModel.selectRecipe(id: fixture.recipe.id)

        XCTAssertEqual(fixture.viewModel.state, .confirmation)
        XCTAssertEqual(fixture.viewModel.quantity, 1)
        XCTAssertEqual(fixture.viewModel.selectedRecipe?.id, fixture.recipe.id)

        let override = try MealCategory(kind: .snack)
        fixture.viewModel.updateCategory(override)
        fixture.repository.createResults = [
            .success(try canonicalSnapshot(fixture: fixture, category: override)),
        ]

        await fixture.viewModel.confirm()

        XCTAssertEqual(fixture.viewModel.state, .saved)
        XCTAssertEqual(fixture.viewModel.category, override)
        XCTAssertEqual(fixture.repository.createRequests.count, 1)
        XCTAssertEqual(fixture.repository.createRequests[0].category, override)
        XCTAssertEqual(
            fixture.repository.createRequests[0].source,
            .recipe(id: fixture.recipe.id, consumedServings: 1)
        )
    }

    func testOptionalQuantityChangeDoesNotAlterTheDefaultConfirmationPath() async throws {
        let fixture = try makeFixture()
        await fixture.viewModel.load()
        fixture.viewModel.selectRecipe(id: fixture.recipe.id)

        XCTAssertEqual(fixture.viewModel.quantity, 1)
        try fixture.viewModel.updateQuantity(1.5)
        XCTAssertEqual(fixture.viewModel.quantity, 1.5)

        fixture.repository.createResults = [
            .success(try canonicalSnapshot(fixture: fixture, quantity: 1.5)),
        ]
        await fixture.viewModel.confirm()

        XCTAssertEqual(
            fixture.repository.createRequests.first?.source,
            .recipe(id: fixture.recipe.id, consumedServings: 1.5)
        )
    }

    func testConfirmPublishesOptimisticEntryAndTotalsBeforeRepositoryCompletes() async throws {
        let fixture = try makeFixture()
        fixture.repository.suspendsCreates = true
        await fixture.viewModel.load()
        fixture.viewModel.selectRecipe(id: fixture.recipe.id)

        let task = Task { await fixture.viewModel.confirm() }
        await waitUntil { fixture.repository.pendingCreateRequest != nil }

        XCTAssertEqual(fixture.viewModel.state, .saving)
        XCTAssertEqual(fixture.observer.snapshots.count, 1)
        let optimistic = try XCTUnwrap(fixture.observer.snapshots.first)
        XCTAssertEqual(optimistic.entries.count, 2)
        XCTAssertEqual(optimistic.entries.last?.id, fixture.viewModel.requestID)
        XCTAssertEqual(optimistic.entries.last?.source, .recipe(
            id: fixture.recipe.id,
            name: fixture.recipe.name
        ))
        XCTAssertEqual(optimistic.totalMacros.calories, 300)
        XCTAssertEqual(optimistic.totalMacros.proteinG, 25)

        let canonical = try canonicalSnapshot(fixture: fixture)
        fixture.repository.finishCreate(with: .success(canonical))
        await task.value

        XCTAssertEqual(fixture.viewModel.state, .saved)
        XCTAssertEqual(fixture.observer.snapshots, [optimistic, canonical])
    }

    func testDoubleConfirmWhileSavingCreatesOnlyOneRepositoryRequest() async throws {
        let fixture = try makeFixture()
        fixture.repository.suspendsCreates = true
        await fixture.viewModel.load()
        fixture.viewModel.selectRecipe(id: fixture.recipe.id)

        let first = Task { await fixture.viewModel.confirm() }
        await waitUntil { fixture.repository.pendingCreateRequest != nil }
        let second = Task { await fixture.viewModel.confirm() }
        await allowMainActorWorkToSettle()

        XCTAssertEqual(fixture.repository.createRequests.count, 1)
        XCTAssertEqual(fixture.viewModel.state, .saving)

        fixture.repository.finishCreate(
            with: .success(try canonicalSnapshot(fixture: fixture))
        )
        await second.value
        await first.value

        XCTAssertEqual(fixture.repository.createRequests.count, 1)
        XCTAssertEqual(fixture.viewModel.state, .saved)
    }

    func testFailureRollsBackExactlyAndRetryKeepsSelectionContextAndRequestID() async throws {
        let fixture = try makeFixture()
        fixture.repository.createResults = [
            .failure(QuickAddStubFailure.save),
            .success(try canonicalSnapshot(fixture: fixture)),
        ]
        await fixture.viewModel.load()
        fixture.viewModel.selectRecipe(id: fixture.recipe.id)
        let baseline = fixture.repository.baseline

        await fixture.viewModel.confirm()

        XCTAssertEqual(fixture.viewModel.state, .saveError)
        XCTAssertEqual(fixture.observer.snapshots.count, 2)
        XCTAssertEqual(fixture.observer.snapshots.last, baseline)
        XCTAssertEqual(fixture.viewModel.selectedRecipe?.id, fixture.recipe.id)
        XCTAssertEqual(fixture.viewModel.category, fixture.category)
        XCTAssertEqual(fixture.viewModel.quantity, 1)
        let failedRequestID = try XCTUnwrap(fixture.viewModel.requestID)

        fixture.viewModel.updateCategory(try MealCategory(kind: .snack))
        try fixture.viewModel.updateQuantity(2)
        XCTAssertEqual(
            fixture.viewModel.category,
            fixture.category,
            "A retry must not mutate the category behind an existing idempotency key."
        )
        XCTAssertEqual(
            fixture.viewModel.quantity,
            1,
            "A retry must not mutate the quantity behind an existing idempotency key."
        )

        await fixture.viewModel.retrySave()

        XCTAssertEqual(fixture.viewModel.state, .saved)
        XCTAssertEqual(fixture.repository.createRequests.count, 2)
        XCTAssertEqual(
            fixture.repository.createRequests.map(\.requestID),
            [failedRequestID, failedRequestID],
            "An uncertain failure must retry the same idempotency key."
        )
        XCTAssertEqual(
            fixture.repository.createRequests[0],
            fixture.repository.createRequests[1],
            "An uncertain failure must retry the exact same intent."
        )
        XCTAssertEqual(fixture.viewModel.selectedRecipe?.id, fixture.recipe.id)
    }

    func testLoadFailureAndEmptyRecipesRemainDistinctRetryableStates() async throws {
        let fixture = try makeFixture()
        fixture.repository.loadError = QuickAddStubFailure.load

        await fixture.viewModel.load()
        XCTAssertEqual(fixture.viewModel.state, .loadError)

        fixture.repository.loadError = nil
        fixture.repository.recipesByCategory[fixture.category] = []
        await fixture.viewModel.retryLoad()
        XCTAssertEqual(fixture.viewModel.state, .empty)
    }

    private func makeFixture() throws -> QuickAddFixture {
        let calendar = makeCalendar()
        let date = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 8,
                    day: 22,
                    hour: 8
                )
            )
        )
        let day = try NutritionDayKey(containing: date, calendar: calendar)
        let category = try MealCategory(kind: .breakfast)
        let recipe = try makeRecipe(
            id: uuid("00000000-0000-4000-8000-00000000a001"),
            name: "Hızlı kase"
        )
        let baselineEntry = MealEntrySnapshot(
            id: uuid("00000000-0000-4000-8000-00000000a010"),
            createdAt: day.start,
            updatedAt: day.start,
            category: category,
            source: .adhoc(name: "Mevcut öğün"),
            quantity: 1,
            resolvedMacros: try NutritionMacros(
                calories: 100,
                proteinG: 10,
                carbG: 10,
                fatG: 2
            ),
            loggedAt: day.start,
            nutritionDayID: uuid("00000000-0000-4000-8000-00000000a011")
        )
        let baseline = try NutritionDayEntriesSnapshot(
            day: day,
            log: nil,
            entries: [baselineEntry]
        )
        let repository = QuickAddRepositoryStub(
            calendar: calendar,
            baseline: baseline
        )
        repository.recipesByCategory[category] = [recipe]
        let observer = SnapshotObserver()
        let requestID = uuid("00000000-0000-4000-8000-00000000a099")
        let viewModel = NutritionQuickAddViewModel(
            repository: repository,
            day: day,
            initialCategory: category,
            makeRequestID: { requestID },
            now: { day.start.addingTimeInterval(60) },
            onSnapshotChange: { snapshot in
                observer.snapshots.append(snapshot)
            }
        )
        return QuickAddFixture(
            calendar: calendar,
            day: day,
            category: category,
            recipe: recipe,
            repository: repository,
            observer: observer,
            viewModel: viewModel
        )
    }

    private func canonicalSnapshot(
        fixture: QuickAddFixture,
        category: MealCategory? = nil,
        quantity: Decimal = 1
    ) throws -> NutritionDayEntriesSnapshot {
        let category = category ?? fixture.category
        let resolved = try fixture.recipe.resolvedMacros(consumedServings: quantity)
        let entry = MealEntrySnapshot(
            id: fixture.viewModel.requestID
                ?? uuid("00000000-0000-4000-8000-00000000a099"),
            createdAt: fixture.day.start.addingTimeInterval(60),
            updatedAt: fixture.day.start.addingTimeInterval(60),
            category: category,
            source: .recipe(id: fixture.recipe.id, name: fixture.recipe.name),
            quantity: quantity,
            resolvedMacros: resolved,
            loggedAt: fixture.day.start.addingTimeInterval(60),
            nutritionDayID: uuid("00000000-0000-4000-8000-00000000a011")
        )
        return try NutritionDayEntriesSnapshot(
            day: fixture.day,
            log: nil,
            entries: fixture.repository.baseline.entries + [entry]
        )
    }

    private func makeRecipe(id: UUID, name: String) throws -> RecipeSnapshot {
        RecipeSnapshot(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 1),
            updatedAt: Date(timeIntervalSinceReferenceDate: 1),
            name: name,
            category: try MealCategory(kind: .breakfast),
            servings: 1,
            isDirectMacros: true,
            totalMacros: try NutritionMacros(
                calories: 200,
                proteinG: 15,
                carbG: 20,
                fatG: 6
            ),
            note: nil
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
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

    private func allowMainActorWorkToSettle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}

final class NutritionQuickAddRankingTests: XCTestCase {
    func testCountRecencyNormalizedNameAndUUIDFormOneDeterministicOrdering() throws {
        let a = try recipe(
            id: uuid("00000000-0000-4000-8000-00000000b001"),
            name: "Éclair"
        )
        let b = try recipe(
            id: uuid("00000000-0000-4000-8000-00000000b002"),
            name: "eclair"
        )
        let c = try recipe(
            id: uuid("00000000-0000-4000-8000-00000000b003"),
            name: "Badem"
        )
        let d = try recipe(
            id: uuid("00000000-0000-4000-8000-00000000b004"),
            name: "Kullanılmadı"
        )
        let older = Date(timeIntervalSinceReferenceDate: 100)
        let newer = Date(timeIntervalSinceReferenceDate: 200)
        let usage = [
            RecipeUsageEvent(recipeID: a.id, loggedAt: older),
            RecipeUsageEvent(recipeID: a.id, loggedAt: newer),
            RecipeUsageEvent(recipeID: b.id, loggedAt: older),
            RecipeUsageEvent(recipeID: b.id, loggedAt: newer),
            RecipeUsageEvent(recipeID: c.id, loggedAt: newer),
        ]

        XCTAssertEqual(
            NutritionQuickAddRanking.sorted(
                recipes: [d, c, b, a],
                usage: usage
            ).map(\.id),
            [a.id, b.id, c.id, d.id]
        )
        assertEquatableSendable(usage[0])
    }

    private func recipe(id: UUID, name: String) throws -> RecipeSnapshot {
        RecipeSnapshot(
            id: id,
            createdAt: .distantPast,
            updatedAt: .distantPast,
            name: name,
            category: try MealCategory(kind: .breakfast),
            servings: 1,
            isDirectMacros: true,
            totalMacros: try NutritionMacros(
                calories: 1,
                proteinG: 1,
                carbG: 1,
                fatG: 1
            ),
            note: nil
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}

@MainActor
private struct QuickAddFixture {
    let calendar: Calendar
    let day: NutritionDayKey
    let category: MealCategory
    let recipe: RecipeSnapshot
    let repository: QuickAddRepositoryStub
    let observer: SnapshotObserver
    let viewModel: NutritionQuickAddViewModel
}

@MainActor
private final class SnapshotObserver {
    var snapshots: [NutritionDayEntriesSnapshot] = []
}

private enum QuickAddStubFailure: Error {
    case load
    case save
    case unexpected
}

@MainActor
private final class QuickAddRepositoryStub: NutritionQuickAddRepository {
    let calendar: Calendar
    var baseline: NutritionDayEntriesSnapshot
    var recipesByCategory: [MealCategory: [RecipeSnapshot]] = [:]
    var loadError: Error?
    var createResults: [Result<NutritionDayEntriesSnapshot, Error>] = []
    var suspendsCreates = false

    private(set) var requestedCategories: [MealCategory] = []
    private(set) var requestedEntryDates: [Date] = []
    private(set) var createRequests: [MealEntryCreateRequest] = []
    private var createContinuation: CheckedContinuation<
        NutritionDayEntriesSnapshot,
        Error
    >?

    var pendingCreateRequest: MealEntryCreateRequest? {
        createContinuation == nil ? nil : createRequests.last
    }

    init(calendar: Calendar, baseline: NutritionDayEntriesSnapshot) {
        self.calendar = calendar
        self.baseline = baseline
    }

    func finishCreate(
        with result: Result<NutritionDayEntriesSnapshot, Error>
    ) {
        let continuation = createContinuation
        createContinuation = nil
        continuation?.resume(with: result)
    }

    func fetchQuickAddRecipes(
        for category: MealCategory
    ) async throws -> [RecipeSnapshot] {
        requestedCategories.append(category)
        if let loadError { throw loadError }
        return recipesByCategory[category] ?? []
    }

    func fetchMealEntries(
        containing date: Date
    ) async throws -> NutritionDayEntriesSnapshot {
        requestedEntryDates.append(date)
        if let loadError { throw loadError }
        return baseline
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

    func updateMealEntry(
        id: UUID,
        update: MealEntryUpdate
    ) async throws -> NutritionDayEntriesSnapshot {
        throw QuickAddStubFailure.unexpected
    }

    func deleteMealEntry(id: UUID) async throws -> NutritionDayEntriesSnapshot {
        throw QuickAddStubFailure.unexpected
    }
}
