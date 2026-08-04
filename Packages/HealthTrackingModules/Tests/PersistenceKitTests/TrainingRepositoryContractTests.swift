import CoreModels
@testable import PersistenceKit
import SwiftData
import TrainingKit
import XCTest

@MainActor
final class TrainingRepositoryContractTests: XCTestCase {
    func testActiveProgramOrderingUsesUpdatedAtThenUUID() {
        let newest = Date(timeIntervalSinceReferenceDate: 2_000)
        let older = Date(timeIntervalSinceReferenceDate: 1_000)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let olderID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let programs = [
            Program(id: olderID, updatedAt: older, isActive: true),
            Program(id: secondID, updatedAt: newest, isActive: true),
            Program(id: firstID, updatedAt: newest, isActive: true)
        ]

        XCTAssertEqual(
            SwiftDataTrainingRepository.sortActivePrograms(programs).map(\.id),
            [firstID, secondID, olderID]
        )
    }

    func testEmptyStoreReturnsNoProfileProgramOrWorkoutDays() async throws {
        let repository = try makeRepository()
        let profile = try await repository.fetchUserProfile()
        let program = try await repository.fetchActiveProgram()
        let days = try await repository.fetchWorkoutDays(programID: UUID())

        XCTAssertNil(profile)
        XCTAssertNil(program)
        XCTAssertEqual(days, [])
    }

    func testRepositoryFetchesInsertedTrainingRecordsFromANewContext() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        let profile = UserProfile(displayName: "Ada")
        let program = Program(name: "Strength", isActive: true)
        let day = WorkoutDayTemplate(name: "Day A", orderIndex: 1, program: program)
        writeContext.insert(profile)
        writeContext.insert(program)
        writeContext.insert(day)
        try writeContext.save()

        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))
        let fetchedProfile = try await repository.fetchUserProfile()
        let fetchedProgram = try await repository.fetchActiveProgram()
        let fetchedDays = try await repository.fetchWorkoutDays(programID: program.id)

        XCTAssertEqual(fetchedProfile?.id, profile.id)
        XCTAssertEqual(fetchedProgram?.id, program.id)
        XCTAssertEqual(fetchedDays.map(\.id), [day.id])
    }

    func testWorkoutDaysUseOrderIndexThenUUIDForStableOrdering() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        let program = Program(isActive: true)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let unorderedDays = [
            WorkoutDayTemplate(id: laterID, name: "Later", orderIndex: 2, program: program),
            WorkoutDayTemplate(id: secondID, name: "Second", orderIndex: 1, program: program),
            WorkoutDayTemplate(id: firstID, name: "First", orderIndex: 1, program: program)
        ]
        writeContext.insert(program)
        unorderedDays.forEach(writeContext.insert)
        try writeContext.save()

        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))
        let fetchedDays = try await repository.fetchWorkoutDays(programID: program.id)

        XCTAssertEqual(fetchedDays.map(\.id), [firstID, secondID, laterID])
    }

    func testDuplicateProfilesProduceTypedIntegrityError() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        writeContext.insert(UserProfile())
        writeContext.insert(UserProfile())
        try writeContext.save()
        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))

        do {
            _ = try await repository.fetchUserProfile()
            XCTFail("Expected duplicate profile integrity error")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryIntegrityError,
                .duplicateUserProfiles(count: 2)
            )
        }
    }

    func testDuplicateActiveProgramsProduceTypedIntegrityError() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        writeContext.insert(Program(isActive: true))
        writeContext.insert(Program(isActive: true))
        try writeContext.save()
        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))

        do {
            _ = try await repository.fetchActiveProgram()
            XCTFail("Expected duplicate active program integrity error")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryIntegrityError,
                .duplicateActivePrograms(count: 2)
            )
        }
    }

    private func makeRepository() throws -> SwiftDataTrainingRepository {
        let container = try ModelContainerFactory.make(for: .inMemory)
        return SwiftDataTrainingRepository(modelContext: ModelContext(container))
    }
}
