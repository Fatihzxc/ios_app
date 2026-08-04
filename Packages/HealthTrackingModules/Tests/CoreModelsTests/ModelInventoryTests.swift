import CoreModels
import SwiftData
import XCTest

final class ModelInventoryTests: XCTestCase {
    func testV1SchemaContainsExactlyApprovedModelNames() throws {
        let container = try makeContainer()

        XCTAssertEqual(
            Set(container.schema.entities.map(\.name)),
            [
                "UserProfile", "Program", "ProgramPhase", "WorkoutDayTemplate", "ExerciseTemplate",
                "WarmupItem", "CooldownItem", "WorkoutSession", "SetLog", "ProgramState",
                "BodyMetric", "ProgressPhoto", "SleepLog", "MoodLog", "PostureMetric",
                "HealthCheckReminder", "BloodworkResult", "Food", "Recipe", "DailyNutritionLog",
                "MealEntry", "AppReminder", "AppSetting"
            ]
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: UserProfile.self, Program.self, ProgramPhase.self, WorkoutDayTemplate.self,
            ExerciseTemplate.self, WarmupItem.self, CooldownItem.self, WorkoutSession.self,
            SetLog.self, ProgramState.self, BodyMetric.self, ProgressPhoto.self, SleepLog.self,
            MoodLog.self, PostureMetric.self, HealthCheckReminder.self, BloodworkResult.self,
            Food.self, Recipe.self, DailyNutritionLog.self, MealEntry.self, AppReminder.self,
            AppSetting.self,
            configurations: configuration
        )
    }
}
