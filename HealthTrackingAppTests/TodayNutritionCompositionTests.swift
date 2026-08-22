@testable import HealthTrackingApp
import CoreModels
import Foundation
import NutritionKit
import TrainingKit
import XCTest

@MainActor
final class TodayNutritionCompositionTests: XCTestCase {
    func testInitialAppLoadPublishesWorkoutBeforeNutritionWorkStarts() async throws {
        let dependencies = try AppDependencies(environment: .uiTesting)
        try dependencies.load()

        await dependencies.loadInitialContent()

        guard case let .content(workout) = dependencies.todayViewModel.state else {
            XCTFail("The workout directive must be meaningful before nutrition starts.")
            return
        }
        XCTAssertEqual(dependencies.todayNutritionViewModel.state, .loading)
        XCTAssertNotNil(workout.firstMeaningfulContentElapsed)
    }

    func testLoadedEmptyAndErrorNutritionNeverMutateTheWorkoutDirective() async throws {
        let dependencies = try AppDependencies(environment: .uiTesting)
        try dependencies.load()
        await dependencies.loadInitialContent()
        let workoutBeforeNutrition = dependencies.todayViewModel.state

        await dependencies.todayNutritionViewModel.load()

        guard case let .empty(emptyPresentation) =
            dependencies.todayNutritionViewModel.state else {
            XCTFail("The seeded local day must map to a distinct empty nutrition state.")
            return
        }
        XCTAssertEqual(emptyPresentation.calories.consumed, 0)
        XCTAssertEqual(emptyPresentation.protein.consumed, 0)
        XCTAssertEqual(emptyPresentation.carbs.consumed, 0)
        XCTAssertEqual(emptyPresentation.fat.consumed, 0)
        XCTAssertEqual(dependencies.todayViewModel.state, workoutBeforeNutrition)

        let calendar = makeCalendar()
        let now = try makeDate(calendar: calendar)
        let repository = TodayNutritionRepositoryStub(calendar: calendar)
        repository.error = TodayNutritionStubFailure.load
        let nutrition = TodayNutritionViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )

        await nutrition.load()

        XCTAssertEqual(nutrition.state, .error)
        XCTAssertEqual(dependencies.todayViewModel.state, workoutBeforeNutrition)
    }

    func testMapperPreservesTargetedAndUntargetedMacroSemantics() throws {
        let calendar = makeCalendar()
        let now = try makeDate(calendar: calendar)
        let day = try NutritionDayKey(containing: now, calendar: calendar)
        let snapshot = try makeSnapshot(day: day, calories: 500, protein: 40)
        let targets = NutritionMacroTargets(
            calories: nil,
            proteinG: 120,
            carbG: nil,
            fatG: 60
        )

        let presentation = TodayNutritionMapper.presentation(
            snapshot: snapshot,
            targets: targets
        )

        XCTAssertEqual(presentation.calories.consumed, 500)
        XCTAssertNil(presentation.calories.target)
        XCTAssertEqual(presentation.protein.consumed, 40)
        XCTAssertEqual(presentation.protein.target, 120)
        XCTAssertEqual(presentation.protein.remaining, 80)
        XCTAssertNil(presentation.carbs.target)
        XCTAssertEqual(presentation.fat.target, 60)
        assertEquatableSendable(presentation)
    }

    func testEmptyDayPreservesTargetedAndUntargetedMacroPresentation() async throws {
        let calendar = makeCalendar()
        let now = try makeDate(calendar: calendar)
        let repository = TodayNutritionRepositoryStub(calendar: calendar)
        repository.targets = NutritionMacroTargets(
            calories: nil,
            proteinG: 120,
            carbG: nil,
            fatG: 60
        )
        let viewModel = TodayNutritionViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )

        await viewModel.load()

        guard case let .empty(presentation) = viewModel.state else {
            XCTFail("A successful empty day must retain its macro presentation.")
            return
        }
        XCTAssertEqual(presentation.calories.consumed, 0)
        XCTAssertNil(presentation.calories.target)
        XCTAssertEqual(presentation.protein.consumed, 0)
        XCTAssertEqual(presentation.protein.target, 120)
        XCTAssertEqual(presentation.protein.remaining, 120)
        XCTAssertNil(presentation.carbs.target)
        XCTAssertEqual(presentation.fat.target, 60)
        XCTAssertEqual(presentation.fat.remaining, 60)
    }

    func testQuickAddSnapshotImmediatelyUpdatesTodayNutritionWithoutReloadingWorkout() async throws {
        let calendar = makeCalendar()
        let now = try makeDate(calendar: calendar)
        let day = try NutritionDayKey(containing: now, calendar: calendar)
        let repository = TodayNutritionRepositoryStub(calendar: calendar)
        repository.snapshot = try makeSnapshot(day: day, calories: 100, protein: 10)
        repository.targets = NutritionMacroTargets(
            calories: nil,
            proteinG: 120,
            carbG: nil,
            fatG: nil
        )
        let viewModel = TodayNutritionViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )
        await viewModel.load()

        let optimistic = try makeSnapshot(day: day, calories: 300, protein: 25)
        viewModel.apply(snapshot: optimistic)

        guard case let .content(presentation) = viewModel.state else {
            XCTFail("An optimistic non-empty snapshot must publish content immediately.")
            return
        }
        XCTAssertEqual(presentation.calories.consumed, 300)
        XCTAssertEqual(presentation.protein.consumed, 25)
        XCTAssertEqual(repository.fetchCount, 1)
    }

    func testQuickAddBeforeInitialNutritionLoadReconcilesTargetsWithoutLosingTotals() async throws {
        let calendar = makeCalendar()
        let now = try makeDate(calendar: calendar)
        let day = try NutritionDayKey(containing: now, calendar: calendar)
        let repository = TodayNutritionRepositoryStub(calendar: calendar)
        repository.targets = NutritionMacroTargets(
            calories: nil,
            proteinG: 120,
            carbG: nil,
            fatG: nil
        )
        let viewModel = TodayNutritionViewModel(
            repository: repository,
            calendar: calendar,
            now: { now }
        )
        let optimistic = try makeSnapshot(day: day, calories: 300, protein: 25)

        viewModel.apply(snapshot: optimistic)

        guard case let .content(immediate) = viewModel.state else {
            XCTFail("The optimistic Today total must publish synchronously.")
            return
        }
        XCTAssertEqual(immediate.protein.consumed, 25)
        XCTAssertNil(immediate.protein.target)
        await waitUntil { repository.targetFetchCount == 1 }
        await waitUntil {
            guard case let .content(reconciled) = viewModel.state else { return false }
            return reconciled.protein.target == 120
                && reconciled.protein.remaining == 95
        }
        XCTAssertEqual(repository.fetchCount, 0)
    }

    func testRootInitializerRequiresTodayNutritionAndQuickAddComposition() {
        withExtendedLifetime(Self.rootInitializerIsTypeChecked) {}
    }

    func testQuickAddEvidenceScenariosHaveStableLaunchValues() {
        XCTAssertEqual(
            AppUITestScenario.nutritionQuickAdd.rawValue,
            "nutrition-quick-add"
        )
        XCTAssertEqual(
            AppUITestScenario.nutritionQuickAddErrorOnce.rawValue,
            "nutrition-quick-add-error-once"
        )
    }

    private static let rootInitializerIsTypeChecked: () -> Void = {
        guard let dependencies = try? AppDependencies(environment: .uiTesting) else { return }
        _ = AppRootView(
            todayViewModel: dependencies.todayViewModel,
            todayNutritionViewModel: dependencies.todayNutritionViewModel,
            foundationViewModel: dependencies.foundationViewModel,
            phaseTransitionViewModel: dependencies.phaseTransitionViewModel,
            trainingHistoryViewModel: dependencies.trainingHistoryViewModel,
            nutritionDayViewModel: dependencies.nutritionDayViewModel,
            foodLibraryViewModel: dependencies.foodLibraryViewModel,
            recipeLibraryViewModel: dependencies.recipeLibraryViewModel,
            makeNutritionQuickAddViewModel: dependencies.makeNutritionQuickAddViewModel,
            nutritionCalendar: dependencies.nutritionCalendar,
            nutritionNow: dependencies.nutritionNow,
            makeSessionViewModel: dependencies.makeSessionViewModel,
            trainingHapticController: dependencies.trainingHapticController,
            shouldLoadFoundation: dependencies.shouldLoadFoundation,
            persistencePresentation: dependencies.persistencePresentation
        )
    }

    private func makeSnapshot(
        day: NutritionDayKey,
        calories: Decimal,
        protein: Decimal
    ) throws -> NutritionDayEntriesSnapshot {
        let entry = MealEntrySnapshot(
            id: UUID(uuidString: "00000000-0000-4000-8000-00000000c001")!,
            createdAt: day.start,
            updatedAt: day.start,
            category: try MealCategory(kind: .breakfast),
            source: .adhoc(name: "Sentetik öğün"),
            quantity: 1,
            resolvedMacros: try NutritionMacros(
                calories: calories,
                proteinG: protein,
                carbG: 20,
                fatG: 5
            ),
            loggedAt: day.start,
            nutritionDayID: UUID(
                uuidString: "00000000-0000-4000-8000-00000000c002"
            )!
        )
        return try NutritionDayEntriesSnapshot(day: day, log: nil, entries: [entry])
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func makeDate(calendar: Calendar) throws -> Date {
        try XCTUnwrap(
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

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}

private enum TodayNutritionStubFailure: Error {
    case load
    case unexpected
}

@MainActor
private final class TodayNutritionRepositoryStub: NutritionDayViewRepository {
    let calendar: Calendar
    var snapshot: NutritionDayEntriesSnapshot?
    var targets: NutritionMacroTargets?
    var error: Error?
    private(set) var fetchCount = 0
    private(set) var targetFetchCount = 0

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func fetchNutritionTargets() async throws -> NutritionMacroTargets? {
        targetFetchCount += 1
        if let error { throw error }
        return targets
    }

    func fetchMealEntries(
        containing date: Date
    ) async throws -> NutritionDayEntriesSnapshot {
        fetchCount += 1
        if let error { throw error }
        let day = try NutritionDayKey(containing: date, calendar: calendar)
        if let snapshot {
            return snapshot
        }
        return try NutritionDayEntriesSnapshot(day: day, log: nil, entries: [])
    }

    func fetchNutritionDay(containing date: Date) async throws -> NutritionDaySnapshot? {
        nil
    }

    func fetchOrCreateNutritionDay(
        containing date: Date
    ) async throws -> NutritionDaySnapshot {
        throw TodayNutritionStubFailure.unexpected
    }

    func fetchNutritionDays() async throws -> [NutritionDaySnapshot] { [] }

    func deleteNutritionDay(id: UUID) async throws {}

    func createMealEntry(
        _ request: MealEntryCreateRequest
    ) async throws -> NutritionDayEntriesSnapshot {
        throw TodayNutritionStubFailure.unexpected
    }

    func updateMealEntry(
        id: UUID,
        update: MealEntryUpdate
    ) async throws -> NutritionDayEntriesSnapshot {
        throw TodayNutritionStubFailure.unexpected
    }

    func deleteMealEntry(id: UUID) async throws -> NutritionDayEntriesSnapshot {
        throw TodayNutritionStubFailure.unexpected
    }
}
