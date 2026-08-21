import Foundation

public enum NutritionRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateNutritionDays(dayStart: Date, ids: [UUID])
    case duplicateNutritionDayIDs(id: UUID, count: Int)
    case nutritionDayIDCollision(id: UUID)
    case duplicateUserProfiles(count: Int)
}

public enum NutritionRepositoryMutationError: Error, Equatable, Sendable {
    case nutritionDayNotFound(id: UUID)
}

public enum NutritionRepositoryOperationError: Error, Equatable, Sendable {
    case loadFailed
    case saveFailed
    case deleteFailed
}

@MainActor
public protocol NutritionDayRepository {
    func fetchNutritionTargets() async throws -> NutritionMacroTargets?
    func fetchNutritionDay(containing date: Date) async throws -> NutritionDaySnapshot?
    func fetchOrCreateNutritionDay(containing date: Date) async throws -> NutritionDaySnapshot
    func fetchNutritionDays() async throws -> [NutritionDaySnapshot]
    func deleteNutritionDay(id: UUID) async throws
}
