import CoreModels
import Foundation
@testable import NutritionKit
import XCTest

@MainActor
final class RecipeLibraryViewModelTests: XCTestCase {
    func testLoadDistinguishesContentEmptySearchEmptyAndCategoryFilter() async throws {
        let active = try makeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000501"),
            name: "Kase",
            category: .breakfast
        )
        let archived = try makeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000502"),
            name: "Çorba",
            category: .dinner
        )
        let library = RecipeLibrarySnapshot(active: [active], archived: [archived])
        let repository = RecipeRepositoryStub(library: library)
        let viewModel = RecipeLibraryViewModel(repository: repository)

        XCTAssertEqual(viewModel.state, .loading)
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .content(library))

        await viewModel.search("missing")
        XCTAssertEqual(viewModel.state, .searchEmpty)

        await viewModel.search(" ")
        await viewModel.filter(by: .breakfast)
        XCTAssertEqual(
            viewModel.state,
            .content(RecipeLibrarySnapshot(active: [active], archived: []))
        )
        XCTAssertEqual(viewModel.categoryFilter, .breakfast)
        XCTAssertEqual(repository.requests.last?.category, .breakfast)

        repository.library = RecipeLibrarySnapshot(active: [], archived: [])
        await viewModel.filter(by: nil)
        XCTAssertEqual(viewModel.state, .empty)
        assertEquatableSendable(viewModel.state)
    }

    func testLoadErrorAndRetryAreRecoverable() async throws {
        let repository = RecipeRepositoryStub(
            library: RecipeLibrarySnapshot(active: [], archived: [])
        )
        repository.loadFails = true
        let viewModel = RecipeLibraryViewModel(repository: repository)

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .error)

        let recovered = try makeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000503"),
            name: "Kurtarılan",
            category: .lunch
        )
        repository.loadFails = false
        repository.library = RecipeLibrarySnapshot(active: [recovered], archived: [])
        await viewModel.retry()

        XCTAssertEqual(
            viewModel.state,
            .content(RecipeLibrarySnapshot(active: [recovered], archived: []))
        )
    }

    func testSuccessfulCreateUpdateArchiveAndRestoreRefreshCurrentRequest() async throws {
        let original = try makeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000504"),
            name: "Eski",
            category: .dinner
        )
        let createdID = uuid("00000000-0000-4000-8000-000000000505")
        let repository = RecipeRepositoryStub(
            library: RecipeLibrarySnapshot(active: [original], archived: []),
            generatedID: createdID
        )
        let viewModel = RecipeLibraryViewModel(repository: repository)
        await viewModel.search("aktif")

        let created = await viewModel.create(try makeInput(name: "Yeni"))
        XCTAssertTrue(created)
        XCTAssertEqual(viewModel.mutationState, .idle)
        XCTAssertEqual(repository.requests.last?.query, "aktif")
        XCTAssertEqual(repository.library.active.map(\.name), ["Eski", "Yeni"])

        let updated = await viewModel.update(
            id: createdID,
            input: try makeInput(name: "Güncel")
        )
        XCTAssertTrue(updated)
        XCTAssertEqual(repository.library.active.map(\.name), ["Eski", "Güncel"])

        let removed = await viewModel.remove(id: original.id)
        XCTAssertTrue(removed)
        XCTAssertEqual(repository.library.active.map(\.name), ["Güncel"])
        XCTAssertEqual(repository.library.archived.map(\.name), ["Eski"])

        let restored = await viewModel.restore(id: original.id)
        XCTAssertTrue(restored)
        XCTAssertEqual(repository.library.active.map(\.name), ["Güncel", "Eski"])
        XCTAssertTrue(repository.library.archived.isEmpty)
    }

    func testFailedMutationsPreserveValidatedLibraryAndExposeSaveError() async throws {
        let original = try makeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000506"),
            name: "Korunan",
            category: .snack
        )
        let archived = try makeSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000507"),
            name: "Arşivde",
            category: .dinner
        )
        let repository = RecipeRepositoryStub(
            library: RecipeLibrarySnapshot(active: [original], archived: [archived])
        )
        let viewModel = RecipeLibraryViewModel(repository: repository)
        await viewModel.load()
        let validatedState = viewModel.state
        repository.mutationFails = true

        let created = await viewModel.create(try makeInput(name: "Eklenemez"))
        XCTAssertFalse(created)
        XCTAssertEqual(viewModel.state, validatedState)
        XCTAssertEqual(viewModel.mutationState, .saveError)

        viewModel.dismissMutationError()
        let updated = await viewModel.update(
            id: original.id,
            input: try makeInput(name: "Değişemez")
        )
        XCTAssertFalse(updated)
        XCTAssertEqual(viewModel.state, validatedState)

        viewModel.dismissMutationError()
        let removed = await viewModel.remove(id: original.id)
        XCTAssertFalse(removed)
        XCTAssertEqual(viewModel.state, validatedState)

        viewModel.dismissMutationError()
        let restored = await viewModel.restore(id: archived.id)
        XCTAssertFalse(restored)
        XCTAssertEqual(viewModel.state, validatedState)
        XCTAssertEqual(repository.library.active, [original])
        XCTAssertEqual(repository.library.archived, [archived])

        viewModel.dismissMutationError()
        XCTAssertEqual(viewModel.mutationState, .idle)
    }

    private func makeInput(name: String) throws -> RecipeInput {
        try RecipeInput(
            name: name,
            category: MealCategory(kind: .dinner),
            servings: 2,
            caloriesTotal: 400,
            proteinTotalG: 30,
            carbTotalG: 40,
            fatTotalG: 12,
            note: nil
        )
    }

    private func makeSnapshot(
        id: UUID,
        name: String,
        category: MealCategory.Kind
    ) throws -> RecipeSnapshot {
        RecipeSnapshot(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            name: name,
            category: try MealCategory(kind: category),
            servings: 2,
            isDirectMacros: true,
            totalMacros: try NutritionMacros(
                calories: 400,
                proteinG: 30,
                carbG: 40,
                fatG: 12
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
private final class RecipeRepositoryStub: RecipeLibraryRepository {
    private enum StubFailure: Error {
        case load
        case mutation
    }

    struct Request {
        let query: String
        let category: MealCategory.Kind?
    }

    var library: RecipeLibrarySnapshot
    var loadFails = false
    var mutationFails = false
    private(set) var requests: [Request] = []

    private let generatedID: UUID
    private var timestamp = Date(timeIntervalSinceReferenceDate: 200)

    init(
        library: RecipeLibrarySnapshot,
        generatedID: UUID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000599"
        )!
    ) {
        self.library = library
        self.generatedID = generatedID
    }

    func fetchRecipeLibrary(
        matching query: String,
        category: MealCategory.Kind?
    ) async throws -> RecipeLibrarySnapshot {
        requests.append(Request(query: query, category: category))
        if loadFails { throw StubFailure.load }
        if query.trimmingCharacters(in: .whitespacesAndNewlines) == "missing" {
            return RecipeLibrarySnapshot(active: [], archived: [])
        }
        guard let category else { return library }
        return RecipeLibrarySnapshot(
            active: library.active.filter { $0.category.kind == category },
            archived: library.archived.filter { $0.category.kind == category }
        )
    }

    func createRecipe(_ input: RecipeInput) async throws -> RecipeSnapshot {
        if mutationFails { throw StubFailure.mutation }
        let snapshot = makeSnapshot(id: generatedID, input: input, createdAt: timestamp)
        library = RecipeLibrarySnapshot(
            active: library.active + [snapshot],
            archived: library.archived
        )
        return snapshot
    }

    func updateRecipe(id: UUID, input: RecipeInput) async throws -> RecipeSnapshot {
        if mutationFails { throw StubFailure.mutation }
        guard let index = library.active.firstIndex(where: { $0.id == id }) else {
            throw StubFailure.mutation
        }
        timestamp = timestamp.addingTimeInterval(1)
        let previous = library.active[index]
        let updated = makeSnapshot(
            id: previous.id,
            input: input,
            createdAt: previous.createdAt
        )
        var active = library.active
        active[index] = updated
        library = RecipeLibrarySnapshot(active: active, archived: library.archived)
        return updated
    }

    func removeRecipe(id: UUID) async throws -> RecipeRemovalResult {
        if mutationFails { throw StubFailure.mutation }
        guard let index = library.active.firstIndex(where: { $0.id == id }) else {
            throw StubFailure.mutation
        }
        var active = library.active
        let removed = active.remove(at: index)
        library = RecipeLibrarySnapshot(
            active: active,
            archived: library.archived + [removed]
        )
        return .archived
    }

    func restoreRecipe(id: UUID) async throws -> RecipeSnapshot {
        if mutationFails { throw StubFailure.mutation }
        guard let index = library.archived.firstIndex(where: { $0.id == id }) else {
            throw StubFailure.mutation
        }
        var archived = library.archived
        let restored = archived.remove(at: index)
        library = RecipeLibrarySnapshot(
            active: library.active + [restored],
            archived: archived
        )
        return restored
    }

    private func makeSnapshot(
        id: UUID,
        input: RecipeInput,
        createdAt: Date
    ) -> RecipeSnapshot {
        RecipeSnapshot(
            id: id,
            createdAt: createdAt,
            updatedAt: timestamp,
            name: input.name,
            category: input.category,
            servings: input.servings,
            isDirectMacros: true,
            totalMacros: input.totalMacros,
            note: input.note
        )
    }
}
