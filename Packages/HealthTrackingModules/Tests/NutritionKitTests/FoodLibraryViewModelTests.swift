import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

@MainActor
final class FoodLibraryViewModelTests: XCTestCase {
    func testLoadDistinguishesContentEmptyAndSearchEmptyStates() async throws {
        let original = try makeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000301"),
            name: "Yoğurt"
        )
        let repository = FoodRepositoryStub(foods: [original])
        let viewModel = FoodLibraryViewModel(repository: repository)

        XCTAssertEqual(viewModel.state, .loading)
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .content([original]))

        repository.foods = []
        await viewModel.search("protein")
        XCTAssertEqual(viewModel.state, .searchEmpty)
        XCTAssertEqual(viewModel.query, "protein")

        await viewModel.search(" \n ")
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(Array(repository.queries.suffix(2)), ["protein", " \n "])
        assertEquatableSendable(viewModel.state)
    }

    func testLoadErrorAndRetryAreRecoverable() async throws {
        let repository = FoodRepositoryStub(foods: [])
        repository.loadFails = true
        let viewModel = FoodLibraryViewModel(repository: repository)

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .error)

        let recovered = try makeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000302"),
            name: "Kefir"
        )
        repository.loadFails = false
        repository.foods = [recovered]
        await viewModel.retry()

        XCTAssertEqual(viewModel.state, .content([recovered]))
    }

    func testSuccessfulCreateUpdateAndDeleteRefreshTheCurrentQuery() async throws {
        let original = try makeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000303"),
            name: "Eski"
        )
        let createdID = uuid("00000000-0000-4000-8000-000000000304")
        let repository = FoodRepositoryStub(foods: [original], generatedID: createdID)
        let viewModel = FoodLibraryViewModel(repository: repository)
        await viewModel.search("aktif")

        let createdResult = await viewModel.create(try makeInput(name: "Yeni"))
        XCTAssertTrue(createdResult)
        XCTAssertEqual(viewModel.mutationState, .idle)
        XCTAssertEqual(repository.queries.last, "aktif")
        XCTAssertEqual(repository.foods.map(\.name), ["Eski", "Yeni"])

        let updatedResult = await viewModel.update(
            id: createdID,
            input: try makeInput(name: "Güncel")
        )
        XCTAssertTrue(updatedResult)
        XCTAssertEqual(repository.foods.map(\.name), ["Eski", "Güncel"])

        let deletedResult = await viewModel.delete(id: original.id)
        XCTAssertTrue(deletedResult)
        XCTAssertEqual(repository.foods.map(\.name), ["Güncel"])
        XCTAssertEqual(viewModel.state, .content(repository.foods))
    }

    func testFailedMutationsPreserveValidatedListAndExposeSaveError() async throws {
        let original = try makeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000305"),
            name: "Korunan"
        )
        let repository = FoodRepositoryStub(foods: [original])
        let viewModel = FoodLibraryViewModel(repository: repository)
        await viewModel.load()
        let validatedState = viewModel.state
        repository.mutationFails = true

        let createResult = await viewModel.create(try makeInput(name: "Eklenemez"))
        XCTAssertFalse(createResult)
        XCTAssertEqual(viewModel.state, validatedState)
        XCTAssertEqual(viewModel.mutationState, .saveError)

        viewModel.dismissMutationError()
        let updateResult = await viewModel.update(
            id: original.id,
            input: try makeInput(name: "Değişemez")
        )
        XCTAssertFalse(updateResult)
        XCTAssertEqual(viewModel.state, validatedState)
        XCTAssertEqual(viewModel.mutationState, .saveError)

        viewModel.dismissMutationError()
        let deleteResult = await viewModel.delete(id: original.id)
        XCTAssertFalse(deleteResult)
        XCTAssertEqual(viewModel.state, validatedState)
        XCTAssertEqual(viewModel.mutationState, .saveError)
        XCTAssertEqual(repository.foods, [original])

        viewModel.dismissMutationError()
        XCTAssertEqual(viewModel.mutationState, .idle)
    }

    private func makeInput(name: String) throws -> FoodInput {
        try FoodInput(
            name: name,
            brand: nil,
            servingSize: 100,
            servingUnit: "g",
            caloriesPerServing: 120,
            proteinG: 10,
            carbG: 15,
            fatG: 4,
            fiberG: nil
        )
    }

    private func makeSnapshot(id: UUID, name: String) throws -> FoodSnapshot {
        FoodSnapshot(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            name: name,
            brand: nil,
            servingSize: 100,
            servingUnit: "g",
            macros: try NutritionMacros(
                calories: 120,
                proteinG: 10,
                carbG: 15,
                fatG: 4
            ),
            fiberG: nil,
            source: .userCreated
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}

@MainActor
private final class FoodRepositoryStub: FoodLibraryRepository {
    private enum StubFailure: Error {
        case load
        case mutation
    }

    var foods: [FoodSnapshot]
    var loadFails = false
    var mutationFails = false
    private(set) var queries: [String] = []

    private let generatedID: UUID
    private var timestamp = Date(timeIntervalSinceReferenceDate: 200)

    init(
        foods: [FoodSnapshot],
        generatedID: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000399")!
    ) {
        self.foods = foods
        self.generatedID = generatedID
    }

    func fetchFoods(matching query: String) async throws -> [FoodSnapshot] {
        queries.append(query)
        if loadFails { throw StubFailure.load }
        if query.trimmingCharacters(in: .whitespacesAndNewlines) == "missing" {
            return []
        }
        return foods
    }

    func createFood(_ input: FoodInput) async throws -> FoodSnapshot {
        if mutationFails { throw StubFailure.mutation }
        let snapshot = FoodSnapshot(
            id: generatedID,
            createdAt: timestamp,
            updatedAt: timestamp,
            name: input.name,
            brand: input.brand,
            servingSize: input.servingSize,
            servingUnit: input.servingUnit,
            macros: input.macros,
            fiberG: input.fiberG,
            source: .userCreated
        )
        foods.append(snapshot)
        return snapshot
    }

    func updateFood(id: UUID, input: FoodInput) async throws -> FoodSnapshot {
        if mutationFails { throw StubFailure.mutation }
        guard let index = foods.firstIndex(where: { $0.id == id }) else {
            throw StubFailure.mutation
        }
        timestamp = timestamp.addingTimeInterval(1)
        let previous = foods[index]
        let snapshot = FoodSnapshot(
            id: previous.id,
            createdAt: previous.createdAt,
            updatedAt: timestamp,
            name: input.name,
            brand: input.brand,
            servingSize: input.servingSize,
            servingUnit: input.servingUnit,
            macros: input.macros,
            fiberG: input.fiberG,
            source: previous.source
        )
        foods[index] = snapshot
        return snapshot
    }

    func deleteFood(id: UUID) async throws {
        if mutationFails { throw StubFailure.mutation }
        guard let index = foods.firstIndex(where: { $0.id == id }) else {
            throw StubFailure.mutation
        }
        foods.remove(at: index)
    }
}
