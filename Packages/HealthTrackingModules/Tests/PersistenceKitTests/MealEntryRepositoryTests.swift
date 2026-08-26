import CoreModels
import Foundation
@testable import NutritionKit
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class MealEntryRepositoryTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testRecipeFoodAndAdhocCreatePersistDistinctSourcesAndSelectedDay() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let calendar = makeCalendar()
        let selectedDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 18,
            calendar: calendar
        )
        let eventDate = makeDate(
            year: 2026,
            month: 8,
            day: 22,
            hour: 9,
            calendar: calendar
        )
        let dayID = uuid("00000000-0000-4000-8000-000000000801")
        let recipeID = uuid("00000000-0000-4000-8000-000000000802")
        let foodID = uuid("00000000-0000-4000-8000-000000000803")
        let recipeEntryID = uuid("00000000-0000-4000-8000-000000000804")
        let foodEntryID = uuid("00000000-0000-4000-8000-000000000805")
        let adhocEntryID = uuid("00000000-0000-4000-8000-000000000806")
        let writer = ModelContext(container)
        writer.insert(
            persistedRecipe(
                id: recipeID,
                name: "Üçte Bir",
                servings: 3,
                calories: 10,
                proteinG: 20,
                carbG: 30,
                fatG: 40
            )
        )
        writer.insert(
            persistedFood(
                id: foodID,
                name: "Yoğurt",
                calories: 100,
                proteinG: 8,
                carbG: 12,
                fatG: 4
            )
        )
        try writer.save()
        let repository = makeRepository(
            container: container,
            calendar: calendar,
            now: eventDate,
            generatedID: dayID
        )

        _ = try await repository.createMealEntry(
            try request(
                id: recipeEntryID,
                date: selectedDate,
                category: MealCategory(kind: .breakfast),
                source: .recipe(id: recipeID, consumedServings: 1)
            )
        )
        _ = try await repository.createMealEntry(
            try request(
                id: foodEntryID,
                date: selectedDate,
                category: MealCategory(kind: .lunch),
                source: .food(id: foodID, quantity: decimal("2.5"))
            )
        )
        let result = try await repository.createMealEntry(
            try request(
                id: adhocEntryID,
                date: selectedDate,
                category: MealCategory(kind: .dinner),
                source: .adhoc(
                    name: "  Ev kasesi  ",
                    quantity: 2,
                    resolvedMacros: try macros(
                        calories: 275,
                        proteinG: 17,
                        carbG: 31,
                        fatG: 9
                    )
                )
            )
        )

        XCTAssertEqual(result.log?.id, dayID)
        XCTAssertEqual(result.day.start, calendar.startOfDay(for: selectedDate))
        XCTAssertFalse(result.day.contains(eventDate))
        XCTAssertEqual(
            result.entries.map(\.id),
            [recipeEntryID, foodEntryID, adhocEntryID]
        )
        XCTAssertEqual(
            result.entries.map(\.source),
            [
                .recipe(id: recipeID, name: "Üçte Bir"),
                .food(id: foodID, name: "Yoğurt"),
                .adhoc(name: "Ev kasesi"),
            ]
        )
        XCTAssertEqual(
            result.totalMacros,
            try macros(
                calories: decimal("528.333333"),
                proteinG: decimal("43.666667"),
                carbG: 71,
                fatG: decimal("32.333333")
            )
        )
        XCTAssertTrue(result.entries.allSatisfy { $0.loggedAt == eventDate })

        let rows = try ModelContext(container)
            .fetch(FetchDescriptor<MealEntry>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].recipeId, recipeID)
        XCTAssertNil(rows[0].foodId)
        XCTAssertNil(rows[0].adhocName)
        XCTAssertEqual(rows[0].quantity, 1)
        XCTAssertEqual(rows[0].caloriesResolved, 3.333333)
        XCTAssertNil(rows[1].recipeId)
        XCTAssertEqual(rows[1].foodId, foodID)
        XCTAssertNil(rows[1].adhocName)
        XCTAssertEqual(rows[1].quantity, 2.5)
        XCTAssertEqual(rows[1].caloriesResolved, 250)
        XCTAssertNil(rows[2].recipeId)
        XCTAssertNil(rows[2].foodId)
        XCTAssertEqual(rows[2].adhocName, "Ev kasesi")
        XCTAssertEqual(rows[2].quantity, 2)
        XCTAssertEqual(rows[2].caloriesResolved, 275)
        XCTAssertTrue(rows.allSatisfy { $0.dailyNutritionLog?.id == dayID })
        assertEquatableSendable(result)
    }

    func testCreateNormalizesAnExistingLogicalDayInsideTheEntryTransaction() async throws {
        let fixture = try makeFixture()
        let entryID = uuid("00000000-0000-4000-8000-000000000807")
        let originalTimestamp = Date(timeIntervalSinceReferenceDate: 7_500)
        let writer = ModelContext(fixture.container)
        writer.insert(
            DailyNutritionLog(
                id: fixture.dayID,
                createdAt: originalTimestamp,
                updatedAt: originalTimestamp,
                date: fixture.selectedDate
            )
        )
        try writer.save()

        let result = try await fixture.repository.createMealEntry(
            try request(
                id: entryID,
                date: fixture.selectedDate,
                category: MealCategory(kind: .dinner),
                source: .adhoc(
                    name: "Kase",
                    quantity: 1,
                    resolvedMacros: try macros()
                )
            )
        )

        let expectedStart = fixture.calendar.startOfDay(for: fixture.selectedDate)
        XCTAssertEqual(result.log?.id, fixture.dayID)
        XCTAssertEqual(result.log?.day.start, expectedStart)
        XCTAssertEqual(result.entries.map(\.id), [entryID])

        let reader = ModelContext(fixture.container)
        let logs = try reader.fetch(FetchDescriptor<DailyNutritionLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.date, expectedStart)
        XCTAssertEqual(logs.first?.createdAt, originalTimestamp)
        XCTAssertEqual(logs.first?.updatedAt, fixture.now)
        XCTAssertEqual(
            try reader.fetchCount(FetchDescriptor<MealEntry>()),
            1
        )
    }

    func testCreateRejectsMissingDuplicateArchivedAndUnsupportedSources() async throws {
        let recipeID = uuid("00000000-0000-4000-8000-000000000811")
        let foodID = uuid("00000000-0000-4000-8000-000000000812")

        let missingRecipe = try makeFixture()
        await assertCreateError(
            repository: missingRecipe.repository,
            source: .recipe(id: recipeID, consumedServings: 1),
            expected: MealEntryRepositoryMutationError.recipeNotFound(id: recipeID)
        )

        let duplicateRecipe = try makeFixture()
        let duplicateRecipeWriter = ModelContext(duplicateRecipe.container)
        duplicateRecipeWriter.insert(persistedRecipe(id: recipeID, name: "Bir"))
        duplicateRecipeWriter.insert(persistedRecipe(id: recipeID, name: "İki"))
        try duplicateRecipeWriter.save()
        await assertCreateError(
            repository: duplicateRecipe.repository,
            source: .recipe(id: recipeID, consumedServings: 1),
            expected: RecipeRepositoryIntegrityError.duplicateRecipeIDs(
                id: recipeID,
                count: 2
            )
        )

        let archivedRecipe = try makeFixture()
        let archivedWriter = ModelContext(archivedRecipe.container)
        archivedWriter.insert(persistedRecipe(id: recipeID, name: "Arşiv"))
        archivedWriter.insert(
            AppSetting(
                key: RecipeArchiveCodec.settingKey,
                value: try RecipeArchiveCodec.encode([recipeID])
            )
        )
        try archivedWriter.save()
        await assertCreateError(
            repository: archivedRecipe.repository,
            source: .recipe(id: recipeID, consumedServings: 1),
            expected: MealEntryRepositoryMutationError.recipeArchived(id: recipeID)
        )

        let missingFood = try makeFixture()
        await assertCreateError(
            repository: missingFood.repository,
            source: .food(id: foodID, quantity: 1),
            expected: MealEntryRepositoryMutationError.foodNotFound(id: foodID)
        )

        let duplicateFood = try makeFixture()
        let duplicateFoodWriter = ModelContext(duplicateFood.container)
        duplicateFoodWriter.insert(persistedFood(id: foodID, name: "Bir"))
        duplicateFoodWriter.insert(persistedFood(id: foodID, name: "İki"))
        try duplicateFoodWriter.save()
        await assertCreateError(
            repository: duplicateFood.repository,
            source: .food(id: foodID, quantity: 1),
            expected: FoodRepositoryIntegrityError.duplicateFoodIDs(
                id: foodID,
                count: 2
            )
        )

        let unsupportedFood = try makeFixture()
        let unsupportedWriter = ModelContext(unsupportedFood.container)
        unsupportedWriter.insert(
            persistedFood(id: foodID, name: "Health", source: .healthKit)
        )
        try unsupportedWriter.save()
        await assertCreateError(
            repository: unsupportedFood.repository,
            source: .food(id: foodID, quantity: 1),
            expected: MealEntryRepositoryMutationError.unsupportedFoodSource(
                id: foodID,
                source: .healthKit
            )
        )
    }

    func testRequestIDIsIdempotentAndConflictingReuseFailsClosed() async throws {
        let fixture = try makeFixture()
        let foodID = uuid("00000000-0000-4000-8000-000000000821")
        let requestID = uuid("00000000-0000-4000-8000-000000000822")
        let writer = ModelContext(fixture.container)
        writer.insert(persistedFood(id: foodID, name: "Besin"))
        try writer.save()
        let createRequest = try request(
            id: requestID,
            date: fixture.selectedDate,
            category: MealCategory(kind: .lunch),
            source: .food(id: foodID, quantity: 1)
        )

        let first = try await fixture.repository.createMealEntry(createRequest)
        let repeated = try await fixture.repository.createMealEntry(createRequest)

        XCTAssertEqual(first, repeated)
        let reader = ModelContext(fixture.container)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<MealEntry>()), 1)
        XCTAssertEqual(
            try reader.fetchCount(FetchDescriptor<DailyNutritionLog>()),
            1
        )

        do {
            _ = try await fixture.repository.createMealEntry(
                try request(
                    id: requestID,
                    date: fixture.selectedDate,
                    category: MealCategory(kind: .dinner),
                    source: .food(id: foodID, quantity: 2)
                )
            )
            XCTFail("Expected conflicting request ID reuse to fail.")
        } catch {
            XCTAssertEqual(
                error as? MealEntryRepositoryMutationError,
                .requestIDConflict(id: requestID)
            )
        }
        XCTAssertEqual(
            try ModelContext(fixture.container).fetchCount(
                FetchDescriptor<MealEntry>()
            ),
            1
        )
    }

    func testFetchRejectsInvalidPersistedSourceQuantityAndMacros() async throws {
        let zeroSourceID = uuid("00000000-0000-4000-8000-000000000831")
        try await assertInvalidPersistedEntry(
            MealEntry(id: zeroSourceID, quantity: 1),
            id: zeroSourceID
        )

        let multipleSourceID = uuid("00000000-0000-4000-8000-000000000832")
        try await assertInvalidPersistedEntry(
            MealEntry(
                id: multipleSourceID,
                recipeId: UUID(),
                foodId: UUID(),
                quantity: 1
            ),
            id: multipleSourceID
        )

        let invalidQuantityID = uuid("00000000-0000-4000-8000-000000000833")
        try await assertInvalidPersistedEntry(
            MealEntry(
                id: invalidQuantityID,
                adhocName: "Kase",
                quantity: 0
            ),
            id: invalidQuantityID
        )

        let invalidMacroID = uuid("00000000-0000-4000-8000-000000000834")
        try await assertInvalidPersistedEntry(
            MealEntry(
                id: invalidMacroID,
                adhocName: "Kase",
                quantity: 1,
                proteinResolved: -1
            ),
            id: invalidMacroID
        )
    }

    func testMissingDayFetchIsEmptyWithoutCreatingPersistence() async throws {
        let fixture = try makeFixture()
        assertNutritionRepository(fixture.repository)

        let result = try await fixture.repository.fetchMealEntries(
            containing: fixture.selectedDate
        )

        XCTAssertNil(result.log)
        XCTAssertEqual(
            result.day,
            try NutritionDayKey(
                containing: fixture.selectedDate,
                calendar: fixture.calendar
            )
        )
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.totalMacros, .zero)
        XCTAssertEqual(
            try ModelContext(fixture.container).fetchCount(
                FetchDescriptor<DailyNutritionLog>()
            ),
            0
        )
    }

    func testUpdateRejectsInvalidStoredQuantityBeforeMutation() async throws {
        let fixture = try makeFixture()
        let entryID = uuid("00000000-0000-4000-8000-000000000835")
        let day = DailyNutritionLog(
            id: fixture.dayID,
            date: fixture.calendar.startOfDay(for: fixture.selectedDate)
        )
        let invalid = persistedEntry(
            id: entryID,
            name: "Bozuk",
            quantity: 0,
            day: day
        )
        let writer = ModelContext(fixture.container)
        writer.insert(day)
        writer.insert(invalid)
        try writer.save()

        do {
            _ = try await fixture.repository.updateMealEntry(
                id: entryID,
                update: try MealEntryUpdate(
                    category: MealCategory(kind: .lunch),
                    quantity: 2
                )
            )
            XCTFail("Expected invalid stored quantity failure.")
        } catch {
            XCTAssertEqual(
                error as? MealEntryRepositoryIntegrityError,
                .invalidPersistedMealEntry(id: entryID)
            )
        }
        let stored = try XCTUnwrap(
            ModelContext(fixture.container).fetch(FetchDescriptor<MealEntry>()).first
        )
        XCTAssertEqual(stored.quantity, 0)
        XCTAssertEqual(stored.category.kind, .breakfast)
    }

    func testUpdateRescalesStoredSnapshotWithoutRereadingChangedRecipe() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let calendar = makeCalendar()
        let dayID = uuid("00000000-0000-4000-8000-000000000841")
        let recipeID = uuid("00000000-0000-4000-8000-000000000842")
        let entryID = uuid("00000000-0000-4000-8000-000000000843")
        let createdAt = Date(timeIntervalSinceReferenceDate: 8_000)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 9_000)
        let categoryUpdatedAt = Date(timeIntervalSinceReferenceDate: 10_000)
        var timestamp = createdAt
        let writer = ModelContext(container)
        writer.insert(
            persistedRecipe(
                id: recipeID,
                name: "İlk tarif",
                servings: 2,
                calories: 400,
                proteinG: 30,
                carbG: 40,
                fatG: 12
            )
        )
        try writer.save()
        let repository = SwiftDataNutritionRepository(
            modelContext: ModelContext(container),
            calendar: calendar,
            now: { timestamp },
            makeID: { dayID }
        )
        let selectedDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 15,
            calendar: calendar
        )
        let created = try await repository.createMealEntry(
            try request(
                id: entryID,
                date: selectedDate,
                category: MealCategory(kind: .dinner),
                source: .recipe(id: recipeID, consumedServings: 1)
            )
        )
        let original = try XCTUnwrap(created.entries.first)
        XCTAssertEqual(
            original.resolvedMacros,
            try macros(calories: 200, proteinG: 15, carbG: 20, fatG: 6)
        )

        let sourceWriter = ModelContext(container)
        let storedRecipe = try XCTUnwrap(
            sourceWriter.fetch(FetchDescriptor<Recipe>()).first
        )
        storedRecipe.name = "Değişen tarif"
        storedRecipe.caloriesTotal = 9_999
        storedRecipe.proteinTotalG = 9_999
        try sourceWriter.save()

        timestamp = updatedAt
        let quantityResult = try await repository.updateMealEntry(
            id: entryID,
            update: try MealEntryUpdate(
                category: MealCategory(kind: .lunch),
                quantity: decimal("1.5")
            )
        )
        let quantityUpdated = try XCTUnwrap(quantityResult.entries.first)
        XCTAssertEqual(quantityUpdated.id, original.id)
        XCTAssertEqual(quantityUpdated.createdAt, original.createdAt)
        XCTAssertEqual(quantityUpdated.loggedAt, original.loggedAt)
        XCTAssertEqual(quantityUpdated.updatedAt, updatedAt)
        XCTAssertEqual(quantityUpdated.category.kind, .lunch)
        XCTAssertEqual(quantityUpdated.quantity, decimal("1.5"))
        XCTAssertEqual(
            quantityUpdated.resolvedMacros,
            try macros(calories: 300, proteinG: 22.5, carbG: 30, fatG: 9)
        )

        timestamp = categoryUpdatedAt
        let categoryResult = try await repository.updateMealEntry(
            id: entryID,
            update: try MealEntryUpdate(
                category: MealCategory(kind: .snack),
                quantity: decimal("1.5")
            )
        )
        let categoryUpdated = try XCTUnwrap(categoryResult.entries.first)
        XCTAssertEqual(
            categoryUpdated.resolvedMacros,
            quantityUpdated.resolvedMacros
        )
        XCTAssertEqual(categoryUpdated.category.kind, .snack)
        XCTAssertEqual(categoryUpdated.updatedAt, categoryUpdatedAt)
    }

    func testArchivedRecipeAndDeletedFoodKeepHistoricalSnapshotsReadable() async throws {
        let fixture = try makeFixture()
        let recipeID = uuid("00000000-0000-4000-8000-000000000851")
        let foodID = uuid("00000000-0000-4000-8000-000000000852")
        let recipeEntryID = uuid("00000000-0000-4000-8000-000000000853")
        let foodEntryID = uuid("00000000-0000-4000-8000-000000000854")
        let writer = ModelContext(fixture.container)
        writer.insert(persistedRecipe(id: recipeID, name: "Korunan tarif"))
        writer.insert(persistedFood(id: foodID, name: "Silinen besin"))
        try writer.save()
        _ = try await fixture.repository.createMealEntry(
            try request(
                id: recipeEntryID,
                date: fixture.selectedDate,
                category: MealCategory(kind: .dinner),
                source: .recipe(id: recipeID, consumedServings: 1)
            )
        )
        _ = try await fixture.repository.createMealEntry(
            try request(
                id: foodEntryID,
                date: fixture.selectedDate,
                category: MealCategory(kind: .snack),
                source: .food(id: foodID, quantity: 1)
            )
        )
        let before = try await fixture.repository.fetchMealEntries(
            containing: fixture.selectedDate
        )

        let removal = try await fixture.repository.removeRecipe(id: recipeID)
        XCTAssertEqual(removal, .archived)
        try await fixture.repository.deleteFood(id: foodID)
        let after = try await fixture.repository.fetchMealEntries(
            containing: fixture.selectedDate
        )

        XCTAssertEqual(after.entries.map(\.id), before.entries.map(\.id))
        XCTAssertEqual(
            after.entries.map(\.resolvedMacros),
            before.entries.map(\.resolvedMacros)
        )
        XCTAssertEqual(after.totalMacros, before.totalMacros)
        XCTAssertEqual(
            after.entries.map(\.source),
            [
                .recipe(id: recipeID, name: "Korunan tarif"),
                .food(id: foodID, name: nil),
            ]
        )
    }

    func testFetchOrderingDeleteTotalsAndEmptyDayRetentionAreDeterministic() async throws {
        let fixture = try makeFixture()
        let firstID = uuid("00000000-0000-4000-8000-000000000861")
        let secondID = uuid("00000000-0000-4000-8000-000000000862")
        let thirdID = uuid("00000000-0000-4000-8000-000000000863")
        let day = DailyNutritionLog(
            id: fixture.dayID,
            createdAt: fixture.now,
            updatedAt: fixture.now,
            date: fixture.calendar.startOfDay(for: fixture.selectedDate)
        )
        let first = persistedEntry(
            id: firstID,
            name: "Bir",
            quantity: 1,
            calories: 100,
            createdAt: fixture.now,
            loggedAt: fixture.now,
            day: day
        )
        let second = persistedEntry(
            id: secondID,
            name: "İki",
            quantity: 1,
            calories: 200,
            createdAt: fixture.now,
            loggedAt: fixture.now,
            day: day
        )
        let third = persistedEntry(
            id: thirdID,
            name: "Üç",
            quantity: 1,
            calories: 300,
            createdAt: fixture.now.addingTimeInterval(10),
            loggedAt: fixture.now.addingTimeInterval(-10),
            day: day
        )
        let writer = ModelContext(fixture.container)
        writer.insert(day)
        writer.insert(second)
        writer.insert(first)
        writer.insert(third)
        try writer.save()

        var result = try await fixture.repository.fetchMealEntries(
            containing: fixture.selectedDate
        )
        XCTAssertEqual(result.entries.map(\.id), [thirdID, firstID, secondID])
        XCTAssertEqual(result.totalMacros.calories, 600)

        result = try await fixture.repository.deleteMealEntry(id: thirdID)
        XCTAssertEqual(result.entries.map(\.id), [firstID, secondID])
        XCTAssertEqual(result.totalMacros.calories, 300)
        _ = try await fixture.repository.deleteMealEntry(id: firstID)
        result = try await fixture.repository.deleteMealEntry(id: secondID)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.totalMacros, .zero)
        XCTAssertEqual(
            try ModelContext(fixture.container).fetchCount(
                FetchDescriptor<DailyNutritionLog>()
            ),
            1,
            "Deleting the last entry must retain the empty day log."
        )
    }

    func testCreateUpdateAndDeleteSaveFailuresRollbackAtomically() async throws {
        let calendar = makeCalendar()
        let selectedDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 12,
            calendar: calendar
        )
        let dayID = uuid("00000000-0000-4000-8000-000000000871")
        let entryID = uuid("00000000-0000-4000-8000-000000000872")
        let createContainer = try ModelContainerFactory.make(for: .inMemory)
        let createContext = ModelContext(createContainer)
        let createRepository = failingRepository(
            context: createContext,
            calendar: calendar,
            generatedID: dayID
        )
        do {
            _ = try await createRepository.createMealEntry(
                try request(
                    id: entryID,
                    date: selectedDate,
                    category: MealCategory(kind: .dinner),
                    source: .adhoc(
                        name: "Kase",
                        quantity: 1,
                        resolvedMacros: try macros()
                    )
                )
            )
            XCTFail("Expected create save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .saveFailed)
        }
        let createReader = ModelContext(createContainer)
        XCTAssertEqual(
            try createReader.fetchCount(FetchDescriptor<DailyNutritionLog>()),
            0
        )
        XCTAssertEqual(try createReader.fetchCount(FetchDescriptor<MealEntry>()), 0)

        let mutationContainer = try ModelContainerFactory.make(for: .inMemory)
        let mutationWriter = ModelContext(mutationContainer)
        let originalUpdatedAt = Date(timeIntervalSinceReferenceDate: 10_000)
        let day = DailyNutritionLog(
            id: dayID,
            createdAt: originalUpdatedAt,
            updatedAt: originalUpdatedAt,
            date: calendar.startOfDay(for: selectedDate)
        )
        mutationWriter.insert(day)
        mutationWriter.insert(
            persistedEntry(
                id: entryID,
                name: "Korunan",
                quantity: 1,
                calories: 100,
                createdAt: originalUpdatedAt,
                loggedAt: originalUpdatedAt,
                day: day
            )
        )
        try mutationWriter.save()
        let mutationContext = ModelContext(mutationContainer)
        let mutationRepository = failingRepository(
            context: mutationContext,
            calendar: calendar,
            generatedID: UUID()
        )
        do {
            _ = try await mutationRepository.updateMealEntry(
                id: entryID,
                update: try MealEntryUpdate(
                    category: MealCategory(kind: .lunch),
                    quantity: 2
                )
            )
            XCTFail("Expected update save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .saveFailed)
        }
        var stored = try XCTUnwrap(
            ModelContext(mutationContainer).fetch(FetchDescriptor<MealEntry>()).first
        )
        XCTAssertEqual(stored.category.kind, .breakfast)
        XCTAssertEqual(stored.quantity, 1)
        XCTAssertEqual(stored.caloriesResolved, 100)
        XCTAssertEqual(stored.updatedAt, originalUpdatedAt)

        do {
            _ = try await mutationRepository.deleteMealEntry(id: entryID)
            XCTFail("Expected delete save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .deleteFailed)
        }
        stored = try XCTUnwrap(
            ModelContext(mutationContainer).fetch(FetchDescriptor<MealEntry>()).first
        )
        XCTAssertEqual(stored.id, entryID)
        XCTAssertEqual(
            try ModelContext(mutationContainer).fetchCount(
                FetchDescriptor<DailyNutritionLog>()
            ),
            1
        )
    }

    func testDuplicateDaysEntryIDsAndMissingMutationsFailClosed() async throws {
        let fixture = try makeFixture()
        let duplicateDayWriter = ModelContext(fixture.container)
        let firstDayID = uuid("00000000-0000-4000-8000-000000000881")
        let secondDayID = uuid("00000000-0000-4000-8000-000000000882")
        duplicateDayWriter.insert(
            DailyNutritionLog(id: firstDayID, date: fixture.selectedDate)
        )
        duplicateDayWriter.insert(
            DailyNutritionLog(
                id: secondDayID,
                date: fixture.selectedDate.addingTimeInterval(60)
            )
        )
        try duplicateDayWriter.save()
        let day = try NutritionDayKey(
            containing: fixture.selectedDate,
            calendar: fixture.calendar
        )
        do {
            _ = try await fixture.repository.createMealEntry(
                try request(
                    id: UUID(),
                    date: fixture.selectedDate,
                    category: MealCategory(kind: .dinner),
                    source: .adhoc(
                        name: "Kase",
                        quantity: 1,
                        resolvedMacros: try macros()
                    )
                )
            )
            XCTFail("Expected duplicate day failure.")
        } catch {
            XCTAssertEqual(
                error as? NutritionRepositoryIntegrityError,
                .duplicateNutritionDays(
                    dayStart: day.start,
                    ids: [firstDayID, secondDayID]
                )
            )
        }

        let duplicateContainer = try ModelContainerFactory.make(for: .inMemory)
        let duplicateID = uuid("00000000-0000-4000-8000-000000000883")
        let duplicateDay = DailyNutritionLog(
            id: fixture.dayID,
            date: fixture.calendar.startOfDay(for: fixture.selectedDate)
        )
        let duplicateWriter = ModelContext(duplicateContainer)
        duplicateWriter.insert(duplicateDay)
        duplicateWriter.insert(
            persistedEntry(id: duplicateID, name: "Bir", day: duplicateDay)
        )
        duplicateWriter.insert(
            persistedEntry(id: duplicateID, name: "İki", day: duplicateDay)
        )
        try duplicateWriter.save()
        let duplicateRepository = makeRepository(
            container: duplicateContainer,
            calendar: fixture.calendar,
            now: fixture.now,
            generatedID: UUID()
        )
        do {
            _ = try await duplicateRepository.fetchMealEntries(
                containing: fixture.selectedDate
            )
            XCTFail("Expected duplicate entry ID failure.")
        } catch {
            XCTAssertEqual(
                error as? MealEntryRepositoryIntegrityError,
                .duplicateMealEntryIDs(id: duplicateID, count: 2)
            )
        }

        let missingID = uuid("00000000-0000-4000-8000-000000000889")
        let missingFixture = try makeFixture()
        do {
            _ = try await missingFixture.repository.updateMealEntry(
                id: missingID,
                update: try MealEntryUpdate(
                    category: MealCategory(kind: .lunch),
                    quantity: 1
                )
            )
            XCTFail("Expected missing update failure.")
        } catch {
            XCTAssertEqual(
                error as? MealEntryRepositoryMutationError,
                .mealEntryNotFound(id: missingID)
            )
        }
        do {
            _ = try await missingFixture.repository.deleteMealEntry(id: missingID)
            XCTFail("Expected missing delete failure.")
        } catch {
            XCTAssertEqual(
                error as? MealEntryRepositoryMutationError,
                .mealEntryNotFound(id: missingID)
            )
        }
    }

    private func assertCreateError<Failure: Error & Equatable>(
        repository: SwiftDataNutritionRepository,
        source: MealEntrySourceRequest,
        expected: Failure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await repository.createMealEntry(
                try request(
                    id: UUID(),
                    date: Date(timeIntervalSinceReferenceDate: 100),
                    category: MealCategory(kind: .dinner),
                    source: source
                )
            )
            XCTFail("Expected create failure.", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? Failure, expected, file: file, line: line)
        }
    }

    private func assertInvalidPersistedEntry(
        _ entry: MealEntry,
        id: UUID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = try makeFixture()
        let day = DailyNutritionLog(
            id: fixture.dayID,
            date: fixture.calendar.startOfDay(for: fixture.selectedDate)
        )
        entry.dailyNutritionLog = day
        let writer = ModelContext(fixture.container)
        writer.insert(day)
        writer.insert(entry)
        try writer.save()
        do {
            _ = try await fixture.repository.fetchMealEntries(
                containing: fixture.selectedDate
            )
            XCTFail("Expected invalid persisted entry failure.", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? MealEntryRepositoryIntegrityError,
                .invalidPersistedMealEntry(id: id),
                file: file,
                line: line
            )
        }
    }

    private func makeFixture() throws -> (
        container: ModelContainer,
        repository: SwiftDataNutritionRepository,
        calendar: Calendar,
        selectedDate: Date,
        now: Date,
        dayID: UUID
    ) {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let calendar = makeCalendar()
        let selectedDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 12,
            calendar: calendar
        )
        let now = Date(timeIntervalSinceReferenceDate: 8_000)
        let dayID = uuid("00000000-0000-4000-8000-000000000899")
        return (
            container,
            makeRepository(
                container: container,
                calendar: calendar,
                now: now,
                generatedID: dayID
            ),
            calendar,
            selectedDate,
            now,
            dayID
        )
    }

    private func makeRepository(
        container: ModelContainer,
        calendar: Calendar,
        now: Date,
        generatedID: UUID
    ) -> SwiftDataNutritionRepository {
        SwiftDataNutritionRepository(
            modelContext: ModelContext(container),
            calendar: calendar,
            now: { now },
            makeID: { generatedID }
        )
    }

    private func failingRepository(
        context: ModelContext,
        calendar: Calendar,
        generatedID: UUID
    ) -> SwiftDataNutritionRepository {
        SwiftDataNutritionRepository(
            modelContext: context,
            calendar: calendar,
            now: { Date(timeIntervalSinceReferenceDate: 11_000) },
            makeID: { generatedID },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )
    }

    private func request(
        id: UUID,
        date: Date,
        category: MealCategory,
        source: MealEntrySourceRequest
    ) throws -> MealEntryCreateRequest {
        try MealEntryCreateRequest(
            requestID: id,
            date: date,
            category: category,
            source: source
        )
    }

    private func persistedRecipe(
        id: UUID,
        name: String,
        servings: Double = 2,
        calories: Double = 400,
        proteinG: Double = 30,
        carbG: Double = 40,
        fatG: Double = 12
    ) -> Recipe {
        Recipe(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            name: name,
            category: MealCategory.defaultValue,
            servings: servings,
            isDirectMacros: true,
            caloriesTotal: calories,
            proteinTotalG: proteinG,
            carbTotalG: carbG,
            fatTotalG: fatG,
            note: nil
        )
    }

    private func persistedFood(
        id: UUID,
        name: String,
        calories: Double = 100,
        proteinG: Double = 10,
        carbG: Double = 20,
        fatG: Double = 5,
        source: FoodSource = .userCreated
    ) -> Food {
        Food(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            name: name,
            brand: nil,
            servingSize: 100,
            servingUnit: "g",
            caloriesPerServing: calories,
            proteinG: proteinG,
            carbG: carbG,
            fatG: fatG,
            fiberG: nil,
            source: source
        )
    }

    private func persistedEntry(
        id: UUID,
        name: String,
        quantity: Double = 1,
        calories: Double = 100,
        createdAt: Date = Date(timeIntervalSinceReferenceDate: 100),
        loggedAt: Date = Date(timeIntervalSinceReferenceDate: 100),
        day: DailyNutritionLog
    ) -> MealEntry {
        MealEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: createdAt,
            category: MealCategory.defaultValue,
            adhocName: name,
            quantity: quantity,
            caloriesResolved: calories,
            proteinResolved: 10,
            carbResolved: 20,
            fatResolved: 5,
            loggedAt: loggedAt,
            dailyNutritionLog: day
        )
    }

    private func macros(
        calories: Decimal = 400,
        proteinG: Decimal = 30,
        carbG: Decimal = 40,
        fatG: Decimal = 12
    ) throws -> NutritionMacros {
        try NutritionMacros(
            calories: calories,
            proteinG: proteinG,
            carbG: carbG,
            fatG: fatG
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
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

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}

    private func assertNutritionRepository(_: any NutritionRepository) {}
}
