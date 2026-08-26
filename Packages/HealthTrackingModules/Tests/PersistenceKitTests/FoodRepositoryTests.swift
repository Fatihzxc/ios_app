import CoreModels
import Foundation
@testable import NutritionKit
@testable import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class FoodRepositoryTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testCreateAndUpdateUseStableIdentitySourceAndInjectedTimestamps() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let foodID = uuid("00000000-0000-4000-8000-000000000201")
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 2_000)
        var timestamp = createdAt
        let repository = SwiftDataNutritionRepository(
            modelContext: context,
            calendar: makeCalendar(),
            now: { timestamp },
            makeID: { foodID }
        )

        let created = try await repository.createFood(
            try makeInput(name: "  Yoğurt  ", brand: "  Marka  ")
        )

        XCTAssertEqual(created.id, foodID)
        XCTAssertEqual(created.createdAt, createdAt)
        XCTAssertEqual(created.updatedAt, createdAt)
        XCTAssertEqual(created.name, "Yoğurt")
        XCTAssertEqual(created.brand, "Marka")
        XCTAssertEqual(created.source, .userCreated)

        timestamp = updatedAt
        let updated = try await repository.updateFood(
            id: foodID,
            input: try makeInput(
                name: "Kefir",
                brand: " ",
                servingSize: decimal("250"),
                servingUnit: "ml",
                calories: decimal("150.25"),
                proteinG: decimal("8.5"),
                carbG: 12,
                fatG: 4,
                fiberG: 0
            )
        )

        XCTAssertEqual(updated.id, foodID)
        XCTAssertEqual(updated.createdAt, createdAt)
        XCTAssertEqual(updated.updatedAt, updatedAt)
        XCTAssertEqual(updated.source, .userCreated)
        XCTAssertEqual(updated.name, "Kefir")
        XCTAssertNil(updated.brand)
        XCTAssertEqual(updated.servingSize, 250)
        XCTAssertEqual(updated.macros.calories, decimal("150.25"))
        XCTAssertEqual(updated.fiberG, 0)

        let stored = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<Food>()).first
        )
        XCTAssertEqual(stored.id, foodID)
        XCTAssertEqual(stored.createdAt, createdAt)
        XCTAssertEqual(stored.updatedAt, updatedAt)
        XCTAssertEqual(stored.source, .userCreated)
        XCTAssertEqual(stored.name, "Kefir")
        assertEquatableSendable(updated)
    }

    func testQueryIsCaseAndDiacriticInsensitiveWithDeterministicOrdering() async throws {
        let fixture = try makeFixture()
        let writer = ModelContext(fixture.container)
        let firstID = uuid("00000000-0000-4000-8000-000000000211")
        let secondID = uuid("00000000-0000-4000-8000-000000000212")
        let thirdID = uuid("00000000-0000-4000-8000-000000000213")
        let fourthID = uuid("00000000-0000-4000-8000-000000000214")
        writer.insert(persistedFood(id: thirdID, name: "Yoğurt", brand: "Café"))
        writer.insert(persistedFood(id: firstID, name: "Éclair", brand: "Zulu"))
        writer.insert(persistedFood(id: fourthID, name: "Yoğurt", brand: nil))
        writer.insert(persistedFood(id: secondID, name: "eclair", brand: "Alpha"))
        try writer.save()

        let all = try await fixture.repository.fetchFoods(matching: " \n ")
        let nameMatches = try await fixture.repository.fetchFoods(matching: "ECLAIR")
        let brandMatches = try await fixture.repository.fetchFoods(matching: "cafe")
        let yogurtMatches = try await fixture.repository.fetchFoods(matching: "yogurt")

        XCTAssertEqual(all.map(\.id), [secondID, firstID, fourthID, thirdID])
        XCTAssertEqual(nameMatches.map(\.id), [secondID, firstID])
        XCTAssertEqual(brandMatches.map(\.id), [thirdID])
        XCTAssertEqual(yogurtMatches.map(\.id), [fourthID, thirdID])
    }

    func testHealthKitFoodsAreReadableButCannotBeUpdatedOrDeleted() async throws {
        let fixture = try makeFixture()
        let foodID = uuid("00000000-0000-4000-8000-000000000221")
        let writer = ModelContext(fixture.container)
        writer.insert(
            persistedFood(
                id: foodID,
                name: "HealthKit Besini",
                brand: nil,
                source: .healthKit
            )
        )
        try writer.save()

        let snapshots = try await fixture.repository.fetchFoods(matching: "healthkit")
        XCTAssertEqual(snapshots.map(\.source), [.healthKit])

        do {
            _ = try await fixture.repository.updateFood(
                id: foodID,
                input: try makeInput(name: "Değiştirilemez")
            )
            XCTFail("Expected an immutable-source update failure.")
        } catch {
            XCTAssertEqual(
                error as? FoodRepositoryMutationError,
                .unsupportedMutationSource(id: foodID, source: .healthKit)
            )
        }

        do {
            try await fixture.repository.deleteFood(id: foodID)
            XCTFail("Expected an immutable-source delete failure.")
        } catch {
            XCTAssertEqual(
                error as? FoodRepositoryMutationError,
                .unsupportedMutationSource(id: foodID, source: .healthKit)
            )
        }
    }

    func testDeletingReferencedAndUnreferencedFoodsPreservesMealSnapshots() async throws {
        let fixture = try makeFixture()
        let referencedID = uuid("00000000-0000-4000-8000-000000000231")
        let unreferencedID = uuid("00000000-0000-4000-8000-000000000232")
        let entryID = uuid("00000000-0000-4000-8000-000000000233")
        let writer = ModelContext(fixture.container)
        writer.insert(persistedFood(id: referencedID, name: "Eski besin", brand: nil))
        writer.insert(persistedFood(id: unreferencedID, name: "Kullanılmayan", brand: nil))
        writer.insert(
            MealEntry(
                id: entryID,
                foodId: referencedID,
                quantity: 2,
                caloriesResolved: 240,
                proteinResolved: 20,
                carbResolved: 30,
                fatResolved: 8
            )
        )
        try writer.save()

        try await fixture.repository.deleteFood(id: referencedID)
        try await fixture.repository.deleteFood(id: unreferencedID)

        let reader = ModelContext(fixture.container)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Food>()), 0)
        let entry = try XCTUnwrap(reader.fetch(FetchDescriptor<MealEntry>()).first)
        XCTAssertEqual(entry.id, entryID)
        XCTAssertEqual(entry.foodId, referencedID)
        XCTAssertEqual(entry.quantity, 2)
        XCTAssertEqual(entry.caloriesResolved, 240)
        XCTAssertEqual(entry.proteinResolved, 20)
        XCTAssertEqual(entry.carbResolved, 30)
        XCTAssertEqual(entry.fatResolved, 8)
    }

    func testDuplicateIDsGeneratedCollisionMissingRecordAndInvalidRowsFailClosed() async throws {
        let fixture = try makeFixture(
            generatedID: uuid("00000000-0000-4000-8000-000000000241")
        )
        let duplicateID = uuid("00000000-0000-4000-8000-000000000242")
        let writer = ModelContext(fixture.container)
        writer.insert(persistedFood(id: fixture.generatedID, name: "Çakışan", brand: nil))
        writer.insert(persistedFood(id: duplicateID, name: "Bir", brand: nil))
        writer.insert(persistedFood(id: duplicateID, name: "İki", brand: nil))
        try writer.save()

        do {
            _ = try await fixture.repository.createFood(try makeInput())
            XCTFail("Expected a generated ID collision.")
        } catch {
            XCTAssertEqual(
                error as? FoodRepositoryIntegrityError,
                .foodIDCollision(id: fixture.generatedID)
            )
        }

        do {
            _ = try await fixture.repository.updateFood(
                id: duplicateID,
                input: try makeInput()
            )
            XCTFail("Expected duplicate IDs to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? FoodRepositoryIntegrityError,
                .duplicateFoodIDs(id: duplicateID, count: 2)
            )
        }

        do {
            try await fixture.repository.deleteFood(
                id: uuid("00000000-0000-4000-8000-000000000249")
            )
            XCTFail("Expected a missing-food failure.")
        } catch {
            XCTAssertEqual(
                error as? FoodRepositoryMutationError,
                .foodNotFound(id: uuid("00000000-0000-4000-8000-000000000249"))
            )
        }
    }

    func testInvalidPersistedFoodFailsClosed() async throws {
        let fixture = try makeFixture()
        let invalidID = uuid("00000000-0000-4000-8000-000000000243")
        let writer = ModelContext(fixture.container)
        writer.insert(
            persistedFood(
                id: invalidID,
                name: "Geçersiz",
                brand: nil,
                servingSize: 0
            )
        )
        try writer.save()

        do {
            _ = try await fixture.repository.fetchFoods(matching: "geçersiz")
            XCTFail("Expected invalid persisted input to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? FoodRepositoryIntegrityError,
                .invalidPersistedFood(id: invalidID)
            )
        }
    }

    func testCreateSaveFailureRollsBackInsertedFood() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let repository = SwiftDataNutritionRepository(
            modelContext: context,
            calendar: makeCalendar(),
            now: { Date(timeIntervalSinceReferenceDate: 3_000) },
            makeID: { self.uuid("00000000-0000-4000-8000-000000000251") },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.createFood(try makeInput())
            XCTFail("Expected a create save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .saveFailed)
        }

        XCTAssertEqual(
            try ModelContext(container).fetchCount(FetchDescriptor<Food>()),
            0
        )
    }

    func testUpdateAndDeleteSaveFailuresRollbackExistingFood() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let foodID = uuid("00000000-0000-4000-8000-000000000261")
        let originalUpdatedAt = Date(timeIntervalSinceReferenceDate: 3_500)
        let writer = ModelContext(container)
        writer.insert(
            persistedFood(
                id: foodID,
                name: "Korunan",
                brand: "Marka",
                updatedAt: originalUpdatedAt
            )
        )
        try writer.save()
        let context = ModelContext(container)
        let repository = SwiftDataNutritionRepository(
            modelContext: context,
            calendar: makeCalendar(),
            now: { Date(timeIntervalSinceReferenceDate: 4_000) },
            makeID: { self.uuid("00000000-0000-4000-8000-000000000262") },
            save: { throw FixtureFailure.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.updateFood(
                id: foodID,
                input: try makeInput(name: "Kaybolmamalı", brand: nil)
            )
            XCTFail("Expected an update save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .saveFailed)
        }

        var stored = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<Food>()).first
        )
        XCTAssertEqual(stored.name, "Korunan")
        XCTAssertEqual(stored.brand, "Marka")
        XCTAssertEqual(stored.updatedAt, originalUpdatedAt)

        do {
            try await repository.deleteFood(id: foodID)
            XCTFail("Expected a delete save failure.")
        } catch {
            XCTAssertEqual(error as? NutritionRepositoryOperationError, .deleteFailed)
        }

        stored = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Food>()).first)
        XCTAssertEqual(stored.id, foodID)
        XCTAssertEqual(stored.name, "Korunan")
    }

    private func makeFixture(
        generatedID: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000200")!
    ) throws -> (
        container: ModelContainer,
        generatedID: UUID,
        repository: SwiftDataNutritionRepository
    ) {
        let container = try ModelContainerFactory.make(for: .inMemory)
        return (
            container,
            generatedID,
            SwiftDataNutritionRepository(
                modelContext: ModelContext(container),
                calendar: makeCalendar(),
                now: { Date(timeIntervalSinceReferenceDate: 1_000) },
                makeID: { generatedID }
            )
        )
    }

    private func makeInput(
        name: String = "Besin",
        brand: String? = nil,
        servingSize: Decimal = 100,
        servingUnit: String = "g",
        calories: Decimal = 120,
        proteinG: Decimal = 10,
        carbG: Decimal = 15,
        fatG: Decimal = 4,
        fiberG: Decimal? = nil
    ) throws -> FoodInput {
        try FoodInput(
            name: name,
            brand: brand,
            servingSize: servingSize,
            servingUnit: servingUnit,
            caloriesPerServing: calories,
            proteinG: proteinG,
            carbG: carbG,
            fatG: fatG,
            fiberG: fiberG
        )
    }

    private func persistedFood(
        id: UUID,
        name: String,
        brand: String?,
        source: FoodSource = .userCreated,
        servingSize: Double = 100,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 500)
    ) -> Food {
        Food(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 400),
            updatedAt: updatedAt,
            name: name,
            brand: brand,
            servingSize: servingSize,
            servingUnit: "g",
            caloriesPerServing: 120,
            proteinG: 10,
            carbG: 15,
            fatG: 4,
            fiberG: 2,
            source: source
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
