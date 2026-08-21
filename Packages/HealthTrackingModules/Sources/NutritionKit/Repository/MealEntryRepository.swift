import CoreModels
import Foundation

public enum MealEntryRepositoryIntegrityError: Error, Equatable, Sendable {
    case invalidPersistedMealEntry(id: UUID)
    case duplicateMealEntryIDs(id: UUID, count: Int)
}

public enum MealEntryRepositoryMutationError: Error, Equatable, Sendable {
    case recipeNotFound(id: UUID)
    case recipeArchived(id: UUID)
    case foodNotFound(id: UUID)
    case unsupportedFoodSource(id: UUID, source: FoodSource)
    case requestIDConflict(id: UUID)
    case mealEntryNotFound(id: UUID)
    case invalidInput
}

@MainActor
public protocol MealEntryRepository {
    func fetchMealEntries(
        containing date: Date
    ) async throws -> NutritionDayEntriesSnapshot

    func createMealEntry(
        _ request: MealEntryCreateRequest
    ) async throws -> NutritionDayEntriesSnapshot

    func updateMealEntry(
        id: UUID,
        update: MealEntryUpdate
    ) async throws -> NutritionDayEntriesSnapshot

    func deleteMealEntry(
        id: UUID
    ) async throws -> NutritionDayEntriesSnapshot
}

@MainActor
public protocol NutritionDayViewRepository:
    NutritionDayRepository,
    MealEntryRepository {}

@MainActor
public protocol NutritionRepository:
    NutritionDayViewRepository,
    FoodLibraryRepository,
    RecipeLibraryRepository {}
