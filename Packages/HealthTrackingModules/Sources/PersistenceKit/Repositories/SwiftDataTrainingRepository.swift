import CoreModels
import Foundation
import SwiftData
import TrainingKit

public enum TrainingRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateUserProfiles(count: Int)
    case duplicateActivePrograms(count: Int)
}

@MainActor
public final class SwiftDataTrainingRepository: TrainingRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchUserProfile() async throws -> UserProfile? {
        let profiles = try modelContext.fetch(
            FetchDescriptor<UserProfile>(
                sortBy: [SortDescriptor(\UserProfile.updatedAt, order: .reverse)]
            )
        )

        guard profiles.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateUserProfiles(count: profiles.count)
        }
        return profiles.first
    }

    public func fetchActiveProgram() async throws -> Program? {
        let programs = Self.sortActivePrograms(
            try modelContext.fetch(
                FetchDescriptor<Program>(
                    predicate: #Predicate { $0.isActive },
                    sortBy: [SortDescriptor(\Program.updatedAt, order: .reverse)]
                )
            )
        )

        guard programs.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateActivePrograms(count: programs.count)
        }
        return programs.first
    }

    static func sortActivePrograms(_ programs: [Program]) -> [Program] {
        programs.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func fetchWorkoutDays(programID: UUID) async throws -> [WorkoutDayTemplate] {
        let days = try modelContext.fetch(
            FetchDescriptor<WorkoutDayTemplate>(
                sortBy: [SortDescriptor(\WorkoutDayTemplate.orderIndex, order: .forward)]
            )
        )

        return days
            .filter { $0.program?.id == programID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }
}
