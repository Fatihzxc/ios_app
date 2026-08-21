import CoreModels
import Foundation
@testable import NutritionKit
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class RecipeRepositoryTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testCreateAndUpdateUseDirectMacrosStableIdentityAndInjectedTimestamps() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let recipeID = uuid("00000000-0000-4000-8000-000000000601")
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 2_000)
        var timestamp = createdAt
        let repository = SwiftDataNutritionRepository(
            modelContext: context,
            calendar: makeCalendar(),
            now: { timestamp },
            makeID: { recipeID }
        )

        let created = try await repository.createRecipe(
            try makeInput(
                name: "  Akşam Kasesi  ",
                category: MealCategory(kind: .custom, customName: "  Gece  "),
                servings: decimal("3.5"),
                note: "  Hazırla  "
            )
        )

        XCTAssertEqual(created.id, recipeID)
        XCTAssertEqual(created.createdAt, createdAt)
        XCTAssertEqual(created.updatedAt, createdAt)
        XCTAssertEqual(created.name, "Akşam Kasesi")
        XCTAssertEqual(created.category.customName, "Gece")
        XCTAssertEqual(created.servings, decimal("3.5"))
        XCTAssertTrue(created.isDirectMacros)
        XCTAssertEqual(created.note, "Hazırla")

        timestamp = updatedAt
        let updated = try await repository.updateRecipe(
            id: recipeID,
            input: try makeInput(
                name: "Güncel Tarif",
                category: MealCategory(kind: .lunch),
                servings: decimal("2.25"),
                calories: decimal("555.25"),
                proteinG: decimal("44.5"),
                carbG: 50,
                fatG: 15,
                note: " "
            )
        )

        XCTAssertEqual(updated.id, recipeID)
        XCTAssertEqual(updated.createdAt, createdAt)
        XCTAssertEqual(updated.updatedAt, updatedAt)
        XCTAssertEqual(updated.category.kind, .lunch)
        XCTAssertEqual(updated.servings, decimal("2.25"))
        XCTAssertEqual(updated.totalMacros.calories, decimal("555.25"))
        XCTAssertNil(updated.note)
        XCTAssertTrue(updated.isDirectMacros)

        let stored = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<Recipe>()).first
        )
        XCTAssertEqual(stored.id, recipeID)
        XCTAssertEqual(stored.createdAt, createdAt)
        XCTAssertEqual(stored.updatedAt, updatedAt)
        XCTAssertTrue(stored.isDirectMacros)
        XCTAssertEqual(stored.name, "Güncel Tarif")
        assertEquatableSendable(updated)
    }

    func testQuerySearchCategoryFilterAndOrderingAreDeterministic() async throws {
        let fixture = try makeFixture()
        let writer = ModelContext(fixture.container)
        let breakfastID = uuid("00000000-0000-4000-8000-000000000611")
        let lunchID = uuid("00000000-0000-4000-8000-000000000612")
        let archivedID = uuid("00000000-0000-4000-8000-000000000613")
        let activeCustomID = uuid("00000000-0000-4000-8000-000000000614")
        writer.insert(
            persistedRecipe(
                id: lunchID,
                name: "Éclair",
                category: try MealCategory(kind: .lunch)
            )
        )
        writer.insert(
            persistedRecipe(
                id: breakfastID,
                name: "eclair",
                category: try MealCategory(kind: .breakfast)
            )
        )
        writer.insert(
            persistedRecipe(
                id: activeCustomID,
                name: "Yoğurt",
                category: try MealCategory(kind: .custom, customName: "Zulu")
            )
        )
        writer.insert(
            persistedRecipe(
                id: archivedID,
                name: "yoğurt",
                category: try MealCategory(kind: .custom, customName: "Alpha")
            )
        )
        writer.insert(
            AppSetting(
                key: RecipeArchiveCodec.settingKey,
                value: try RecipeArchiveCodec.encode([archivedID])
            )
        )
        try writer.save()

        let all = try await fixture.repository.fetchRecipeLibrary(
            matching: " \n ",
            category: nil
        )
        let eclair = try await fixture.repository.fetchRecipeLibrary(
            matching: "ECLAIR",
            category: nil
        )
        let yogurt = try await fixture.repository.fetchRecipeLibrary(
            matching: "yogurt",
            category: nil
        )
        let custom = try await fixture.repository.fetchRecipeLibrary(
            matching: "",
            category: .custom
        )

        XCTAssertEqual(all.active.map(\.id), [breakfastID, lunchID, activeCustomID])
        XCTAssertEqual(all.archived.map(\.id), [archivedID])
        XCTAssertEqual(eclair.active.map(\.id), [breakfastID, lunchID])
        XCTAssertTrue(eclair.archived.isEmpty)
        XCTAssertEqual(yogurt.active.map(\.id), [activeCustomID])
        XCTAssertEqual(yogurt.archived.map(\.id), [archivedID])
        XCTAssertEqual(custom.active.map(\.id), [activeCustomID])
        XCTAssertEqual(custom.archived.map(\.id), [archivedID])
        assertEquatableSendable(all)
    }

    func testReferencedRemoveArchivesAndRestorePreservesMealEntrySnapshot() async throws {
        let fixture = try makeFixture()
        let recipeID = uuid("00000000-0000-4000-8000-000000000621")
        let entryID = uuid("00000000-0000-4000-8000-000000000622")
        let writer = ModelContext(fixture.container)
        writer.insert(persistedRecipe(id: recipeID, name: "Referanslı"))
        writer.insert(
            MealEntry(
                id: entryID,
                category: try MealCategory(kind: .dinner),
                recipeId: recipeID,
                quantity: 1.5,
                caloriesResolved: 375,
                proteinResolved: 30,
                carbResolved: 42,
                fatResolved: 9,
                loggedAt: Date(timeIntervalSinceReferenceDate: 500)
            )
        )
        try writer.save()

        let removal = try await fixture.repository.removeRecipe(id: recipeID)
        XCTAssertEqual(removal, .archived)

        var library = try await fixture.repository.fetchRecipeLibrary(
            matching: "",
            category: nil
        )
        XCTAssertTrue(library.active.isEmpty)
        XCTAssertEqual(library.archived.map(\.id), [recipeID])
        XCTAssertEqual(
            try ModelContext(fixture.container).fetchCount(FetchDescriptor<Recipe>()),
            1
        )
        assertEntrySnapshot(
            try XCTUnwrap(
                ModelContext(fixture.container)
                    .fetch(FetchDescriptor<MealEntry>())
                    .first
            ),
            id: entryID,
            recipeID: recipeID
        )

        let restored = try await fixture.repository.restoreRecipe(id: recipeID)
        XCTAssertEqual(restored.id, recipeID)
        library = try await fixture.repository.fetchRecipeLibrary(
            matching: "",
            category: nil
        )
        XCTAssertEqual(library.active.map(\.id), [recipeID])
        XCTAssertTrue(library.archived.isEmpty)
        assertEntrySnapshot(
            try XCTUnwrap(
                ModelContext(fixture.container)
                    .fetch(FetchDescriptor<MealEntry>())
                    .first
            ),
            id: entryID,
            recipeID: recipeID
        )
    }

    func testUnreferencedRemoveHardDeletesAndCleansStaleArchiveID() async throws {
        let fixture = try makeFixture()
        let recipeID = uuid("00000000-0000-4000-8000-000000000631")
        let writer = ModelContext(fixture.container)
        writer.insert(persistedRecipe(id: recipeID, name: "Silinebilir"))
        writer.insert(
            AppSetting(
                key: RecipeArchiveCodec.settingKey,
                value: try RecipeArchiveCodec.encode([recipeID])
            )
        )
        try writer.save()

        let removal = try await fixture.repository.removeRecipe(id: recipeID)

        XCTAssertEqual(removal, .deleted)
        let reader = ModelContext(fixture.container)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Recipe>()), 0)
        let setting = try XCTUnwrap(reader.fetch(FetchDescriptor<AppSetting>()).first)
        XCTAssertEqual(try RecipeArchiveCodec.decode(setting.value), [])
    }

    func testUpdateDoesNotChangeExistingMealEntrySnapshot() async throws {
        let fixture = try makeFixture()
        let recipeID = uuid("00000000-0000-4000-8000-000000000641")
        let entryID = uuid("00000000-0000-4000-8000-000000000642")
        let writer = ModelContext(fixture.container)
        writer.insert(persistedRecipe(id: recipeID, name: "Önce"))
        writer.insert(
            MealEntry(
                id: entryID,
                category: try MealCategory(kind: .lunch),
                recipeId: recipeID,
                quantity: 1.5,
                caloriesResolved: 375,
                proteinResolved: 30,
                carbResolved: 42,
                fatResolved: 9,
                loggedAt: Date(timeIntervalSinceReferenceDate: 500)
            )
        )
        try writer.save()

        _ = try await fixture.repository.updateRecipe(
            id: recipeID,
            input: try makeInput(name: "Sonra", calories: 999)
        )

        assertEntrySnapshot(
            try XCTUnwrap(
                ModelContext(fixture.container)
                    .fetch(FetchDescriptor<MealEntry>())
                    .first
            ),
            id: entryID,
            recipeID: recipeID
        )
    }

    func testMissingArchiveIsEmptyButCorruptUnsupportedAndDuplicateSettingsFailClosed() async throws {
        let fixture = try makeFixture()
        let missing = try await fixture.repository.fetchRecipeLibrary(
            matching: "",
            category: nil
        )
        XCTAssertEqual(missing, RecipeLibrarySnapshot(active: [], archived: []))

        try await assertArchiveFailure(
            value: "not-json",
            expected: RecipeArchiveCodecError.malformedPayload
        )
        try await assertArchiveFailure(
            value: #"{"recipeIDs":[],"schemaVersion":2}"#,
            expected: RecipeArchiveCodecError.unsupportedSchemaVersion(2)
        )

        let duplicateContainer = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(duplicateContainer)
        writer.insert(
            AppSetting(
                key: RecipeArchiveCodec.settingKey,
                value: try RecipeArchiveCodec.encode([])
            )
        )
        writer.insert(
            AppSetting(
                key: RecipeArchiveCodec.settingKey,
                value: try RecipeArchiveCodec.encode([])
            )
        )
        try writer.save()
        let repository = makeRepository(container: duplicateContainer)
        do {
            _ = try await repository.fetchRecipeLibrary(matching: "", category: nil)
            XCTFail("Expected duplicate archive settings to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? RecipeRepositoryIntegrityError,
                .duplicateArchiveSettings(count: 2)
            )
        }
    }

    func testDuplicateIDsGeneratedCollisionInvalidRowsAndMissingMutationsFailClosed() async throws {
        let generatedID = uuid("00000000-0000-4000-8000-000000000651")
        let fixture = try makeFixture(generatedID: generatedID)
        let duplicateID = uuid("00000000-0000-4000-8000-000000000652")
        let writer = ModelContext(fixture.container)
        writer.insert(persistedRecipe(id: generatedID, name: "Çakışan"))
        writer.insert(persistedRecipe(id: duplicateID, name: "Bir"))
        writer.insert(persistedRecipe(id: duplicateID, name: "İki"))
        try writer.save()

        do {
            _ = try await fixture.repository.createRecipe(try makeInput())
            XCTFail("Expected a generated ID collision.")
        } catch {
            XCTAssertEqual(
                error as? RecipeRepositoryIntegrityError,
                .recipeIDCollision(id: generatedID)
            )
        }

        do {
            _ = try await fixture.repository.fetchRecipeLibrary(matching: "", category: nil)
            XCTFail("Expected duplicate recipe IDs to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? RecipeRepositoryIntegrityError,
                .duplicateRecipeIDs(id: duplicateID, count: 2)
            )
        }

        let missingContainer = try ModelContainerFactory.make(for: .inMemory)
        let missingWriter = ModelContext(missingContainer)
        missingWriter.insert(persistedRecipe(id: generatedID, name: "Arşivde değil"))
        try missingWriter.save()
        let missingRepository = makeRepository(container: missingContainer)
        let missingID = uuid("00000000-0000-4000-8000-000000000659")
        do {
            _ = try await missingRepository.updateRecipe(
                id: missingID,
                input: try makeInput()
            )
            XCTFail("Expected a missing-recipe update failure.")
        } catch {
            XCTAssertEqual(
                error as? RecipeRepositoryMutationError,
                .recipeNotFound(id: missingID)
            )
        }

        do {
            _ = try await missingRepository.restoreRecipe(id: generatedID)
            XCTFail("Expected a not-archived restore failure.")
        } catch {
            XCTAssertEqual(
                error as? RecipeRepositoryMutationError,
                .recipeNotArchived(id: generatedID)
            )
        }

        let invalidContainer = try ModelContainerFactory.make(for: .inMemory)
        let invalidID = uuid("00000000-0000-4000-8000-000000000653")
        let invalidWriter = ModelContext(invalidContainer)
        invalidWriter.insert(
            persistedRecipe(
                id: invalidID,
                name: "Bileşimli",
                isDirectMacros: false
            )
        )
        try invalidWriter.save()
        do {
            _ = try await makeRepository(container: invalidContainer)
                .fetchRecipeLibrary(matching: "", category: nil)
            XCTFail("Expected non-direct persisted recipes to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? RecipeRepositoryIntegrityError,
                .invalidPersistedRecipe(id: invalidID)
            )
        }
    }

    func testCreateAndUpdateSaveFailuresRollback() async throws {
        let createContainer = try ModelContainerFactory.make(for: .inMemory)
        let createContext = ModelContext(createContainer)
        let createRepository = SwiftDataNutritionRepository(
            modelContext: createContext,
            calendar: makeCalendar(),
            now: { Date(timeIntervalSinceReferenceDate: 3_000) },
            makeID: { self.uuid("00000000-0000-4000-8000-000000000661") },
            save: { throw FixtureFailure.save },
            rollback: { createContext.rollback() }
        )
        do {
            _ = try await createRepository.createRecipe(try makeInput())
            XCTFail("Expected create save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .saveFailed)
        }
        XCTAssertEqual(
            try ModelContext(createContainer).fetchCount(FetchDescriptor<Recipe>()),
            0
        )

        let updateContainer = try ModelContainerFactory.make(for: .inMemory)
        let recipeID = uuid("00000000-0000-4000-8000-000000000662")
        let originalUpdatedAt = Date(timeIntervalSinceReferenceDate: 3_500)
        let writer = ModelContext(updateContainer)
        writer.insert(
            persistedRecipe(
                id: recipeID,
                name: "Korunan",
                updatedAt: originalUpdatedAt
            )
        )
        try writer.save()
        let updateContext = ModelContext(updateContainer)
        let updateRepository = SwiftDataNutritionRepository(
            modelContext: updateContext,
            calendar: makeCalendar(),
            now: { Date(timeIntervalSinceReferenceDate: 4_000) },
            makeID: { UUID() },
            save: { throw FixtureFailure.save },
            rollback: { updateContext.rollback() }
        )
        do {
            _ = try await updateRepository.updateRecipe(
                id: recipeID,
                input: try makeInput(name: "Kaybolmamalı")
            )
            XCTFail("Expected update save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .saveFailed)
        }
        let stored = try XCTUnwrap(
            ModelContext(updateContainer).fetch(FetchDescriptor<Recipe>()).first
        )
        XCTAssertEqual(stored.name, "Korunan")
        XCTAssertEqual(stored.updatedAt, originalUpdatedAt)
    }

    func testHardDeleteArchiveAndRestoreSaveFailuresRollbackAtomically() async throws {
        let hardDeleteContainer = try ModelContainerFactory.make(for: .inMemory)
        let hardDeleteID = uuid("00000000-0000-4000-8000-000000000671")
        let hardDeleteWriter = ModelContext(hardDeleteContainer)
        hardDeleteWriter.insert(persistedRecipe(id: hardDeleteID, name: "Korunan silme"))
        try hardDeleteWriter.save()
        let hardDeleteContext = ModelContext(hardDeleteContainer)
        let hardDeleteRepository = failingRepository(context: hardDeleteContext)
        do {
            _ = try await hardDeleteRepository.removeRecipe(id: hardDeleteID)
            XCTFail("Expected hard-delete save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .deleteFailed)
        }
        XCTAssertEqual(
            try ModelContext(hardDeleteContainer).fetchCount(FetchDescriptor<Recipe>()),
            1
        )

        let archiveContainer = try ModelContainerFactory.make(for: .inMemory)
        let archiveID = uuid("00000000-0000-4000-8000-000000000672")
        let archiveWriter = ModelContext(archiveContainer)
        archiveWriter.insert(persistedRecipe(id: archiveID, name: "Korunan arşiv"))
        archiveWriter.insert(MealEntry(recipeId: archiveID, quantity: 1))
        try archiveWriter.save()
        let archiveContext = ModelContext(archiveContainer)
        let archiveRepository = failingRepository(context: archiveContext)
        do {
            _ = try await archiveRepository.removeRecipe(id: archiveID)
            XCTFail("Expected archive save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .deleteFailed)
        }
        let archiveReader = ModelContext(archiveContainer)
        XCTAssertEqual(try archiveReader.fetchCount(FetchDescriptor<Recipe>()), 1)
        XCTAssertEqual(try archiveReader.fetchCount(FetchDescriptor<AppSetting>()), 0)

        let restoreContainer = try ModelContainerFactory.make(for: .inMemory)
        let restoreID = uuid("00000000-0000-4000-8000-000000000673")
        let restoreWriter = ModelContext(restoreContainer)
        restoreWriter.insert(persistedRecipe(id: restoreID, name: "Korunan restore"))
        restoreWriter.insert(
            AppSetting(
                key: RecipeArchiveCodec.settingKey,
                value: try RecipeArchiveCodec.encode([restoreID])
            )
        )
        try restoreWriter.save()
        let restoreContext = ModelContext(restoreContainer)
        let restoreRepository = failingRepository(context: restoreContext)
        do {
            _ = try await restoreRepository.restoreRecipe(id: restoreID)
            XCTFail("Expected restore save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .saveFailed)
        }
        let restoreSetting = try XCTUnwrap(
            ModelContext(restoreContainer).fetch(FetchDescriptor<AppSetting>()).first
        )
        XCTAssertEqual(try RecipeArchiveCodec.decode(restoreSetting.value), [restoreID])
    }

    private func assertArchiveFailure(
        value: String,
        expected: RecipeArchiveCodecError
    ) async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        writer.insert(AppSetting(key: RecipeArchiveCodec.settingKey, value: value))
        try writer.save()
        do {
            _ = try await makeRepository(container: container)
                .fetchRecipeLibrary(matching: "", category: nil)
            XCTFail("Expected corrupt archive failure.")
        } catch {
            XCTAssertEqual(error as? RecipeArchiveCodecError, expected)
        }
    }

    private func assertEntrySnapshot(
        _ entry: MealEntry,
        id: UUID,
        recipeID: UUID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(entry.id, id, file: file, line: line)
        XCTAssertEqual(entry.recipeId, recipeID, file: file, line: line)
        XCTAssertEqual(entry.quantity, 1.5, file: file, line: line)
        XCTAssertEqual(entry.caloriesResolved, 375, file: file, line: line)
        XCTAssertEqual(entry.proteinResolved, 30, file: file, line: line)
        XCTAssertEqual(entry.carbResolved, 42, file: file, line: line)
        XCTAssertEqual(entry.fatResolved, 9, file: file, line: line)
    }

    private func makeFixture(
        generatedID: UUID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000600"
        )!
    ) throws -> (
        container: ModelContainer,
        repository: SwiftDataNutritionRepository
    ) {
        let container = try ModelContainerFactory.make(for: .inMemory)
        return (container, makeRepository(container: container, generatedID: generatedID))
    }

    private func makeRepository(
        container: ModelContainer,
        generatedID: UUID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000600"
        )!
    ) -> SwiftDataNutritionRepository {
        SwiftDataNutritionRepository(
            modelContext: ModelContext(container),
            calendar: makeCalendar(),
            now: { Date(timeIntervalSinceReferenceDate: 1_000) },
            makeID: { generatedID }
        )
    }

    private func failingRepository(
        context: ModelContext
    ) -> SwiftDataNutritionRepository {
        SwiftDataNutritionRepository(
            modelContext: context,
            calendar: makeCalendar(),
            now: { Date(timeIntervalSinceReferenceDate: 4_000) },
            makeID: { UUID() },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )
    }

    private func makeInput(
        name: String = "Tarif",
        category: MealCategory? = nil,
        servings: Decimal = 2,
        calories: Decimal = 400,
        proteinG: Decimal = 30,
        carbG: Decimal = 40,
        fatG: Decimal = 12,
        note: String? = nil
    ) throws -> RecipeInput {
        try RecipeInput(
            name: name,
            category: category ?? MealCategory(kind: .dinner),
            servings: servings,
            caloriesTotal: calories,
            proteinTotalG: proteinG,
            carbTotalG: carbG,
            fatTotalG: fatG,
            note: note
        )
    }

    private func persistedRecipe(
        id: UUID,
        name: String,
        category: MealCategory? = nil,
        servings: Double = 2,
        isDirectMacros: Bool = true,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 500)
    ) -> Recipe {
        Recipe(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 400),
            updatedAt: updatedAt,
            name: name,
            category: category ?? MealCategory.defaultValue,
            servings: servings,
            isDirectMacros: isDirectMacros,
            caloriesTotal: 400,
            proteinTotalG: 30,
            carbTotalG: 40,
            fatTotalG: 12,
            note: nil
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}
