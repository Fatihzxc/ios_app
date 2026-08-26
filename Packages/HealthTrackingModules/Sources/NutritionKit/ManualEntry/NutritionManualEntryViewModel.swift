import CoreModels
import Foundation
import Observation

@MainActor
@Observable
public final class NutritionManualEntryViewModel {
    public private(set) var phase: NutritionManualEntryPhase = .idle
    public private(set) var mode: NutritionManualEntryMode?
    public private(set) var intent: NutritionQuickAddIntent?
    public private(set) var category: MealCategory?
    public private(set) var categoryOptions: [MealCategory] = []
    public private(set) var foods: [FoodSnapshot] = []
    public private(set) var selectedFood: FoodSnapshot?
    public private(set) var quantity: Decimal = 1
    public private(set) var requestID: UUID?
    public private(set) var targets: NutritionMacroTargets?

    @ObservationIgnored
    private let repository: any NutritionQuickAddRepository
    @ObservationIgnored
    private let foodRepository: any FoodLibraryRepository
    @ObservationIgnored
    private let calendar: Calendar
    @ObservationIgnored
    private let makeID: @MainActor () -> UUID
    @ObservationIgnored
    private var generation = 0
    @ObservationIgnored
    private var context: NutritionQuickAddContext?
    @ObservationIgnored
    private var pendingRequest: MealEntryCreateRequest?

    public init(
        repository: any NutritionQuickAddRepository,
        foodRepository: any FoodLibraryRepository,
        calendar: Calendar = .autoupdatingCurrent,
        makeID: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        self.repository = repository
        self.foodRepository = foodRepository
        self.calendar = calendar
        self.makeID = makeID
    }

    public func begin(
        mode: NutritionManualEntryMode,
        intent: NutritionQuickAddIntent
    ) async {
        generation &+= 1
        let loadGeneration = generation
        reset(mode: mode, intent: intent)
        phase = .loading

        do {
            guard try NutritionDayKey(
                containing: intent.day.start,
                calendar: calendar
            ) == intent.day else {
                throw NutritionManualEntryInternalError.invalidDay
            }
            let loadedContext = try await repository.fetchQuickAddContext(
                containing: intent.day.start
            )
            guard isCurrentLoad(
                generation: loadGeneration,
                mode: mode,
                intentID: intent.id
            ) else { return }
            guard loadedContext.daySnapshot.day == intent.day else {
                throw NutritionManualEntryInternalError.invalidContext
            }

            let loadedFoods: [FoodSnapshot]
            if mode == .food {
                loadedFoods = try await foodRepository.fetchFoods(matching: "")
            } else {
                loadedFoods = []
            }
            guard isCurrentLoad(
                generation: loadGeneration,
                mode: mode,
                intentID: intent.id
            ) else { return }
            guard Set(loadedFoods.map(\.id)).count == loadedFoods.count else {
                throw NutritionManualEntryInternalError.invalidFoods
            }

            context = loadedContext
            targets = loadedContext.targets
            foods = FoodSearch.results(
                loadedFoods.filter { $0.source == .userCreated },
                matching: ""
            )
            phase = mode == .food ? .foodSelection : .adhocEntry
        } catch {
            guard isCurrentLoad(
                generation: loadGeneration,
                mode: mode,
                intentID: intent.id
            ) else { return }
            phase = .loadError
        }
    }

    public func retryLoad() async {
        guard phase == .loadError, let mode, let intent else { return }
        await begin(mode: mode, intent: intent)
    }

    public func selectCategory(_ category: MealCategory) {
        guard phase == .foodSelection
                || phase == .foodConfirmation
                || phase == .adhocEntry else { return }
        self.category = category
        if !categoryOptions.contains(category) {
            categoryOptions = Self.categoryOptions(current: category)
        }
    }

    public func selectFood(id: UUID) {
        guard phase == .foodSelection,
              let food = foods.first(where: { $0.id == id }) else { return }
        selectedFood = food
        quantity = 1
        requestID = makeID()
        pendingRequest = nil
        phase = .foodConfirmation
    }

    public func returnToFoods() {
        guard phase == .foodConfirmation else { return }
        selectedFood = nil
        quantity = 1
        requestID = nil
        pendingRequest = nil
        phase = .foodSelection
    }

    public func setQuantity(_ value: Decimal) throws {
        guard phase == .foodConfirmation else { return }
        quantity = try NutritionQuantity(value).value
    }

    public func saveFood(
        onPublish: @escaping @MainActor (
            NutritionDayEntriesSnapshot,
            NutritionMacroTargets?
        ) -> Void
    ) async {
        guard phase == .foodConfirmation,
              let intent,
              let category,
              let selectedFood,
              let requestID else { return }
        do {
            let request = try MealEntryCreateRequest(
                requestID: requestID,
                date: intent.day.start,
                category: category,
                source: .food(id: selectedFood.id, quantity: quantity)
            )
            pendingRequest = request
            await performSave(request, onPublish: onPublish)
        } catch {
            return
        }
    }

    public func saveAdhoc(
        name: String,
        quantity: Decimal,
        resolvedMacros: NutritionMacros,
        onPublish: @escaping @MainActor (
            NutritionDayEntriesSnapshot,
            NutritionMacroTargets?
        ) -> Void
    ) async {
        guard phase == .adhocEntry,
              let intent,
              let category else { return }
        let requestID = self.requestID ?? makeID()
        do {
            let request = try MealEntryCreateRequest(
                requestID: requestID,
                date: intent.day.start,
                category: category,
                source: .adhoc(
                    name: name,
                    quantity: quantity,
                    resolvedMacros: resolvedMacros
                )
            )
            self.requestID = requestID
            self.quantity = quantity
            pendingRequest = request
            await performSave(request, onPublish: onPublish)
        } catch {
            return
        }
    }

    public func retrySave(
        onPublish: @escaping @MainActor (
            NutritionDayEntriesSnapshot,
            NutritionMacroTargets?
        ) -> Void
    ) async {
        guard phase == .saveError, let pendingRequest else { return }
        await performSave(pendingRequest, onPublish: onPublish)
    }

    public func dismiss() {
        generation &+= 1
        phase = .idle
        mode = nil
        intent = nil
        category = nil
        categoryOptions = []
        foods = []
        selectedFood = nil
        quantity = 1
        requestID = nil
        targets = nil
        context = nil
        pendingRequest = nil
    }

    private func performSave(
        _ request: MealEntryCreateRequest,
        onPublish: @escaping @MainActor (
            NutritionDayEntriesSnapshot,
            NutritionMacroTargets?
        ) -> Void
    ) async {
        guard let intent,
              let context,
              context.daySnapshot.day == intent.day,
              request.requestID == requestID else { return }
        let saveGeneration = generation
        let intentID = intent.id
        phase = .saving

        do {
            let canonical = try await repository.createMealEntry(request)
            guard isCurrentSave(
                generation: saveGeneration,
                intentID: intentID,
                requestID: request.requestID
            ) else { return }
            guard canonical.day == intent.day,
                  canonical.entries.contains(where: { $0.id == request.requestID }) else {
                throw NutritionManualEntryInternalError.invalidMutationResponse
            }
            onPublish(canonical, targets)
            phase = .completed
        } catch {
            guard isCurrentSave(
                generation: saveGeneration,
                intentID: intentID,
                requestID: request.requestID
            ) else { return }
            phase = .saveError
        }
    }

    private func reset(
        mode: NutritionManualEntryMode,
        intent: NutritionQuickAddIntent
    ) {
        self.mode = mode
        self.intent = intent
        category = intent.category
        categoryOptions = Self.categoryOptions(current: intent.category)
        foods = []
        selectedFood = nil
        quantity = 1
        requestID = nil
        targets = nil
        context = nil
        pendingRequest = nil
    }

    private func isCurrentLoad(
        generation: Int,
        mode: NutritionManualEntryMode,
        intentID: UUID
    ) -> Bool {
        self.generation == generation
            && self.mode == mode
            && intent?.id == intentID
            && phase == .loading
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

    private static func categoryOptions(current: MealCategory) -> [MealCategory] {
        let standard = MealCategory.Kind.allCases.compactMap { kind -> MealCategory? in
            guard kind != .custom else { return nil }
            return try? MealCategory(kind: kind)
        }
        if current.kind == .custom { return standard + [current] }
        return standard
    }
}

private enum NutritionManualEntryInternalError: Error {
    case invalidDay
    case invalidContext
    case invalidFoods
    case invalidMutationResponse
}
