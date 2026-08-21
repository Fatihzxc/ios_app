import Foundation
import Observation

public enum FoodLibraryViewState: Equatable, Sendable {
    case loading
    case content([FoodSnapshot])
    case empty
    case searchEmpty
    case error
}

public enum FoodLibraryMutationState: Equatable, Sendable {
    case idle
    case saving
    case saveError
}

@MainActor
@Observable
public final class FoodLibraryViewModel {
    public private(set) var state: FoodLibraryViewState = .loading
    public private(set) var mutationState: FoodLibraryMutationState = .idle
    public private(set) var query = ""

    @ObservationIgnored
    private let repository: any FoodLibraryRepository

    public init(repository: any FoodLibraryRepository) {
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

    @discardableResult
    public func create(_ input: FoodInput) async -> Bool {
        mutationState = .saving
        do {
            _ = try await repository.createFood(input)
            mutationState = .idle
            await refresh()
            return true
        } catch {
            mutationState = .saveError
            return false
        }
    }

    @discardableResult
    public func update(id: UUID, input: FoodInput) async -> Bool {
        mutationState = .saving
        do {
            _ = try await repository.updateFood(id: id, input: input)
            mutationState = .idle
            await refresh()
            return true
        } catch {
            mutationState = .saveError
            return false
        }
    }

    @discardableResult
    public func delete(id: UUID) async -> Bool {
        mutationState = .saving
        do {
            try await repository.deleteFood(id: id)
            mutationState = .idle
            await refresh()
            return true
        } catch {
            mutationState = .saveError
            return false
        }
    }

    public func dismissMutationError() {
        if mutationState == .saveError {
            mutationState = .idle
        }
    }

    private func refresh() async {
        do {
            let foods = try await repository.fetchFoods(matching: query)
            if foods.isEmpty {
                state = FoodSearch.normalized(query).isEmpty ? .empty : .searchEmpty
            } else {
                state = .content(foods)
            }
        } catch {
            state = .error
        }
    }
}
