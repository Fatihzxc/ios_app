import CoreModels
import Foundation
@testable import NutritionKit
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class QuickAddRepositoryTests: XCTestCase {
    func testContextReturnsOneConsistentDayActiveRecipesTargetsAndDerivedUsageEvents() async throws {
        let calendar = makeCalendar()
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let selectedDate = makeDate(day: 22, hour: 12, calendar: calendar)
        let selectedDay = try NutritionDayKey(containing: selectedDate, calendar: calendar)
        let previousDate = makeDate(day: 21, hour: 12, calendar: calendar)
        let previousDay = try NutritionDayKey(containing: previousDate, calendar: calendar)
        let breakfast = try MealCategory(kind: .breakfast)
        let custom = try MealCategory(kind: .custom, customName: "Gece")
        let activeID = uuid("00000000-0000-4000-8000-000000000601")
        let archivedID = uuid("00000000-0000-4000-8000-000000000602")
        let customID = uuid("00000000-0000-4000-8000-000000000603")
        let active = persistedRecipe(id: activeID, name: "Yulaf", category: breakfast)
        let archived = persistedRecipe(id: archivedID, name: "Eski", category: breakfast)
        let customRecipe = persistedRecipe(id: customID, name: "Gece", category: custom)
        let selectedLog = DailyNutritionLog(
            id: uuid("00000000-0000-4000-8000-000000000611"),
            createdAt: selectedDay.start,
            updatedAt: selectedDay.start,
            date: selectedDay.start
        )
        let previousLog = DailyNutritionLog(
            id: uuid("00000000-0000-4000-8000-000000000612"),
            createdAt: previousDay.start,
            updatedAt: previousDay.start,
            date: previousDay.start
        )
        let selectedEntry = persistedEntry(
            id: uuid("00000000-0000-4000-8000-000000000621"),
            recipeID: activeID,
            category: breakfast,
            loggedAt: selectedDay.start.addingTimeInterval(100),
            log: selectedLog
        )
        let historicalEntry = persistedEntry(
            id: uuid("00000000-0000-4000-8000-000000000622"),
            recipeID: activeID,
            category: breakfast,
            loggedAt: previousDay.start.addingTimeInterval(200),
            log: previousLog
        )
        let archivedHistory = persistedEntry(
            id: uuid("00000000-0000-4000-8000-000000000623"),
            recipeID: archivedID,
            category: breakfast,
            loggedAt: previousDay.start.addingTimeInterval(300),
            log: previousLog
        )
        for model in [active, archived, customRecipe] {
            writer.insert(model)
        }
        writer.insert(selectedLog)
        writer.insert(previousLog)
        writer.insert(selectedEntry)
        writer.insert(historicalEntry)
        writer.insert(archivedHistory)
        writer.insert(
            AppSetting(
                key: RecipeArchiveCodec.settingKey,
                value: try RecipeArchiveCodec.encode([archivedID])
            )
        )
        try writer.save()
        let repository = SwiftDataNutritionRepository(
            modelContext: ModelContext(container),
            calendar: calendar,
            now: { selectedDate },
            makeID: { UUID() }
        )

        let context = try await repository.fetchQuickAddContext(containing: selectedDate)

        XCTAssertEqual(context.daySnapshot.day, selectedDay)
        XCTAssertEqual(context.daySnapshot.entries.map(\.id), [selectedEntry.id])
        XCTAssertNil(context.targets)
        XCTAssertEqual(Set(context.activeRecipes.map(\.id)), [activeID, customID])
        XCTAssertFalse(context.activeRecipes.map(\.id).contains(archivedID))
        XCTAssertEqual(
            context.usage,
            [
                RecipeUsageEvent(
                    recipeID: activeID,
                    category: breakfast,
                    loggedAt: selectedEntry.loggedAt
                ),
                RecipeUsageEvent(
                    recipeID: activeID,
                    category: breakfast,
                    loggedAt: historicalEntry.loggedAt
                ),
                RecipeUsageEvent(
                    recipeID: archivedID,
                    category: breakfast,
                    loggedAt: archivedHistory.loggedAt
                ),
            ].sorted { lhs, rhs in
                if lhs.loggedAt != rhs.loggedAt { return lhs.loggedAt > rhs.loggedAt }
                return lhs.recipeID.uuidString < rhs.recipeID.uuidString
            }
        )
    }

    private func persistedRecipe(
        id: UUID,
        name: String,
        category: MealCategory
    ) -> Recipe {
        Recipe(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            name: name,
            category: category,
            servings: 1,
            isDirectMacros: true,
            caloriesTotal: 200,
            proteinTotalG: 20,
            carbTotalG: 25,
            fatTotalG: 5,
            note: nil
        )
    }

    private func persistedEntry(
        id: UUID,
        recipeID: UUID,
        category: MealCategory,
        loggedAt: Date,
        log: DailyNutritionLog
    ) -> MealEntry {
        MealEntry(
            id: id,
            createdAt: loggedAt,
            updatedAt: loggedAt,
            category: category,
            recipeId: recipeID,
            quantity: 1,
            caloriesResolved: 200,
            proteinResolved: 20,
            carbResolved: 25,
            fatResolved: 5,
            loggedAt: loggedAt,
            dailyNutritionLog: log
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
