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

    func testEmptyStoreReturnsNoProfileProgramOrTrainingCatalogRecords() async throws {
        let repository = try makeRepository()
        let profile = try await repository.fetchUserProfile()
        let program = try await repository.fetchActiveProgram()
        let phases = try await repository.fetchProgramPhases(programID: UUID())
        let days = try await repository.fetchWorkoutDays(programID: UUID())
        let exercises = try await repository.fetchExerciseTemplates(workoutDayID: UUID())
        let warmups = try await repository.fetchWarmupItems(workoutDayID: UUID())
        let cooldowns = try await repository.fetchCooldownItems(workoutDayID: UUID())
        let reminders = try await repository.fetchHealthCheckReminders()
        let programState = try await repository.fetchProgramState(programID: UUID())

        XCTAssertNil(profile)
        XCTAssertNil(program)
        XCTAssertTrue(phases.isEmpty)
        XCTAssertEqual(days, [])
        XCTAssertEqual(exercises, [])
        XCTAssertEqual(warmups, [])
        XCTAssertEqual(cooldowns, [])
        XCTAssertEqual(reminders, [])
        XCTAssertNil(programState)
    }

    func testSeededM1CatalogRoundTripsThroughRepositoryInStableOrder() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        try SwiftDataSeedLoader(modelContext: writeContext).seedIfNeeded(
            installedAt: Date(timeIntervalSinceReferenceDate: 10_000)
        )
        let repository: any TrainingRepository = SwiftDataTrainingRepository(
            modelContext: ModelContext(container)
        )

        let fetchedProgram = try await repository.fetchActiveProgram()
        let program = try XCTUnwrap(fetchedProgram)
        let days = try await repository.fetchWorkoutDays(programID: program.id)
        XCTAssertEqual(days.map(\.id), [SeedIdentifiers.dayA, SeedIdentifiers.dayB, SeedIdentifiers.dayC])

        let expectedExerciseNames: [UUID: [String]] = [
            SeedIdentifiers.dayA: [
                "Goblet Squat", "Chin-up", "DB Floor Press", "DB Romanian Deadlift",
                "Prone Y-T-W", "Face Pull (bant)", "Tek Bacak Calf Raise", "Plank / Pallof"
            ],
            SeedIdentifiers.dayB: [
                "DB RDL (çift)", "Tek Kol DB Row", "Push-up", "DB Overhead Press",
                "Bulgarian Split Squat", "Glute Bridge / Hip Thrust", "Wall Slide",
                "Dead Bug", "Copenhagen Plank"
            ],
            SeedIdentifiers.dayC: [
                "Reverse Lunge (DB)", "Nordic Hamstring Curl", "Pull-up / bantlı",
                "Bantlı / Tek Kol Row", "Half-Kneeling DB Press", "DB Lateral Raise",
                "Farmer's Carry", "Curl", "Triceps", "Side Plank / Pallof"
            ]
        ]
        let expectedWarmupCounts = [
            SeedIdentifiers.dayA: 9,
            SeedIdentifiers.dayB: 12,
            SeedIdentifiers.dayC: 9
        ]

        for day in days {
            let exercises = try await repository.fetchExerciseTemplates(workoutDayID: day.id)
            let warmups = try await repository.fetchWarmupItems(workoutDayID: day.id)
            let cooldowns = try await repository.fetchCooldownItems(workoutDayID: day.id)
            let expectedNames = try XCTUnwrap(expectedExerciseNames[day.id])
            let expectedWarmupCount = try XCTUnwrap(expectedWarmupCounts[day.id])

            XCTAssertEqual(exercises.map(\.name), expectedNames)
            XCTAssertEqual(exercises.map(\.orderIndex), Array(1...expectedNames.count))
            XCTAssertEqual(warmups.count, expectedWarmupCount)
            XCTAssertEqual(warmups.map(\.orderIndex), Array(1...expectedWarmupCount))
            XCTAssertEqual(cooldowns.map(\.movement), [
                "Pektoral germe", "C6 nöral gliding", "Chin tuck"
            ])
            XCTAssertEqual(cooldowns.map(\.orderIndex), [1, 2, 3])
        }

        let reminders = try await repository.fetchHealthCheckReminders()
        XCTAssertEqual(reminders.map(\.name), ["D vitamini", "Genel check-up", "Ferritin"])
        let fetchedState = try await repository.fetchProgramState(programID: program.id)
        let state = try XCTUnwrap(fetchedState)
        XCTAssertEqual(state.id, SeedIdentifiers.programState)
        XCTAssertEqual(state.programId, SeedIdentifiers.program)
        XCTAssertEqual(state.currentPhaseId, SeedIdentifiers.phase1)
    }

    func testProgramPhasesFilterRequestedProgramThenUseOrderIndexAndUUIDForStableOrdering() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        let requestedProgram = Program(isActive: false)
        let activeDecoyProgram = Program(isActive: true)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let decoyID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let unorderedPhases = [
            ProgramPhase(id: laterID, name: "Later", orderIndex: 2, program: requestedProgram),
            ProgramPhase(id: secondID, name: "Second", orderIndex: 1, program: requestedProgram),
            ProgramPhase(id: firstID, name: "First", orderIndex: 1, program: requestedProgram),
            ProgramPhase(id: decoyID, name: "Active decoy", orderIndex: 0, program: activeDecoyProgram)
        ]
        writeContext.insert(requestedProgram)
        writeContext.insert(activeDecoyProgram)
        unorderedPhases.forEach(writeContext.insert)
        try writeContext.save()

        let repository: any TrainingRepository = SwiftDataTrainingRepository(
            modelContext: ModelContext(container)
        )
        let fetchedPhases = try await repository.fetchProgramPhases(programID: requestedProgram.id)

        XCTAssertEqual(fetchedPhases.map(\.id), [firstID, secondID, laterID])
    }

    func testProgramPhasesReturnEmptyWithoutCrossProgramLeakage() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        let requestedProgram = Program(isActive: true)
        let otherProgram = Program()
        let otherProgramPhase = ProgramPhase(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Other program",
            orderIndex: 0,
            program: otherProgram
        )
        writeContext.insert(requestedProgram)
        writeContext.insert(otherProgram)
        writeContext.insert(otherProgramPhase)
        try writeContext.save()

        let repository: any TrainingRepository = SwiftDataTrainingRepository(
            modelContext: ModelContext(container)
        )
        let fetchedPhases = try await repository.fetchProgramPhases(programID: requestedProgram.id)

        XCTAssertTrue(fetchedPhases.isEmpty)
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

    func testCatalogReadsFilterRequestedDayThenUseOrderIndexAndUUIDForStableOrdering() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        let requestedDay = WorkoutDayTemplate(name: "Requested")
        let decoyDay = WorkoutDayTemplate(name: "Decoy")
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let decoyID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

        let exercises = [
            ExerciseTemplate(id: laterID, orderIndex: 2, workoutDayTemplate: requestedDay),
            ExerciseTemplate(id: secondID, orderIndex: 1, workoutDayTemplate: requestedDay),
            ExerciseTemplate(id: firstID, orderIndex: 1, workoutDayTemplate: requestedDay),
            ExerciseTemplate(id: decoyID, orderIndex: 0, workoutDayTemplate: decoyDay)
        ]
        let warmups = [
            WarmupItem(id: laterID, orderIndex: 2, workoutDayTemplate: requestedDay),
            WarmupItem(id: secondID, orderIndex: 1, workoutDayTemplate: requestedDay),
            WarmupItem(id: firstID, orderIndex: 1, workoutDayTemplate: requestedDay),
            WarmupItem(id: decoyID, orderIndex: 0, workoutDayTemplate: decoyDay)
        ]
        let cooldowns = [
            CooldownItem(id: laterID, orderIndex: 2, workoutDayTemplate: requestedDay),
            CooldownItem(id: secondID, orderIndex: 1, workoutDayTemplate: requestedDay),
            CooldownItem(id: firstID, orderIndex: 1, workoutDayTemplate: requestedDay),
            CooldownItem(id: decoyID, orderIndex: 0, workoutDayTemplate: decoyDay)
        ]
        writeContext.insert(requestedDay)
        writeContext.insert(decoyDay)
        exercises.forEach(writeContext.insert)
        warmups.forEach(writeContext.insert)
        cooldowns.forEach(writeContext.insert)
        try writeContext.save()

        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))
        let fetchedExercises = try await repository.fetchExerciseTemplates(
            workoutDayID: requestedDay.id
        )
        let fetchedWarmups = try await repository.fetchWarmupItems(workoutDayID: requestedDay.id)
        let fetchedCooldowns = try await repository.fetchCooldownItems(
            workoutDayID: requestedDay.id
        )

        XCTAssertEqual(fetchedExercises.map(\.id), [firstID, secondID, laterID])
        XCTAssertEqual(fetchedWarmups.map(\.id), [firstID, secondID, laterID])
        XCTAssertEqual(fetchedCooldowns.map(\.id), [firstID, secondID, laterID])
    }

    func testHealthCheckRemindersUseDueDateThenUUIDForStableOrdering() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        let dueDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        [
            HealthCheckReminder(id: laterID, dueDate: dueDate.addingTimeInterval(1)),
            HealthCheckReminder(id: secondID, dueDate: dueDate),
            HealthCheckReminder(id: firstID, dueDate: dueDate)
        ].forEach(writeContext.insert)
        try writeContext.save()

        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))
        let reminders = try await repository.fetchHealthCheckReminders()

        XCTAssertEqual(reminders.map(\.id), [firstID, secondID, laterID])
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

    func testDuplicateProgramStatesProduceTypedIntegrityError() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        let programID = UUID()
        writeContext.insert(ProgramState(programId: programID))
        writeContext.insert(ProgramState(programId: programID))
        try writeContext.save()
        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))

        do {
            _ = try await repository.fetchProgramState(programID: programID)
            XCTFail("Expected duplicate program-state integrity error")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryIntegrityError,
                .duplicateProgramStates(programID: programID, count: 2)
            )
        }
    }

    private func makeRepository() throws -> any TrainingRepository {
        let container = try ModelContainerFactory.make(for: .inMemory)
        return SwiftDataTrainingRepository(modelContext: ModelContext(container))
    }
}
