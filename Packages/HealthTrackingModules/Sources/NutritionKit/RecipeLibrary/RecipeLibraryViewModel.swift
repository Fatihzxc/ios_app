import CoreModels
import Foundation
import Observation

public enum RecipeLibraryViewState: Equatable, Sendable {
    case loading
    case content(RecipeLibrarySnapshot)
    case empty
    case searchEmpty
    case error
}

public enum RecipeLibraryMutationState: Equatable, Sendable {
    case idle
    case saving
    case saveError
}

@MainActor
@Observable
public final class RecipeLibraryViewModel {
    public private(set) var state: RecipeLibraryViewState = .loading
    public private(set) var mutationState: RecipeLibraryMutationState = .idle
    public private(set) var query = ""
    public private(set) var categoryFilter: MealCategory.Kind?

    @ObservationIgnored
    private let repository: any RecipeLibraryRepository

    public init(repository: any RecipeLibraryRepository) {
        self.repository = repository
    }

    public func load() async {
        state = .loading
        await refresh()
    }

    public func retry() async {
        await load()
    }

    public func search(_ query: String) async {
        self.query = query
        await refresh()
    }

    public func filter(by category: MealCategory.Kind?) async {
        categoryFilter = category
        await refresh()
    }

    @discardableResult
    public func create(_ input: RecipeInput) async -> Bool {
        await mutate {
            _ = try await repository.createRecipe(input)
        }
    }

    @discardableResult
    public func update(id: UUID, input: RecipeInput) async -> Bool {
        await mutate {
            _ = try await repository.updateRecipe(id: id, input: input)
        }
    }

    @discardableResult
    public func remove(id: UUID) async -> Bool {
        await mutate {
            _ = try await repository.removeRecipe(id: id)
        }
    }

    @discardableResult
    public func restore(id: UUID) async -> Bool {
        await mutate {
            _ = try await repository.restoreRecipe(id: id)
        }
    }

    public func dismissMutationError() {
        if mutationState == .saveError {
            mutationState = .idle
        }
    }

    private func mutate(
        _ operation: @MainActor () async throws -> Void
    ) async -> Bool {
        mutationState = .saving
        do {
            try await operation()
            mutationState = .idle
            await refresh()
            return true
        } catch {
            mutationState = .saveError
            return false
        }
    }

    private func refresh() async {
        do {
            let library = try await repository.fetchRecipeLibrary(
                matching: query,
                category: categoryFilter
            )
            if library.active.isEmpty, library.archived.isEmpty {
                state = FoodSearch.normalized(query).isEmpty
                    && categoryFilter == nil
                    ? .empty
                    : .searchEmpty
            } else {
                state = .content(library)
            }
        } catch {
            state = .error
        }
    }
}
