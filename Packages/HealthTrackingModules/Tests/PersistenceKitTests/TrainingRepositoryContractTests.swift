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
        let completedHistory = try await repository.fetchCompletedExerciseHistory(
            exerciseTemplateID: UUID()
        )

        XCTAssertNil(profile)
        XCTAssertNil(program)
        XCTAssertTrue(phases.isEmpty)
        XCTAssertEqual(days, [])
        XCTAssertEqual(exercises, [])
        XCTAssertEqual(warmups, [])
        XCTAssertEqual(cooldowns, [])
        XCTAssertEqual(reminders, [])
        XCTAssertNil(programState)
        XCTAssertEqual(completedHistory, [])
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

    func testCompletedExerciseHistoryIsImmutableDeterministicAndExcludesActiveSessions() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000000090")!
        let newestDate = Date(timeIntervalSinceReferenceDate: 3_000)
        let olderDate = Date(timeIntervalSinceReferenceDate: 2_000)
        let newestFirst = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000091")!,
            date: newestDate,
            status: .completed
        )
        let newestSecond = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000092")!,
            date: newestDate,
            status: .completed
        )
        let older = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000093")!,
            date: olderDate,
            status: .completed
        )
        let active = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000094")!,
            date: Date(timeIntervalSinceReferenceDate: 4_000),
            status: .inProgress
        )
        [newestFirst, newestSecond, older, active].forEach(context.insert)

        let newestSecondSet = SetLog(
            exerciseTemplateId: exerciseID,
            setIndex: 2,
            weightKg: 12.5,
            reps: 8,
            rir: 1,
            workoutSession: newestFirst
        )
        let logs = [
            newestSecondSet,
            SetLog(
                exerciseTemplateId: exerciseID,
                setIndex: 1,
                weightKg: 10,
                reps: 12,
                rir: 0,
                workoutSession: newestFirst
            ),
            SetLog(
                exerciseTemplateId: exerciseID,
                setIndex: 0,
                reps: 5,
                isWarmupSet: true,
                workoutSession: newestFirst
            ),
            SetLog(
                exerciseTemplateId: exerciseID,
                setIndex: 1,
                weightKg: 10,
                reps: 12,
                rir: 1,
                workoutSession: newestSecond
            ),
            SetLog(
                exerciseTemplateId: exerciseID,
                setIndex: 1,
                weightKg: 7.5,
                reps: 10,
                rir: 1,
                workoutSession: older
            ),
            SetLog(
                exerciseTemplateId: exerciseID,
                setIndex: 1,
                weightKg: 20,
                reps: 12,
                rir: 0,
                workoutSession: active
            ),
            SetLog(
                exerciseTemplateId: UUID(),
                setIndex: 1,
                weightKg: 99,
                reps: 99,
                rir: 0,
                workoutSession: newestFirst
            ),
        ]
        logs.forEach(context.insert)
        try context.save()
        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))

        let history = try await repository.fetchCompletedExerciseHistory(
            exerciseTemplateID: exerciseID
        )

        XCTAssertEqual(
            history.map(\.session.id),
            [newestFirst.id, newestSecond.id, older.id]
        )
        XCTAssertEqual(history[0].setLogs.map(\.setIndex), [0, 1, 2])
        XCTAssertEqual(history[0].setLogs.map(\.isWarmupSet), [true, false, false])
        XCTAssertEqual(history[0].setLogs.last?.measurement.weightKg, 12.5)
        newestSecondSet.weightKg = 99
        XCTAssertEqual(history[0].setLogs.last?.measurement.weightKg, 12.5)
        assertEquatableSendable(history[0])
    }

    func testSaveSetRevalidatesAndReturnsAnImmutableSnapshot() async throws {
        let fixture = try makeSetMutationFixture(kind: .weightReps)
        let setID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let completedAt = Date(timeIntervalSinceReferenceDate: 4_000)
        let request = SetLogSaveRequest(
            id: setID,
            workoutSessionID: fixture.session.id,
            exerciseTemplateID: fixture.exercise.id,
            setIndex: 1,
            measurement: .init(weightKg: 12.5, reps: 8, performedVariant: "DB", rir: 2),
            isWarmupSet: false,
            completedAt: completedAt
        )

        let snapshot = try await fixture.repository.saveSet(request)

        XCTAssertEqual(snapshot.id, setID)
        XCTAssertEqual(snapshot.workoutSessionID, fixture.session.id)
        XCTAssertEqual(snapshot.exerciseTemplateID, fixture.exercise.id)
        XCTAssertEqual(snapshot.setIndex, 1)
        XCTAssertEqual(snapshot.measurement, request.measurement)
        XCTAssertFalse(snapshot.isWarmupSet)
        XCTAssertEqual(snapshot.completedAt, completedAt)
        assertEquatableSendable(snapshot)

        let stored = try ModelContext(fixture.container).fetch(FetchDescriptor<SetLog>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.measurementInput, request.measurement)
        XCTAssertEqual(stored.first?.workoutSession?.id, fixture.session.id)
    }

    func testInvalidAndAmbiguousSetInputsNeverMutatePersistentCount() async throws {
        let fixture = try makeSetMutationFixture(kind: .duration)
        let invalidInputs: [SetMeasurementInput] = [
            .init(durationSec: 0),
            .init(reps: 8, durationSec: 30)
        ]

        for (offset, input) in invalidInputs.enumerated() {
            let request = SetLogSaveRequest(
                workoutSessionID: fixture.session.id,
                exerciseTemplateID: fixture.exercise.id,
                setIndex: offset + 1,
                measurement: input,
                completedAt: Date(timeIntervalSinceReferenceDate: Double(5_000 + offset))
            )

            await XCTAssertThrowsErrorAsync(try await fixture.repository.saveSet(request))
            XCTAssertEqual(
                try ModelContext(fixture.container).fetchCount(FetchDescriptor<SetLog>()),
                0
            )
        }
    }

    func testLogicalDuplicateSetIndexIsRejectedWithoutReplacingFirstValue() async throws {
        let fixture = try makeSetMutationFixture(kind: .reps)
        let first = SetLogSaveRequest(
            workoutSessionID: fixture.session.id,
            exerciseTemplateID: fixture.exercise.id,
            setIndex: 1,
            measurement: .init(reps: 8, rir: 3),
            completedAt: Date(timeIntervalSinceReferenceDate: 6_000)
        )
        let duplicate = SetLogSaveRequest(
            workoutSessionID: fixture.session.id,
            exerciseTemplateID: fixture.exercise.id,
            setIndex: 1,
            measurement: .init(reps: 10, rir: 1),
            completedAt: Date(timeIntervalSinceReferenceDate: 6_100)
        )

        _ = try await fixture.repository.saveSet(first)
        do {
            _ = try await fixture.repository.saveSet(duplicate)
            XCTFail("Expected duplicate logical set index to fail")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryIntegrityError,
                .duplicateSetIndex(
                    workoutSessionID: fixture.session.id,
                    exerciseTemplateID: fixture.exercise.id,
                    setIndex: 1
                )
            )
        }

        let stored = try ModelContext(fixture.container).fetch(FetchDescriptor<SetLog>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.measurementInput, first.measurement)
    }

    func testWarmupAndWorkingSetCannotShareALogicalIndex() async throws {
        let fixture = try makeSetMutationFixture(kind: .reps)
        let base = SetLogSaveRequest(
            workoutSessionID: fixture.session.id,
            exerciseTemplateID: fixture.exercise.id,
            setIndex: 1,
            measurement: .init(reps: 5),
            isWarmupSet: true,
            completedAt: Date(timeIntervalSinceReferenceDate: 7_000)
        )
        let working = SetLogSaveRequest(
            workoutSessionID: fixture.session.id,
            exerciseTemplateID: fixture.exercise.id,
            setIndex: 1,
            measurement: .init(reps: 8),
            isWarmupSet: false,
            completedAt: Date(timeIntervalSinceReferenceDate: 7_100)
        )

        _ = try await fixture.repository.saveSet(base)
        do {
            _ = try await fixture.repository.saveSet(working)
            XCTFail("Expected duplicate logical set index to fail")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryIntegrityError,
                .duplicateSetIndex(
                    workoutSessionID: fixture.session.id,
                    exerciseTemplateID: fixture.exercise.id,
                    setIndex: 1
                )
            )
        }

        let stored = try ModelContext(fixture.container).fetch(FetchDescriptor<SetLog>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertTrue(stored.first?.isWarmupSet == true)
    }

    private func makeRepository() throws -> any TrainingRepository {
        let container = try ModelContainerFactory.make(for: .inMemory)
        return SwiftDataTrainingRepository(modelContext: ModelContext(container))
    }

    private func makeSetMutationFixture(
        kind: ExerciseMeasurementKind
    ) throws -> (
        container: ModelContainer,
        repository: SwiftDataTrainingRepository,
        session: WorkoutSession,
        exercise: ExerciseTemplate
    ) {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let session = WorkoutSession(status: .inProgress)
        let exercise = ExerciseTemplate(measurementKind: kind)
        context.insert(session)
        context.insert(exercise)
        try context.save()
        return (
            container,
            SwiftDataTrainingRepository(modelContext: ModelContext(container)),
            session,
            exercise
        )
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}

    private func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {}
    }
}
