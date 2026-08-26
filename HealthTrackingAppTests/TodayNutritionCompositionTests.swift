@testable import HealthTrackingApp
import CoreModels
import Foundation
import NutritionKit
import TrainingKit
import XCTest

@MainActor
final class TodayNutritionCompositionTests: XCTestCase {
    func testNutritionLoadsAfterMeaningfulTodayWithoutChangingTheWorkoutDirective() async throws {
        let dependencies = try AppDependencies(environment: .uiTesting)
        try dependencies.load()
        await dependencies.todayViewModel.load()
        let trainingState = dependencies.todayViewModel.state
        guard case .content = trainingState else {
            XCTFail("The seeded Today directive must be meaningful before nutrition starts.")
            return
        }

        await dependencies.todayNutritionViewModel.load()

        XCTAssertEqual(dependencies.todayViewModel.state, trainingState)
        guard case let .empty(presentation) = dependencies.todayNutritionViewModel.state else {
            XCTFail("A valid day without meals must be an empty nutrition summary.")
            return
        }
        XCTAssertEqual(presentation.protein.consumed, 0)
        XCTAssertEqual(presentation.protein.target, 120)
        XCTAssertEqual(presentation.protein.remaining, 120)
        XCTAssertEqual(presentation.protein.clampedProgress, 0)
        XCTAssertEqual(presentation.calories.consumed, 0)
        XCTAssertNil(presentation.calories.target)
    }

    func testQuickAddSnapshotUpdatesTodayOnlyForTheInjectedLocalToday() async throws {
        let calendar = makeCalendar()
        let todayDate = makeDate(day: 22, hour: 9, calendar: calendar)
        let today = try NutritionDayKey(containing: todayDate, calendar: calendar)
        let yesterday = try NutritionDayKey(
            containing: makeDate(day: 21, hour: 9, calendar: calendar),
            calendar: calendar
        )
        let repository = TodayNutritionRepositoryStub(
            context: try context(day: today, entries: [])
        )
        let viewModel = TodayNutritionViewModel(
            repository: repository,
            calendar: calendar,
            now: { todayDate }
        )
        await viewModel.load()
        let initial = viewModel.state
        let targets = NutritionMacroTargets(
            calories: 2_000,
            proteinG: 120,
            carbG: nil,
            fatG: nil
        )
        let yesterdaySnapshot = try snapshot(
            day: yesterday,
            entries: [try entry(day: yesterday, value: 10)]
        )

        viewModel.apply(snapshot: yesterdaySnapshot, targets: targets)
        XCTAssertEqual(viewModel.state, initial)

        let todaySnapshot = try snapshot(
            day: today,
            entries: [try entry(day: today, value: 25)]
        )
        viewModel.apply(snapshot: todaySnapshot, targets: targets)

        guard case let .content(presentation) = viewModel.state else {
            XCTFail("A same-day optimistic snapshot must immediately publish Today content.")
            return
        }
        XCTAssertEqual(presentation.protein.consumed, 25)
        XCTAssertEqual(presentation.protein.target, 120)
        XCTAssertEqual(presentation.calories.consumed, 25)
        XCTAssertEqual(presentation.calories.target, 2_000)
    }

    func testCompositionExposesQuickAddAndTodayNutritionViewModelsFromOneRepository() throws {
        let dependencies = try AppDependencies(environment: .uiTesting)
        try dependencies.load()

        withExtendedLifetime(dependencies.nutritionRepository) {
            _ = dependencies.nutritionQuickAddViewModel
            _ = dependencies.todayNutritionViewModel
        }
    }

    private func context(
        day: NutritionDayKey,
        entries: [MealEntrySnapshot]
    ) throws -> NutritionQuickAddContext {
        NutritionQuickAddContext(
            daySnapshot: try snapshot(day: day, entries: entries),
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

    private func snapshot(
        day: NutritionDayKey,
        entries: [MealEntrySnapshot]
    ) throws -> NutritionDayEntriesSnapshot {
        try NutritionDayEntriesSnapshot(day: day, log: nil, entries: entries)
    }

    private func entry(day: NutritionDayKey, value: Decimal) throws -> MealEntrySnapshot {
        MealEntrySnapshot(
            id: uuid("00000000-0000-4000-8000-000000000701"),
            createdAt: day.start,
            updatedAt: day.start,
            category: try MealCategory(kind: .breakfast),
            source: .adhoc(name: "Sentetik"),
            quantity: 1,
            resolvedMacros: try NutritionMacros(
                calories: value,
                proteinG: value,
                carbG: value,
                fatG: value
            ),
            loggedAt: day.start,
            nutritionDayID: uuid("00000000-0000-4000-8000-000000000702")
        )
    }

    private func makeDate(day: Int, hour: Int, calendar: Calendar) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026,
                month: 8,
                day: day,
                hour: hour
            )
        )!
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
}

@MainActor
private final class TodayNutritionRepositoryStub: NutritionQuickAddRepository {
    let context: NutritionQuickAddContext

    init(context: NutritionQuickAddContext) {
        self.context = context
    }

    func fetchQuickAddContext(containing date: Date) async throws -> NutritionQuickAddContext {
        context
    }

    func createMealEntry(
        _ request: MealEntryCreateRequest
    ) async throws -> NutritionDayEntriesSnapshot {
        context.daySnapshot
    }
}
