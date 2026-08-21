import CoreModels
import Foundation
import NutritionKit
import SwiftData

public enum NutritionPersistenceDecimalError: Error, Equatable, Sendable {
    case nonFinite(NutritionMacroField)
    case negative(NutritionMacroField)
    case notRepresentable(NutritionMacroField)
}

enum NutritionPersistenceDecimalMapper {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func decimal(
        from value: Double,
        field: NutritionMacroField
    ) throws -> Decimal {
        guard value.isFinite else {
            throw NutritionPersistenceDecimalError.nonFinite(field)
        }
        guard value >= 0 else {
            throw NutritionPersistenceDecimalError.negative(field)
        }
        guard let result = Decimal(string: String(value), locale: posix),
              result.isFinite else {
            throw NutritionPersistenceDecimalError.notRepresentable(field)
        }
        return result
    }

    static func target(
        from value: Double?,
        field: NutritionMacroField
    ) throws -> Decimal? {
        guard let value, value != 0 else { return nil }
        return try decimal(from: value, field: field)
    }

    static func double(
        from value: Decimal,
        field: NutritionMacroField
    ) throws -> Double {
        guard value.isFinite else {
            throw NutritionPersistenceDecimalError.nonFinite(field)
        }
        guard value >= 0 else {
            throw NutritionPersistenceDecimalError.negative(field)
        }
        let decimalString = NSDecimalNumber(decimal: value).stringValue
        guard let result = Double(decimalString) else {
            throw NutritionPersistenceDecimalError.notRepresentable(field)
        }
        guard result.isFinite,
              value == 0 || result != 0 else {
            throw NutritionPersistenceDecimalError.notRepresentable(field)
        }
        guard let roundTrip = Decimal(string: String(result), locale: posix),
              roundTrip.isFinite,
              roundTrip >= 0,
              roundTrip == value else {
            throw NutritionPersistenceDecimalError.notRepresentable(field)
        }
        return result
    }
}

private enum FoodPersistenceValueError: Error {
    case notRepresentable
}

private enum FoodPersistenceValueMapper {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func decimal(from value: Double) throws -> Decimal {
        guard value.isFinite,
              let result = Decimal(string: String(value), locale: posix),
              result.isFinite else {
            throw FoodPersistenceValueError.notRepresentable
        }
        return result
    }

    static func double(from value: Decimal) throws -> Double {
        guard value.isFinite else {
            throw FoodPersistenceValueError.notRepresentable
        }
        let decimalString = NSDecimalNumber(decimal: value).stringValue
        guard let result = Double(decimalString),
              result.isFinite,
              value == 0 || result != 0,
              let roundTrip = Decimal(string: String(result), locale: posix),
              roundTrip == value else {
            throw FoodPersistenceValueError.notRepresentable
        }
        return result
    }
}

private struct FoodPersistenceValues {
    let servingSize: Double
    let calories: Double
    let proteinG: Double
    let carbG: Double
    let fatG: Double
    let fiberG: Double?
}

private enum RecipePersistenceValueError: Error {
    case notRepresentable
}

private enum RecipePersistenceValueMapper {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func decimal(from value: Double) throws -> Decimal {
        guard value.isFinite,
              let result = Decimal(string: String(value), locale: posix),
              result.isFinite else {
            throw RecipePersistenceValueError.notRepresentable
        }
        return result
    }

    static func double(from value: Decimal) throws -> Double {
        guard value.isFinite else {
            throw RecipePersistenceValueError.notRepresentable
        }
        let decimalString = NSDecimalNumber(decimal: value).stringValue
        guard let result = Double(decimalString),
              result.isFinite,
              value == 0 || result != 0,
              let roundTrip = Decimal(string: String(result), locale: posix),
              roundTrip == value else {
            throw RecipePersistenceValueError.notRepresentable
        }
        return result
    }
}

private struct RecipePersistenceValues {
    let servings: Double
    let calories: Double
    let proteinG: Double
    let carbG: Double
    let fatG: Double
}

@MainActor
public final class SwiftDataNutritionRepository:
    NutritionDayRepository,
    FoodLibraryRepository,
    RecipeLibraryRepository {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let now: @MainActor () -> Date
    private let makeID: @MainActor () -> UUID
    private let fetchDaysOperation: @MainActor (
        FetchDescriptor<DailyNutritionLog>
    ) throws -> [DailyNutritionLog]
    private let fetchEntriesOperation: @MainActor (
        FetchDescriptor<MealEntry>
    ) throws -> [MealEntry]
    private let fetchProfilesOperation: @MainActor (
        FetchDescriptor<UserProfile>
    ) throws -> [UserProfile]
    private let fetchFoodsOperation: @MainActor (
        FetchDescriptor<Food>
    ) throws -> [Food]
    private let fetchRecipesOperation: @MainActor (
        FetchDescriptor<Recipe>
    ) throws -> [Recipe]
    private let fetchSettingsOperation: @MainActor (
        FetchDescriptor<AppSetting>
    ) throws -> [AppSetting]
    private let saveOperation: @MainActor () throws -> Void
    private let rollbackOperation: @MainActor () -> Void

    public init(
        modelContext: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @MainActor () -> Date = { .now },
        makeID: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
        fetchDaysOperation = { try modelContext.fetch($0) }
        fetchEntriesOperation = { try modelContext.fetch($0) }
        fetchProfilesOperation = { try modelContext.fetch($0) }
        fetchFoodsOperation = { try modelContext.fetch($0) }
        fetchRecipesOperation = { try modelContext.fetch($0) }
        fetchSettingsOperation = { try modelContext.fetch($0) }
        saveOperation = { try modelContext.save() }
        rollbackOperation = { modelContext.rollback() }
    }

    init(
        modelContext: ModelContext,
        calendar: Calendar,
        now: @escaping @MainActor () -> Date,
        makeID: @escaping @MainActor () -> UUID,
        save: @escaping @MainActor () throws -> Void,
        rollback: @escaping @MainActor () -> Void
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
        fetchDaysOperation = { try modelContext.fetch($0) }
        fetchEntriesOperation = { try modelContext.fetch($0) }
        fetchProfilesOperation = { try modelContext.fetch($0) }
        fetchFoodsOperation = { try modelContext.fetch($0) }
        fetchRecipesOperation = { try modelContext.fetch($0) }
        fetchSettingsOperation = { try modelContext.fetch($0) }
        saveOperation = save
        rollbackOperation = rollback
    }

    init(
        modelContext: ModelContext,
        calendar: Calendar,
        now: @escaping @MainActor () -> Date,
        makeID: @escaping @MainActor () -> UUID,
        fetchProfiles: @escaping @MainActor (
            FetchDescriptor<UserProfile>
        ) throws -> [UserProfile],
        save: @escaping @MainActor () throws -> Void,
        rollback: @escaping @MainActor () -> Void
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
        fetchDaysOperation = { try modelContext.fetch($0) }
        fetchEntriesOperation = { try modelContext.fetch($0) }
        fetchProfilesOperation = fetchProfiles
        fetchFoodsOperation = { try modelContext.fetch($0) }
        fetchRecipesOperation = { try modelContext.fetch($0) }
        fetchSettingsOperation = { try modelContext.fetch($0) }
        saveOperation = save
        rollbackOperation = rollback
    }

    init(
        modelContext: ModelContext,
        calendar: Calendar,
        now: @escaping @MainActor () -> Date,
        makeID: @escaping @MainActor () -> UUID,
        fetchDays: @escaping @MainActor (
            FetchDescriptor<DailyNutritionLog>
        ) throws -> [DailyNutritionLog],
        fetchEntries: @escaping @MainActor (
            FetchDescriptor<MealEntry>
        ) throws -> [MealEntry],
        save: @escaping @MainActor () throws -> Void,
        rollback: @escaping @MainActor () -> Void
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
        fetchDaysOperation = fetchDays
        fetchEntriesOperation = fetchEntries
        fetchProfilesOperation = { try modelContext.fetch($0) }
        fetchFoodsOperation = { try modelContext.fetch($0) }
        fetchRecipesOperation = { try modelContext.fetch($0) }
        fetchSettingsOperation = { try modelContext.fetch($0) }
        saveOperation = save
        rollbackOperation = rollback
    }

    public func fetchNutritionTargets() async throws -> NutritionMacroTargets? {
        let profiles = try fetchProfiles(FetchDescriptor<UserProfile>())
        guard profiles.count <= 1 else {
            throw NutritionRepositoryIntegrityError.duplicateUserProfiles(
                count: profiles.count
            )
        }
        guard let profile = profiles.first else { return nil }
        return NutritionMacroTargets(
            calories: try NutritionPersistenceDecimalMapper.target(
                from: profile.calorieTarget,
                field: .calories
            ),
            proteinG: try NutritionPersistenceDecimalMapper.target(
                from: profile.proteinTargetG,
                field: .proteinG
            ),
            carbG: try NutritionPersistenceDecimalMapper.target(
                from: profile.carbTargetG,
                field: .carbG
            ),
            fatG: try NutritionPersistenceDecimalMapper.target(
                from: profile.fatTargetG,
                field: .fatG
            )
        )
    }

    public func fetchFoods(matching query: String) async throws -> [FoodSnapshot] {
        let foods = try fetchFoodModels(FetchDescriptor<Food>())
        try validateUniqueFoodIDs(foods)
        return FoodSearch.results(
            try foods.map(foodSnapshot),
            matching: query
        )
    }

    public func createFood(_ input: FoodInput) async throws -> FoodSnapshot {
        let id = makeID()
        guard try matchingFoods(id: id).isEmpty else {
            throw FoodRepositoryIntegrityError.foodIDCollision(id: id)
        }
        let values = try persistenceValues(input)
        let timestamp = now()
        let food = Food(
            id: id,
            createdAt: timestamp,
            updatedAt: timestamp,
            name: input.name,
            brand: input.brand,
            servingSize: values.servingSize,
            servingUnit: input.servingUnit,
            caloriesPerServing: values.calories,
            proteinG: values.proteinG,
            carbG: values.carbG,
            fatG: values.fatG,
            fiberG: values.fiberG,
            source: .userCreated
        )
        modelContext.insert(food)
        try saveMutation(or: .saveFailed)
        return try foodSnapshot(food)
    }

    public func updateFood(
        id: UUID,
        input: FoodInput
    ) async throws -> FoodSnapshot {
        let matches = try matchingFoods(id: id)
        guard !matches.isEmpty else {
            throw FoodRepositoryMutationError.foodNotFound(id: id)
        }
        guard matches.count == 1, let food = matches.first else {
            throw FoodRepositoryIntegrityError.duplicateFoodIDs(
                id: id,
                count: matches.count
            )
        }
        guard food.source == .userCreated else {
            throw FoodRepositoryMutationError.unsupportedMutationSource(
                id: id,
                source: food.source
            )
        }

        let values = try persistenceValues(input)
        food.name = input.name
        food.brand = input.brand
        food.servingSize = values.servingSize
        food.servingUnit = input.servingUnit
        food.caloriesPerServing = values.calories
        food.proteinG = values.proteinG
        food.carbG = values.carbG
        food.fatG = values.fatG
        food.fiberG = values.fiberG
        food.updatedAt = now()
        try saveMutation(or: .saveFailed)
        return try foodSnapshot(food)
    }

    public func deleteFood(id: UUID) async throws {
        let matches = try matchingFoods(id: id)
        guard !matches.isEmpty else {
            throw FoodRepositoryMutationError.foodNotFound(id: id)
        }
        guard matches.count == 1, let food = matches.first else {
            throw FoodRepositoryIntegrityError.duplicateFoodIDs(
                id: id,
                count: matches.count
            )
        }
        guard food.source == .userCreated else {
            throw FoodRepositoryMutationError.unsupportedMutationSource(
                id: id,
                source: food.source
            )
        }
        modelContext.delete(food)
        try saveMutation(or: .deleteFailed)
    }

    public func fetchRecipeLibrary(
        matching query: String,
        category: MealCategory.Kind?
    ) async throws -> RecipeLibrarySnapshot {
        let recipes = try fetchRecipeModels(FetchDescriptor<Recipe>())
        try validateUniqueRecipeIDs(recipes)
        let archive = try archiveState()
        let persistedIDs = Set(recipes.map(\.id))
        if let missingID = archive.ids
            .subtracting(persistedIDs)
            .sorted(by: { $0.uuidString < $1.uuidString })
            .first {
            throw RecipeRepositoryIntegrityError.archivedRecipeMissing(id: missingID)
        }

        var active: [RecipeSnapshot] = []
        var archived: [RecipeSnapshot] = []
        for recipe in recipes {
            let snapshot = try recipeSnapshot(recipe)
            if archive.ids.contains(recipe.id) {
                archived.append(snapshot)
            } else {
                active.append(snapshot)
            }
        }
        return RecipeSearch.library(
            active: active,
            archived: archived,
            matching: query,
            category: category
        )
    }

    public func createRecipe(
        _ input: RecipeInput
    ) async throws -> RecipeSnapshot {
        let id = makeID()
        guard try matchingRecipes(id: id).isEmpty else {
            throw RecipeRepositoryIntegrityError.recipeIDCollision(id: id)
        }
        let values = try recipePersistenceValues(input)
        let timestamp = now()
        let recipe = Recipe(
            id: id,
            createdAt: timestamp,
            updatedAt: timestamp,
            name: input.name,
            category: input.category,
            servings: values.servings,
            isDirectMacros: true,
            caloriesTotal: values.calories,
            proteinTotalG: values.proteinG,
            carbTotalG: values.carbG,
            fatTotalG: values.fatG,
            note: input.note
        )
        modelContext.insert(recipe)
        try saveMutation(or: .saveFailed)
        return try recipeSnapshot(recipe)
    }

    public func updateRecipe(
        id: UUID,
        input: RecipeInput
    ) async throws -> RecipeSnapshot {
        let matches = try matchingRecipes(id: id)
        guard !matches.isEmpty else {
            throw RecipeRepositoryMutationError.recipeNotFound(id: id)
        }
        guard matches.count == 1, let recipe = matches.first else {
            throw RecipeRepositoryIntegrityError.duplicateRecipeIDs(
                id: id,
                count: matches.count
            )
        }
        guard recipe.isDirectMacros else {
            throw RecipeRepositoryIntegrityError.invalidPersistedRecipe(id: id)
        }

        let values = try recipePersistenceValues(input)
        recipe.name = input.name
        recipe.category = input.category
        recipe.servings = values.servings
        recipe.isDirectMacros = true
        recipe.caloriesTotal = values.calories
        recipe.proteinTotalG = values.proteinG
        recipe.carbTotalG = values.carbG
        recipe.fatTotalG = values.fatG
        recipe.note = input.note
        recipe.updatedAt = now()
        try saveMutation(or: .saveFailed)
        return try recipeSnapshot(recipe)
    }

    public func removeRecipe(id: UUID) async throws -> RecipeRemovalResult {
        let matches = try matchingRecipes(id: id)
        guard !matches.isEmpty else {
            throw RecipeRepositoryMutationError.recipeNotFound(id: id)
        }
        guard matches.count == 1, let recipe = matches.first else {
            throw RecipeRepositoryIntegrityError.duplicateRecipeIDs(
                id: id,
                count: matches.count
            )
        }
        _ = try recipeSnapshot(recipe)

        let archive = try archiveState()
        let isReferenced = try fetchEntries(FetchDescriptor<MealEntry>())
            .contains { $0.recipeId == id }
        if isReferenced {
            var archivedIDs = archive.ids
            archivedIDs.insert(id)
            try writeArchive(
                archivedIDs,
                setting: archive.setting,
                timestamp: now()
            )
            try saveMutation(or: .deleteFailed)
            return .archived
        }

        if archive.ids.contains(id) {
            var archivedIDs = archive.ids
            archivedIDs.remove(id)
            try writeArchive(
                archivedIDs,
                setting: archive.setting,
                timestamp: now()
            )
        }
        modelContext.delete(recipe)
        try saveMutation(or: .deleteFailed)
        return .deleted
    }

    public func restoreRecipe(id: UUID) async throws -> RecipeSnapshot {
        let matches = try matchingRecipes(id: id)
        guard !matches.isEmpty else {
            throw RecipeRepositoryMutationError.recipeNotFound(id: id)
        }
        guard matches.count == 1, let recipe = matches.first else {
            throw RecipeRepositoryIntegrityError.duplicateRecipeIDs(
                id: id,
                count: matches.count
            )
        }
        let snapshot = try recipeSnapshot(recipe)
        let archive = try archiveState()
        guard archive.ids.contains(id) else {
            throw RecipeRepositoryMutationError.recipeNotArchived(id: id)
        }

        var archivedIDs = archive.ids
        archivedIDs.remove(id)
        try writeArchive(
            archivedIDs,
            setting: archive.setting,
            timestamp: now()
        )
        try saveMutation(or: .saveFailed)
        return snapshot
    }

    public func fetchNutritionDay(
        containing date: Date
    ) async throws -> NutritionDaySnapshot? {
        let day = try NutritionDayKey(containing: date, calendar: calendar)
        let matches = try matchingDays(for: day)
        guard matches.count <= 1 else {
            throw duplicateDayError(day: day, matches: matches)
        }
        guard let existing = matches.first else { return nil }
        try validateUniqueDayID(existing)
        return snapshot(existing, day: day)
    }

    public func fetchOrCreateNutritionDay(
        containing date: Date
    ) async throws -> NutritionDaySnapshot {
        let day = try NutritionDayKey(containing: date, calendar: calendar)
        let matches = try matchingDays(for: day)
        guard matches.count <= 1 else {
            throw duplicateDayError(day: day, matches: matches)
        }

        if let existing = matches.first {
            try validateUniqueDayID(existing)
            guard existing.date != day.start else {
                return snapshot(existing, day: day)
            }
            existing.date = day.start
            existing.updatedAt = now()
            try saveMutation(or: .saveFailed)
            return snapshot(existing, day: day)
        }

        let id = makeID()
        guard try matchingDays(id: id).isEmpty else {
            throw NutritionRepositoryIntegrityError.nutritionDayIDCollision(id: id)
        }
        let timestamp = now()
        let created = DailyNutritionLog(
            id: id,
            createdAt: timestamp,
            updatedAt: timestamp,
            date: day.start
        )
        modelContext.insert(created)
        try saveMutation(or: .saveFailed)
        return snapshot(created, day: day)
    }

    public func fetchNutritionDays() async throws -> [NutritionDaySnapshot] {
        let logs = try fetchDays(FetchDescriptor<DailyNutritionLog>())
        try validateUniqueDayIDs(logs)
        var grouped: [NutritionDayKey: [DailyNutritionLog]] = [:]
        for log in logs {
            let day = try NutritionDayKey(containing: log.date, calendar: calendar)
            grouped[day, default: []].append(log)
        }
        if let (day, matches) = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { lhs, rhs in
                if lhs.key.start != rhs.key.start {
                    return lhs.key.start < rhs.key.start
                }
                return lhs.key.end < rhs.key.end
            })
            .first {
            throw duplicateDayError(day: day, matches: matches)
        }
        return grouped
            .compactMap { day, matches in
                matches.first.map { snapshot($0, day: day) }
            }
            .sorted { lhs, rhs in
                if lhs.day.start != rhs.day.start {
                    return lhs.day.start < rhs.day.start
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func deleteNutritionDay(id: UUID) async throws {
        let matches = try matchingDays(id: id)
        guard !matches.isEmpty else {
            throw NutritionRepositoryMutationError.nutritionDayNotFound(id: id)
        }
        guard matches.count == 1, let day = matches.first else {
            throw NutritionRepositoryIntegrityError.duplicateNutritionDayIDs(
                id: id,
                count: matches.count
            )
        }

        let entries = try fetchEntries(FetchDescriptor<MealEntry>())
            .filter { $0.dailyNutritionLog?.id == id }
        entries.forEach { modelContext.delete($0) }
        modelContext.delete(day)
        try saveMutation(or: .deleteFailed)
    }

    private func matchingFoods(id: UUID) throws -> [Food] {
        let requestedID = id
        return try fetchFoodModels(
            FetchDescriptor<Food>(
                predicate: #Predicate { $0.id == requestedID }
            )
        )
    }

    private func fetchFoodModels(
        _ descriptor: FetchDescriptor<Food>
    ) throws -> [Food] {
        do {
            return try fetchFoodsOperation(descriptor)
        } catch {
            throw NutritionRepositoryOperationError.loadFailed
        }
    }

    private func validateUniqueFoodIDs(_ foods: [Food]) throws {
        let duplicate = Dictionary(grouping: foods, by: \.id)
            .filter { $0.value.count > 1 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .first
        if let (id, matches) = duplicate {
            throw FoodRepositoryIntegrityError.duplicateFoodIDs(
                id: id,
                count: matches.count
            )
        }
    }

    private func foodSnapshot(_ food: Food) throws -> FoodSnapshot {
        do {
            let input = try FoodInput(
                name: food.name,
                brand: food.brand,
                servingSize: try FoodPersistenceValueMapper.decimal(
                    from: food.servingSize
                ),
                servingUnit: food.servingUnit,
                caloriesPerServing: try FoodPersistenceValueMapper.decimal(
                    from: food.caloriesPerServing
                ),
                proteinG: try FoodPersistenceValueMapper.decimal(
                    from: food.proteinG
                ),
                carbG: try FoodPersistenceValueMapper.decimal(
                    from: food.carbG
                ),
                fatG: try FoodPersistenceValueMapper.decimal(
                    from: food.fatG
                ),
                fiberG: try food.fiberG.map {
                    try FoodPersistenceValueMapper.decimal(from: $0)
                }
            )
            return FoodSnapshot(
                id: food.id,
                createdAt: food.createdAt,
                updatedAt: food.updatedAt,
                name: input.name,
                brand: input.brand,
                servingSize: input.servingSize,
                servingUnit: input.servingUnit,
                macros: input.macros,
                fiberG: input.fiberG,
                source: food.source
            )
        } catch {
            throw FoodRepositoryIntegrityError.invalidPersistedFood(id: food.id)
        }
    }

    private func persistenceValues(
        _ input: FoodInput
    ) throws -> FoodPersistenceValues {
        do {
            return FoodPersistenceValues(
                servingSize: try FoodPersistenceValueMapper.double(
                    from: input.servingSize
                ),
                calories: try FoodPersistenceValueMapper.double(
                    from: input.macros.calories
                ),
                proteinG: try FoodPersistenceValueMapper.double(
                    from: input.macros.proteinG
                ),
                carbG: try FoodPersistenceValueMapper.double(
                    from: input.macros.carbG
                ),
                fatG: try FoodPersistenceValueMapper.double(
                    from: input.macros.fatG
                ),
                fiberG: try input.fiberG.map {
                    try FoodPersistenceValueMapper.double(from: $0)
                }
            )
        } catch {
            throw FoodRepositoryMutationError.invalidInput
        }
    }

    private func matchingRecipes(id: UUID) throws -> [Recipe] {
        let requestedID = id
        return try fetchRecipeModels(
            FetchDescriptor<Recipe>(
                predicate: #Predicate { $0.id == requestedID }
            )
        )
    }

    private func fetchRecipeModels(
        _ descriptor: FetchDescriptor<Recipe>
    ) throws -> [Recipe] {
        do {
            return try fetchRecipesOperation(descriptor)
        } catch {
            throw NutritionRepositoryOperationError.loadFailed
        }
    }

    private func fetchSettings(
        _ descriptor: FetchDescriptor<AppSetting>
    ) throws -> [AppSetting] {
        do {
            return try fetchSettingsOperation(descriptor)
        } catch {
            throw NutritionRepositoryOperationError.loadFailed
        }
    }

    private func validateUniqueRecipeIDs(_ recipes: [Recipe]) throws {
        let duplicate = Dictionary(grouping: recipes, by: \.id)
            .filter { $0.value.count > 1 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .first
        if let (id, matches) = duplicate {
            throw RecipeRepositoryIntegrityError.duplicateRecipeIDs(
                id: id,
                count: matches.count
            )
        }
    }

    private func recipeSnapshot(_ recipe: Recipe) throws -> RecipeSnapshot {
        guard recipe.isDirectMacros else {
            throw RecipeRepositoryIntegrityError.invalidPersistedRecipe(id: recipe.id)
        }
        do {
            let input = try RecipeInput(
                name: recipe.name,
                category: recipe.category,
                servings: try RecipePersistenceValueMapper.decimal(
                    from: recipe.servings
                ),
                caloriesTotal: try RecipePersistenceValueMapper.decimal(
                    from: recipe.caloriesTotal
                ),
                proteinTotalG: try RecipePersistenceValueMapper.decimal(
                    from: recipe.proteinTotalG
                ),
                carbTotalG: try RecipePersistenceValueMapper.decimal(
                    from: recipe.carbTotalG
                ),
                fatTotalG: try RecipePersistenceValueMapper.decimal(
                    from: recipe.fatTotalG
                ),
                note: recipe.note
            )
            return RecipeSnapshot(
                id: recipe.id,
                createdAt: recipe.createdAt,
                updatedAt: recipe.updatedAt,
                name: input.name,
                category: input.category,
                servings: input.servings,
                isDirectMacros: true,
                totalMacros: input.totalMacros,
                note: input.note
            )
        } catch {
            throw RecipeRepositoryIntegrityError.invalidPersistedRecipe(id: recipe.id)
        }
    }

    private func recipePersistenceValues(
        _ input: RecipeInput
    ) throws -> RecipePersistenceValues {
        do {
            return RecipePersistenceValues(
                servings: try RecipePersistenceValueMapper.double(
                    from: input.servings
                ),
                calories: try RecipePersistenceValueMapper.double(
                    from: input.totalMacros.calories
                ),
                proteinG: try RecipePersistenceValueMapper.double(
                    from: input.totalMacros.proteinG
                ),
                carbG: try RecipePersistenceValueMapper.double(
                    from: input.totalMacros.carbG
                ),
                fatG: try RecipePersistenceValueMapper.double(
                    from: input.totalMacros.fatG
                )
            )
        } catch {
            throw RecipeRepositoryMutationError.invalidInput
        }
    }

    private func archiveState() throws -> (
        setting: AppSetting?,
        ids: Set<UUID>
    ) {
        let settings = try fetchSettings(FetchDescriptor<AppSetting>())
            .filter { $0.key == RecipeArchiveCodec.settingKey }
        guard settings.count <= 1 else {
            throw RecipeRepositoryIntegrityError.duplicateArchiveSettings(
                count: settings.count
            )
        }
        guard let setting = settings.first else {
            return (nil, [])
        }
        return (setting, try RecipeArchiveCodec.decode(setting.value))
    }

    private func writeArchive(
        _ ids: Set<UUID>,
        setting: AppSetting?,
        timestamp: Date
    ) throws {
        let value = try RecipeArchiveCodec.encode(ids)
        if let setting {
            setting.value = value
            setting.updatedAt = timestamp
        } else {
            modelContext.insert(
                AppSetting(
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    key: RecipeArchiveCodec.settingKey,
                    value: value
                )
            )
        }
    }

    private func matchingDays(for day: NutritionDayKey) throws -> [DailyNutritionLog] {
        let start = day.start
        let end = day.end
        return try fetchDays(
            FetchDescriptor<DailyNutritionLog>(
                predicate: #Predicate { log in
                    log.date >= start && log.date < end
                }
            )
        )
    }

    private func matchingDays(id: UUID) throws -> [DailyNutritionLog] {
        let requestedID = id
        return try fetchDays(
            FetchDescriptor<DailyNutritionLog>(
                predicate: #Predicate { $0.id == requestedID }
            )
        )
    }

    private func fetchDays(
        _ descriptor: FetchDescriptor<DailyNutritionLog>
    ) throws -> [DailyNutritionLog] {
        do {
            return try fetchDaysOperation(descriptor)
        } catch {
            throw NutritionRepositoryOperationError.loadFailed
        }
    }

    private func fetchEntries(
        _ descriptor: FetchDescriptor<MealEntry>
    ) throws -> [MealEntry] {
        do {
            return try fetchEntriesOperation(descriptor)
        } catch {
            throw NutritionRepositoryOperationError.loadFailed
        }
    }

    private func fetchProfiles(
        _ descriptor: FetchDescriptor<UserProfile>
    ) throws -> [UserProfile] {
        do {
            return try fetchProfilesOperation(descriptor)
        } catch {
            throw NutritionRepositoryOperationError.loadFailed
        }
    }

    private func validateUniqueDayIDs(_ logs: [DailyNutritionLog]) throws {
        let duplicate = Dictionary(grouping: logs, by: \.id)
            .filter { $0.value.count > 1 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .first
        if let (id, matches) = duplicate {
            throw NutritionRepositoryIntegrityError.duplicateNutritionDayIDs(
                id: id,
                count: matches.count
            )
        }
    }

    private func validateUniqueDayID(_ log: DailyNutritionLog) throws {
        let matches = try matchingDays(id: log.id)
        guard matches.count == 1 else {
            throw NutritionRepositoryIntegrityError.duplicateNutritionDayIDs(
                id: log.id,
                count: matches.count
            )
        }
    }

    private func duplicateDayError(
        day: NutritionDayKey,
        matches: [DailyNutritionLog]
    ) -> NutritionRepositoryIntegrityError {
        .duplicateNutritionDays(
            dayStart: day.start,
            ids: matches.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func snapshot(
        _ log: DailyNutritionLog,
        day: NutritionDayKey
    ) -> NutritionDaySnapshot {
        NutritionDaySnapshot(
            id: log.id,
            createdAt: log.createdAt,
            updatedAt: log.updatedAt,
            day: day,
            mealEntryIDs: (log.mealEntries ?? [])
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func saveMutation(
        or operationError: NutritionRepositoryOperationError
    ) throws {
        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw operationError
        }
    }
}
