import CoreModels
import SwiftData
import XCTest

final class RemainingModelRoundTripTests: XCTestCase {
    func testRemainingV1ModelsRoundTripAllFieldsRelationshipsAndSnapshots() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let timestamp = Date(timeIntervalSinceReferenceDate: 654_321)

        let bodyMetricID = UUID()
        let photoID = UUID()
        let sleepID = UUID()
        let moodID = UUID()
        let postureID = UUID()
        let healthCheckID = UUID()
        let bloodworkID = UUID()
        let foodID = UUID()
        let recipeID = UUID()
        let nutritionLogID = UUID()
        let mealEntryID = UUID()
        let orphanMealEntryID = UUID()
        let reminderID = UUID()
        let settingID = UUID()
        let opaqueAssetID = "progress-photo-asset-9D681CEF"
        let schedule = try ReminderScheduleCodec.encode(
            .weekly(weekdays: [.monday, .friday], hour: 7, minute: 15)
        )

        let bodyMetric = BodyMetric(
            id: bodyMetricID, createdAt: timestamp, updatedAt: timestamp, date: timestamp,
            type: .custom, customName: "Shoulder", value: -0.5, unit: "cm"
        )
        let photo = ProgressPhoto(
            id: photoID, createdAt: timestamp, updatedAt: timestamp, date: timestamp,
            imageRef: opaqueAssetID, pose: .side, note: "After training"
        )
        let sleep = SleepLog(
            id: sleepID, createdAt: timestamp, updatedAt: timestamp, date: timestamp,
            durationHours: 0, quality: 0, note: "Interrupted"
        )
        let mood = MoodLog(
            id: moodID, createdAt: timestamp, updatedAt: timestamp, date: timestamp,
            moodScore: 0, moodTags: ["tired", "focused"], energy: 0, note: "Long day"
        )
        let posture = PostureMetric(
            id: postureID, createdAt: timestamp, updatedAt: timestamp, date: timestamp,
            wallTestPass: false, symptomScore: 0, region: "neck", note: "No pain"
        )
        let healthCheck = HealthCheckReminder(
            id: healthCheckID, createdAt: timestamp, updatedAt: timestamp, name: "Ferritin",
            dueDate: timestamp, recurrence: .quarterly, status: .done
        )
        let bloodwork = BloodworkResult(
            id: bloodworkID, createdAt: timestamp, updatedAt: timestamp, date: timestamp,
            marker: "Ferritin", value: -1, unit: "ng/mL", note: "Reference only"
        )
        let food = Food(
            id: foodID, createdAt: timestamp, updatedAt: timestamp, name: "Yogurt", brand: "Plain",
            servingSize: 0, servingUnit: "g", caloriesPerServing: 0, proteinG: 0,
            carbG: -2, fatG: 0, fiberG: 0, source: .healthKit
        )
        let recipe = Recipe(
            id: recipeID, createdAt: timestamp, updatedAt: timestamp, name: "Breakfast bowl",
            category: try MealCategory(kind: .custom, customName: "Second breakfast"), servings: 0,
            isDirectMacros: true, caloriesTotal: 500, proteinTotalG: 30, carbTotalG: 45,
            fatTotalG: 15, note: "Snapshot source"
        )
        let nutritionLog = DailyNutritionLog(
            id: nutritionLogID, createdAt: timestamp, updatedAt: timestamp, date: timestamp
        )
        let mealEntry = MealEntry(
            id: mealEntryID, createdAt: timestamp, updatedAt: timestamp,
            category: try MealCategory(kind: .breakfast), recipeId: recipeID, foodId: foodID,
            adhocName: "Protein bowl", quantity: 0, caloriesResolved: 500, proteinResolved: 30,
            carbResolved: 45, fatResolved: 15, loggedAt: timestamp, dailyNutritionLog: nutritionLog
        )
        let orphanMealEntry = MealEntry(
            id: orphanMealEntryID, createdAt: timestamp, updatedAt: timestamp,
            category: try MealCategory(kind: .snack), recipeId: nil, foodId: nil, adhocName: nil,
            quantity: -1, caloriesResolved: -1, proteinResolved: -2, carbResolved: -3,
            fatResolved: -4, loggedAt: timestamp, dailyNutritionLog: nil
        )
        let reminder = AppReminder(
            id: reminderID, createdAt: timestamp, updatedAt: timestamp, type: .mealLog,
            schedule: schedule, message: "Log lunch", isEnabled: false
        )
        let setting = AppSetting(
            id: settingID, createdAt: timestamp, updatedAt: timestamp,
            key: "seed.catalog.version", value: "1"
        )

        context.insert(bodyMetric)
        context.insert(photo)
        context.insert(sleep)
        context.insert(mood)
        context.insert(posture)
        context.insert(healthCheck)
        context.insert(bloodwork)
        context.insert(food)
        context.insert(recipe)
        context.insert(nutritionLog)
        context.insert(mealEntry)
        context.insert(orphanMealEntry)
        context.insert(reminder)
        context.insert(setting)
        try context.save()

        recipe.caloriesTotal = 9_999
        recipe.proteinTotalG = 9_999
        recipe.carbTotalG = 9_999
        recipe.fatTotalG = 9_999
        try context.save()

        let readContext = ModelContext(container)
        let loadedBodyMetric = try XCTUnwrap(readContext.fetch(FetchDescriptor<BodyMetric>(predicate: #Predicate { $0.id == bodyMetricID })).first)
        let loadedPhoto = try XCTUnwrap(readContext.fetch(FetchDescriptor<ProgressPhoto>(predicate: #Predicate { $0.id == photoID })).first)
        let loadedSleep = try XCTUnwrap(readContext.fetch(FetchDescriptor<SleepLog>(predicate: #Predicate { $0.id == sleepID })).first)
        let loadedMood = try XCTUnwrap(readContext.fetch(FetchDescriptor<MoodLog>(predicate: #Predicate { $0.id == moodID })).first)
        let loadedPosture = try XCTUnwrap(readContext.fetch(FetchDescriptor<PostureMetric>(predicate: #Predicate { $0.id == postureID })).first)
        let loadedHealthCheck = try XCTUnwrap(readContext.fetch(FetchDescriptor<HealthCheckReminder>(predicate: #Predicate { $0.id == healthCheckID })).first)
        let loadedBloodwork = try XCTUnwrap(readContext.fetch(FetchDescriptor<BloodworkResult>(predicate: #Predicate { $0.id == bloodworkID })).first)
        let loadedFood = try XCTUnwrap(readContext.fetch(FetchDescriptor<Food>(predicate: #Predicate { $0.id == foodID })).first)
        let loadedRecipe = try XCTUnwrap(readContext.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == recipeID })).first)
        let loadedNutritionLog = try XCTUnwrap(readContext.fetch(FetchDescriptor<DailyNutritionLog>(predicate: #Predicate { $0.id == nutritionLogID })).first)
        let loadedMealEntry = try XCTUnwrap(readContext.fetch(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.id == mealEntryID })).first)
        let loadedOrphanMealEntry = try XCTUnwrap(readContext.fetch(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.id == orphanMealEntryID })).first)
        let loadedReminder = try XCTUnwrap(readContext.fetch(FetchDescriptor<AppReminder>(predicate: #Predicate { $0.id == reminderID })).first)
        let loadedSetting = try XCTUnwrap(readContext.fetch(FetchDescriptor<AppSetting>(predicate: #Predicate { $0.id == settingID })).first)

        XCTAssertEqual(loadedBodyMetric.id, bodyMetricID)
        XCTAssertEqual(loadedBodyMetric.createdAt, timestamp)
        XCTAssertEqual(loadedBodyMetric.updatedAt, timestamp)
        XCTAssertEqual(loadedBodyMetric.date, timestamp)
        XCTAssertEqual(loadedBodyMetric.type, .custom)
        XCTAssertEqual(loadedBodyMetric.customName, "Shoulder")
        XCTAssertEqual(loadedBodyMetric.value, -0.5)
        XCTAssertEqual(loadedBodyMetric.unit, "cm")

        XCTAssertEqual(loadedPhoto.id, photoID)
        XCTAssertEqual(loadedPhoto.createdAt, timestamp)
        XCTAssertEqual(loadedPhoto.updatedAt, timestamp)
        XCTAssertEqual(loadedPhoto.date, timestamp)
        XCTAssertEqual(loadedPhoto.imageRef, opaqueAssetID)
        XCTAssertEqual(loadedPhoto.pose, .side)
        XCTAssertEqual(loadedPhoto.note, "After training")

        XCTAssertEqual(loadedSleep.id, sleepID)
        XCTAssertEqual(loadedSleep.createdAt, timestamp)
        XCTAssertEqual(loadedSleep.updatedAt, timestamp)
        XCTAssertEqual(loadedSleep.date, timestamp)
        XCTAssertEqual(loadedSleep.durationHours, 0)
        XCTAssertEqual(loadedSleep.quality, 0)
        XCTAssertEqual(loadedSleep.note, "Interrupted")

        XCTAssertEqual(loadedMood.id, moodID)
        XCTAssertEqual(loadedMood.createdAt, timestamp)
        XCTAssertEqual(loadedMood.updatedAt, timestamp)
        XCTAssertEqual(loadedMood.date, timestamp)
        XCTAssertEqual(loadedMood.moodScore, 0)
        XCTAssertEqual(loadedMood.moodTags, ["tired", "focused"])
        XCTAssertEqual(loadedMood.energy, 0)
        XCTAssertEqual(loadedMood.note, "Long day")

        XCTAssertEqual(loadedPosture.id, postureID)
        XCTAssertEqual(loadedPosture.createdAt, timestamp)
        XCTAssertEqual(loadedPosture.updatedAt, timestamp)
        XCTAssertEqual(loadedPosture.date, timestamp)
        XCTAssertEqual(loadedPosture.wallTestPass, false)
        XCTAssertEqual(loadedPosture.symptomScore, 0)
        XCTAssertEqual(loadedPosture.region, "neck")
        XCTAssertEqual(loadedPosture.note, "No pain")

        XCTAssertEqual(loadedHealthCheck.id, healthCheckID)
        XCTAssertEqual(loadedHealthCheck.createdAt, timestamp)
        XCTAssertEqual(loadedHealthCheck.updatedAt, timestamp)
        XCTAssertEqual(loadedHealthCheck.name, "Ferritin")
        XCTAssertEqual(loadedHealthCheck.dueDate, timestamp)
        XCTAssertEqual(loadedHealthCheck.recurrence, .quarterly)
        XCTAssertEqual(loadedHealthCheck.status, .done)

        XCTAssertEqual(loadedBloodwork.id, bloodworkID)
        XCTAssertEqual(loadedBloodwork.createdAt, timestamp)
        XCTAssertEqual(loadedBloodwork.updatedAt, timestamp)
        XCTAssertEqual(loadedBloodwork.date, timestamp)
        XCTAssertEqual(loadedBloodwork.marker, "Ferritin")
        XCTAssertEqual(loadedBloodwork.value, -1)
        XCTAssertEqual(loadedBloodwork.unit, "ng/mL")
        XCTAssertEqual(loadedBloodwork.note, "Reference only")

        XCTAssertEqual(loadedFood.id, foodID)
        XCTAssertEqual(loadedFood.createdAt, timestamp)
        XCTAssertEqual(loadedFood.updatedAt, timestamp)
        XCTAssertEqual(loadedFood.name, "Yogurt")
        XCTAssertEqual(loadedFood.brand, "Plain")
        XCTAssertEqual(loadedFood.servingSize, 0)
        XCTAssertEqual(loadedFood.servingUnit, "g")
        XCTAssertEqual(loadedFood.caloriesPerServing, 0)
        XCTAssertEqual(loadedFood.proteinG, 0)
        XCTAssertEqual(loadedFood.carbG, -2)
        XCTAssertEqual(loadedFood.fatG, 0)
        XCTAssertEqual(loadedFood.fiberG, 0)
        XCTAssertEqual(loadedFood.source, .healthKit)

        XCTAssertEqual(loadedRecipe.id, recipeID)
        XCTAssertEqual(loadedRecipe.createdAt, timestamp)
        XCTAssertEqual(loadedRecipe.updatedAt, timestamp)
        XCTAssertEqual(loadedRecipe.name, "Breakfast bowl")
        XCTAssertEqual(loadedRecipe.category, try MealCategory(kind: .custom, customName: "Second breakfast"))
        XCTAssertEqual(loadedRecipe.servings, 0)
        XCTAssertTrue(loadedRecipe.isDirectMacros)
        XCTAssertEqual(loadedRecipe.caloriesTotal, 9_999)
        XCTAssertEqual(loadedRecipe.proteinTotalG, 9_999)
        XCTAssertEqual(loadedRecipe.carbTotalG, 9_999)
        XCTAssertEqual(loadedRecipe.fatTotalG, 9_999)
        XCTAssertEqual(loadedRecipe.note, "Snapshot source")

        XCTAssertEqual(loadedNutritionLog.id, nutritionLogID)
        XCTAssertEqual(loadedNutritionLog.createdAt, timestamp)
        XCTAssertEqual(loadedNutritionLog.updatedAt, timestamp)
        XCTAssertEqual(loadedNutritionLog.date, timestamp)
        XCTAssertEqual(loadedNutritionLog.mealEntries?.map(\.id), [mealEntryID])

        XCTAssertEqual(loadedMealEntry.id, mealEntryID)
        XCTAssertEqual(loadedMealEntry.createdAt, timestamp)
        XCTAssertEqual(loadedMealEntry.updatedAt, timestamp)
        XCTAssertEqual(loadedMealEntry.category, try MealCategory(kind: .breakfast))
        XCTAssertEqual(loadedMealEntry.recipeId, recipeID)
        XCTAssertEqual(loadedMealEntry.foodId, foodID)
        XCTAssertEqual(loadedMealEntry.adhocName, "Protein bowl")
        XCTAssertEqual(loadedMealEntry.quantity, 0)
        XCTAssertEqual(loadedMealEntry.caloriesResolved, 500)
        XCTAssertEqual(loadedMealEntry.proteinResolved, 30)
        XCTAssertEqual(loadedMealEntry.carbResolved, 45)
        XCTAssertEqual(loadedMealEntry.fatResolved, 15)
        XCTAssertEqual(loadedMealEntry.loggedAt, timestamp)
        XCTAssertEqual(loadedMealEntry.dailyNutritionLog?.id, nutritionLogID)

        XCTAssertEqual(loadedOrphanMealEntry.id, orphanMealEntryID)
        XCTAssertEqual(loadedOrphanMealEntry.createdAt, timestamp)
        XCTAssertEqual(loadedOrphanMealEntry.updatedAt, timestamp)
        XCTAssertEqual(loadedOrphanMealEntry.category, try MealCategory(kind: .snack))
        XCTAssertNil(loadedOrphanMealEntry.recipeId)
        XCTAssertNil(loadedOrphanMealEntry.foodId)
        XCTAssertNil(loadedOrphanMealEntry.adhocName)
        XCTAssertEqual(loadedOrphanMealEntry.quantity, -1)
        XCTAssertEqual(loadedOrphanMealEntry.caloriesResolved, -1)
        XCTAssertEqual(loadedOrphanMealEntry.proteinResolved, -2)
        XCTAssertEqual(loadedOrphanMealEntry.carbResolved, -3)
        XCTAssertEqual(loadedOrphanMealEntry.fatResolved, -4)
        XCTAssertEqual(loadedOrphanMealEntry.loggedAt, timestamp)
        XCTAssertNil(loadedOrphanMealEntry.dailyNutritionLog)

        XCTAssertEqual(loadedReminder.id, reminderID)
        XCTAssertEqual(loadedReminder.createdAt, timestamp)
        XCTAssertEqual(loadedReminder.updatedAt, timestamp)
        XCTAssertEqual(loadedReminder.type, .mealLog)
        XCTAssertEqual(loadedReminder.schedule, schedule)
        XCTAssertEqual(try ReminderScheduleCodec.decode(loadedReminder.schedule), .weekly(weekdays: [.monday, .friday], hour: 7, minute: 15))
        XCTAssertEqual(loadedReminder.message, "Log lunch")
        XCTAssertFalse(loadedReminder.isEnabled)

        XCTAssertEqual(loadedSetting.id, settingID)
        XCTAssertEqual(loadedSetting.createdAt, timestamp)
        XCTAssertEqual(loadedSetting.updatedAt, timestamp)
        XCTAssertEqual(loadedSetting.key, "seed.catalog.version")
        XCTAssertEqual(loadedSetting.value, "1")
    }

    func testDailyNutritionLogAllowsDuplicateRawDatesAtSchemaLevel() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let date = Date(timeIntervalSinceReferenceDate: 987_654)
        context.insert(DailyNutritionLog(date: date))
        context.insert(DailyNutritionLog(date: date))
        try context.save()

        let rows = try ModelContext(container).fetch(FetchDescriptor<DailyNutritionLog>())
        XCTAssertEqual(rows.filter { $0.date == date }.count, 2)
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
