import CoreModels
import Foundation
import Observation

public enum NutritionQuickAddState: Equatable, Sendable {
    case loading
    case recipes
    case confirmation
    case saving
    case saveError
    case saved
    case empty
    case loadError
}

@MainActor
@Observable
public final class NutritionQuickAddViewModel {
    public private(set) var state: NutritionQuickAddState = .loading
    public private(set) var category: MealCategory
    public private(set) var recipes: [RecipeSnapshot] = []
    public private(set) var selectedRecipe: RecipeSnapshot?
    public private(set) var quantity: Decimal = 1
    public private(set) var requestID: UUID?

    public let day: NutritionDayKey

    @ObservationIgnored
    private let repository: any NutritionQuickAddRepository
    @ObservationIgnored
    private let makeRequestID: @MainActor () -> UUID
    @ObservationIgnored
    private let now: @MainActor () -> Date
    @ObservationIgnored
    private let onSnapshotChange: @MainActor (NutritionDayEntriesSnapshot) -> Void
    @ObservationIgnored
    private var baselineSnapshot: NutritionDayEntriesSnapshot?

    public init(
        repository: any NutritionQuickAddRepository,
        day: NutritionDayKey,
        initialCategory: MealCategory,
        makeRequestID: @escaping @MainActor () -> UUID = UUID.init,
        now: @escaping @MainActor () -> Date = { .now },
        onSnapshotChange: @escaping @MainActor (
            NutritionDayEntriesSnapshot
        ) -> Void = { _ in }
    ) {
        self.repository = repository
        self.day = day
        category = initialCategory
        self.makeRequestID = makeRequestID
        self.now = now
        self.onSnapshotChange = onSnapshotChange
    }

    public func load() async {
        state = .loading
        do {
            let snapshot = try await repository.fetchMealEntries(
                containing: day.start
            )
            guard snapshot.day == day else {
                state = .loadError
                return
            }
            let recipes = try await repository.fetchQuickAddRecipes(
                for: category
            )
            baselineSnapshot = snapshot
            self.recipes = recipes
            state = recipes.isEmpty ? .empty : .recipes
        } catch {
            state = .loadError
        }
    }

    public func retryLoad() async {
        await load()
    }

    public func selectRecipe(id: UUID) {
        guard let recipe = recipes.first(where: { $0.id == id }) else { return }
        selectedRecipe = recipe
        quantity = 1
        requestID = nil
        state = .confirmation
    }

    public func updateCategory(_ category: MealCategory) {
        guard state == .confirmation || state == .empty else { return }
        self.category = category
    }

    public func updateQuantity(_ quantity: Decimal) throws {
        guard state == .confirmation else { return }
        self.quantity = try NutritionQuantity(quantity).value
    }

    public func confirm() async {
        guard state == .confirmation || state == .saveError,
              let selectedRecipe,
              let baselineSnapshot else {
            return
        }

        let requestID = self.requestID ?? makeRequestID()
        self.requestID = requestID
        let timestamp = now()

        do {
            let resolvedMacros = try selectedRecipe.resolvedMacros(
                consumedServings: quantity
            )
            let request = try MealEntryCreateRequest(
                requestID: requestID,
                date: day.start,
                category: category,
                source: .recipe(
                    id: selectedRecipe.id,
                    consumedServings: quantity
                )
            )
            let optimisticEntry = MealEntrySnapshot(
                id: requestID,
                createdAt: timestamp,
                updatedAt: timestamp,
                category: category,
                source: .recipe(
                    id: selectedRecipe.id,
                    name: selectedRecipe.name
                ),
                quantity: quantity,
                resolvedMacros: resolvedMacros,
                loggedAt: timestamp,
                nutritionDayID: baselineSnapshot.log?.id ?? requestID
            )
            let optimisticSnapshot = try NutritionDayEntriesSnapshot(
                day: day,
                log: baselineSnapshot.log,
                entries: baselineSnapshot.entries + [optimisticEntry]
            )

            state = .saving
            onSnapshotChange(optimisticSnapshot)

            do {
                let canonical = try await repository.createMealEntry(request)
                guard canonical.day == day else { throw QuickAddSnapshotError.wrongDay }
                self.baselineSnapshot = canonical
                onSnapshotChange(canonical)
                state = .saved
            } catch {
                onSnapshotChange(baselineSnapshot)
                state = .saveError
            }
        } catch {
            onSnapshotChange(baselineSnapshot)
            state = .saveError
        }
    }

    public func retrySave() async {
        guard state == .saveError else { return }
        await confirm()
    }
}

private enum QuickAddSnapshotError: Error {
    case wrongDay
}
