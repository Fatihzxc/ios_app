import CoreModels
import Foundation
import Observation

@MainActor
@Observable
public final class NutritionQuickAddViewModel {
    public private(set) var phase: NutritionQuickAddPhase = .idle
    public private(set) var intent: NutritionQuickAddIntent?
    public private(set) var category: MealCategory?
    public private(set) var categoryOptions: [MealCategory] = []
    public private(set) var recipes: [RecipeSnapshot] = []
    public private(set) var selectedRecipe: RecipeSnapshot?
    public private(set) var quantity: Decimal = 1
    public private(set) var requestID: UUID?
    public private(set) var projectedSnapshot: NutritionDayEntriesSnapshot?
    public private(set) var targets: NutritionMacroTargets?

    @ObservationIgnored
    private let repository: any NutritionQuickAddRepository
    @ObservationIgnored
    private let calendar: Calendar
    @ObservationIgnored
    private let makeID: @MainActor () -> UUID
    @ObservationIgnored
    private let now: @MainActor () -> Date
    @ObservationIgnored
    private var generation = 0
    @ObservationIgnored
    private var context: NutritionQuickAddContext?

    public init(
        repository: any NutritionQuickAddRepository,
        calendar: Calendar = .autoupdatingCurrent,
        makeID: @escaping @MainActor () -> UUID = { UUID() },
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.makeID = makeID
        self.now = now
    }

    public func begin(_ intent: NutritionQuickAddIntent) async {
        generation &+= 1
        let loadGeneration = generation
        self.intent = intent
        category = intent.category
        categoryOptions = []
        recipes = []
        selectedRecipe = nil
        quantity = 1
        requestID = nil
        projectedSnapshot = nil
        targets = nil
        context = nil
        phase = .loading

        do {
            guard try NutritionDayKey(
                containing: intent.day.start,
                calendar: calendar
            ) == intent.day else {
                throw NutritionQuickAddInternalError.invalidDay
            }
            let loaded = try await repository.fetchQuickAddContext(
                containing: intent.day.start
            )
            guard generation == loadGeneration, self.intent == intent else { return }
            guard loaded.daySnapshot.day == intent.day,
                  Set(loaded.activeRecipes.map(\.id)).count == loaded.activeRecipes.count else {
                throw NutritionQuickAddInternalError.invalidContext
            }
            context = loaded
            targets = loaded.targets
            projectedSnapshot = loaded.daySnapshot
            categoryOptions = Self.categoryOptions(
                activeRecipes: loaded.activeRecipes,
                current: intent.category
            )
            recipes = FrequentRecipeRanking.recipes(
                active: loaded.activeRecipes,
                usage: loaded.usage,
                category: intent.category
            )
            phase = .selecting
        } catch {
            guard generation == loadGeneration, self.intent == intent else { return }
            phase = .loadError
        }
    }

    public func retryLoad() async {
        guard phase == .loadError, let intent else { return }
        await begin(intent)
    }

    public func selectCategory(_ category: MealCategory) {
        guard phase == .selecting || phase == .confirming,
              let context else { return }
        self.category = category
        if !categoryOptions.contains(category) {
            categoryOptions = Self.categoryOptions(
                activeRecipes: context.activeRecipes,
                current: category
            )
        }
        recipes = FrequentRecipeRanking.recipes(
            active: context.activeRecipes,
            usage: context.usage,
            category: category
        )
    }

    public func selectRecipe(id: UUID) {
        guard phase == .selecting,
              let recipe = recipes.first(where: { $0.id == id }) else { return }
        selectedRecipe = recipe
        quantity = 1
        requestID = makeID()
        phase = .confirming
    }

    public func setQuantity(_ value: Decimal) throws {
        guard phase == .confirming else { return }
        quantity = try NutritionQuantity(value).value
    }

    public func returnToRecipes() {
        guard phase == .confirming else { return }
        selectedRecipe = nil
        quantity = 1
        requestID = nil
        phase = .selecting
    }

    public func confirm(
        onPublish: @escaping @MainActor (
            NutritionDayEntriesSnapshot,
            NutritionMacroTargets?
        ) -> Void
    ) async {
        guard phase == .confirming else { return }
        await performSave(onPublish: onPublish)
    }

    public func retrySave(
        onPublish: @escaping @MainActor (
            NutritionDayEntriesSnapshot,
            NutritionMacroTargets?
        ) -> Void
    ) async {
        guard phase == .saveError else { return }
        await performSave(onPublish: onPublish)
    }

    public func dismiss() {
        generation &+= 1
        phase = .idle
        intent = nil
        category = nil
        categoryOptions = []
        recipes = []
        selectedRecipe = nil
        quantity = 1
        requestID = nil
        projectedSnapshot = nil
        targets = nil
        context = nil
    }

    private func performSave(
        onPublish: @escaping @MainActor (
            NutritionDayEntriesSnapshot,
            NutritionMacroTargets?
        ) -> Void
    ) async {
        guard let intent,
              let category,
              let selectedRecipe,
              let requestID,
              let context,
              context.daySnapshot.day == intent.day else { return }

        let saveGeneration = generation
        let original = context.daySnapshot
        phase = .saving
        do {
            let request = try MealEntryCreateRequest(
                requestID: requestID,
                date: intent.day.start,
                category: category,
                source: .recipe(id: selectedRecipe.id, consumedServings: quantity)
            )
            let resolvedMacros = try selectedRecipe.resolvedMacros(
                consumedServings: quantity
            )
            let timestamp = now()
            let optimisticEntry = MealEntrySnapshot(
                id: requestID,
                createdAt: timestamp,
                updatedAt: timestamp,
                category: category,
                source: .recipe(id: selectedRecipe.id, name: selectedRecipe.name),
                quantity: quantity,
                resolvedMacros: resolvedMacros,
                loggedAt: timestamp,
                nutritionDayID: original.log?.id ?? requestID
            )
            let optimistic = try NutritionDayEntriesSnapshot(
                day: original.day,
                log: original.log,
                entries: original.entries.filter { $0.id != requestID } + [optimisticEntry]
            )
            projectedSnapshot = optimistic
            onPublish(optimistic, targets)

            let canonical = try await repository.createMealEntry(request)
            guard isCurrentSave(
                generation: saveGeneration,
                intentID: intent.id,
                requestID: requestID
            ) else { return }
            guard canonical.day == intent.day,
                  canonical.entries.contains(where: { $0.id == requestID }) else {
                throw NutritionQuickAddInternalError.invalidMutationResponse
            }
            self.context = NutritionQuickAddContext(
                daySnapshot: canonical,
                targets: context.targets,
                activeRecipes: context.activeRecipes,
                usage: context.usage
            )
            projectedSnapshot = canonical
            onPublish(canonical, targets)
            phase = .completed
        } catch {
            guard isCurrentSave(
                generation: saveGeneration,
                intentID: intent.id,
                requestID: requestID
            ) else { return }
            projectedSnapshot = original
            onPublish(original, targets)
            phase = .saveError
        }
    }

    private func isCurrentSave(
        generation: Int,
        intentID: UUID,
        requestID: UUID
    ) -> Bool {
        self.generation == generation
            && intent?.id == intentID
            && self.requestID == requestID
            && phase == .saving
    }

    private static func categoryOptions(
        activeRecipes: [RecipeSnapshot],
        current: MealCategory
    ) -> [MealCategory] {
        let standard = MealCategory.Kind.allCases.compactMap { kind -> MealCategory? in
            guard kind != .custom else { return nil }
            return try? MealCategory(kind: kind)
        }
        let custom = Set(
            activeRecipes.map(\.category).filter { $0.kind == .custom }
                + (current.kind == .custom ? [current] : [])
        ).sorted { lhs, rhs in
            let left = FoodSearch.normalized(lhs.customName ?? "")
            let right = FoodSearch.normalized(rhs.customName ?? "")
            if left != right { return left < right }
            return (lhs.customName ?? "") < (rhs.customName ?? "")
        }
        return standard + custom
    }
}

private enum NutritionQuickAddInternalError: Error {
    case invalidDay
    case invalidContext
    case invalidMutationResponse
}
