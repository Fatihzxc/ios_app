import CoreModels
import SwiftData
import XCTest

final class TrainingModelRoundTripTests: XCTestCase {
    func testProgramAndTrainingModelsRoundTripAllScalarsAndRelationships() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let date = Date(timeIntervalSinceReferenceDate: 123_456)
        let profileID = UUID()
        let programID = UUID()
        let phaseID = UUID()
        let dayID = UUID()
        let exerciseID = UUID()
        let warmupID = UUID()
        let cooldownID = UUID()
        let sessionID = UUID()
        let setLogID = UUID()
        let stateID = UUID()

        let profile = UserProfile(
            id: profileID, createdAt: date, updatedAt: date,
            displayName: "Ada", heightCm: 172, startWeightKg: 71, targetWeightKg: 65,
            birthYear: 1990, unitsSystem: .imperial, proteinTargetG: 125, calorieTarget: 2_000,
            carbTargetG: 210, fatTargetG: 60, programStartDate: date, weeklyWorkoutTarget: 4
        )
        let program = Program(id: programID, createdAt: date, updatedAt: date, name: "Strength", descriptionText: "Base", isActive: true)
        let phase = ProgramPhase(
            id: phaseID, createdAt: date, updatedAt: date, name: "Build", orderIndex: 2, monthStart: 3, monthEnd: 6,
            trainingFocus: "Strength", nutritionFocus: "Protein", milestone: "Progress",
            entryCriteria: "Consistent", program: program
        )
        let day = WorkoutDayTemplate(id: dayID, createdAt: date, updatedAt: date, name: "Day A", orderIndex: 1, focus: "Squat", program: program)
        let exercise = ExerciseTemplate(
            id: exerciseID, createdAt: date, updatedAt: date, name: "Goblet Squat", orderIndex: 1, targetSets: 3,
            repLow: 8, repHigh: 12, rirLow: 1, rirHigh: 2, category: .compound,
            allowFailure: false, cues: "Brace", safetyNote: "Slow", startingWeightKg: 0,
            progressionRule: .doubleProgression, measurementKind: .weightReps,
            supersetGroupId: UUID(), supersetOrder: 2, workoutDayTemplate: day
        )
        let warmup = WarmupItem(id: warmupID, createdAt: date, updatedAt: date, phase: .activate, movement: "Band", dose: "10 reps", orderIndex: 1, workoutDayTemplate: day)
        let cooldown = CooldownItem(id: cooldownID, createdAt: date, updatedAt: date, movement: "Walk", dose: "5 min", note: "Easy", orderIndex: 1, workoutDayTemplate: day)
        let session = WorkoutSession(
            id: sessionID, createdAt: date, updatedAt: date, date: date, status: .completed, workoutDayTemplateId: dayID,
            perceivedRecovery: 8, note: "Good", ohpSymptomResponse: .symptomFree,
            ohpSymptomCheckedAt: date
        )
        let setLog = SetLog(
            id: setLogID, createdAt: date, updatedAt: date, exerciseTemplateId: exerciseID, setIndex: 1, weightKg: 0, reps: 10,
            durationSec: nil, distanceSteps: nil, performedVariant: "Band green", rir: 2,
            isWarmupSet: false, completedAt: date, workoutSession: session
        )
        let state = ProgramState(
            id: stateID, createdAt: date, updatedAt: date, programId: programID, currentPhaseId: phaseID, phaseStartedAt: date,
            trainingWeekIndex: 3, deloadStatus: .recommended, deloadReason: .scheduled,
            deloadUpdatedAt: date, lastDeloadSkippedAt: date, lastDeloadAction: .stay
        )

        context.insert(profile)
        context.insert(program)
        context.insert(phase)
        context.insert(day)
        context.insert(exercise)
        context.insert(warmup)
        context.insert(cooldown)
        context.insert(session)
        context.insert(setLog)
        context.insert(state)
        try context.save()

        let readContext = ModelContext(container)
        let loadedProfile = try XCTUnwrap(readContext.fetch(FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == profileID })).first)
        let loadedProgram = try XCTUnwrap(readContext.fetch(FetchDescriptor<Program>(predicate: #Predicate { $0.id == programID })).first)
        let loadedPhase = try XCTUnwrap(readContext.fetch(FetchDescriptor<ProgramPhase>(predicate: #Predicate { $0.id == phaseID })).first)
        let loadedDay = try XCTUnwrap(readContext.fetch(FetchDescriptor<WorkoutDayTemplate>(predicate: #Predicate { $0.id == dayID })).first)
        let loadedExercise = try XCTUnwrap(readContext.fetch(FetchDescriptor<ExerciseTemplate>(predicate: #Predicate { $0.id == exerciseID })).first)
        let loadedWarmup = try XCTUnwrap(readContext.fetch(FetchDescriptor<WarmupItem>(predicate: #Predicate { $0.id == warmupID })).first)
        let loadedCooldown = try XCTUnwrap(readContext.fetch(FetchDescriptor<CooldownItem>(predicate: #Predicate { $0.id == cooldownID })).first)
        let loadedSession = try XCTUnwrap(readContext.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first)
        let loadedSetLog = try XCTUnwrap(readContext.fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.id == setLogID })).first)
        let loadedState = try XCTUnwrap(readContext.fetch(FetchDescriptor<ProgramState>(predicate: #Predicate { $0.id == stateID })).first)

        XCTAssertEqual(loadedProfile.id, profileID)
        XCTAssertEqual(loadedProfile.createdAt, date)
        XCTAssertEqual(loadedProfile.updatedAt, date)
        XCTAssertEqual(loadedProfile.displayName, "Ada")
        XCTAssertEqual(loadedProfile.heightCm, 172)
        XCTAssertEqual(loadedProfile.startWeightKg, 71)
        XCTAssertEqual(loadedProfile.targetWeightKg, 65)
        XCTAssertEqual(loadedProfile.birthYear, 1990)
        XCTAssertEqual(loadedProfile.unitsSystem, .imperial)
        XCTAssertEqual(loadedProfile.proteinTargetG, 125)
        XCTAssertEqual(loadedProfile.calorieTarget, 2_000)
        XCTAssertEqual(loadedProfile.carbTargetG, 210)
        XCTAssertEqual(loadedProfile.fatTargetG, 60)
        XCTAssertEqual(loadedProfile.programStartDate, date)
        XCTAssertEqual(loadedProfile.weeklyWorkoutTarget, 4)
        XCTAssertEqual(loadedProgram.id, programID)
        XCTAssertEqual(loadedProgram.createdAt, date)
        XCTAssertEqual(loadedProgram.updatedAt, date)
        XCTAssertEqual(loadedProgram.name, "Strength")
        XCTAssertEqual(loadedProgram.descriptionText, "Base")
        XCTAssertTrue(loadedProgram.isActive)
        XCTAssertEqual(loadedProgram.workoutDayTemplates?.count, 1)
        XCTAssertEqual(loadedProgram.programPhases?.count, 1)
        XCTAssertEqual(loadedPhase.id, phaseID)
        XCTAssertEqual(loadedPhase.createdAt, date)
        XCTAssertEqual(loadedPhase.updatedAt, date)
        XCTAssertEqual(loadedPhase.name, "Build")
        XCTAssertEqual(loadedPhase.orderIndex, 2)
        XCTAssertEqual(loadedPhase.monthStart, 3)
        XCTAssertEqual(loadedPhase.monthEnd, 6)
        XCTAssertEqual(loadedPhase.trainingFocus, "Strength")
        XCTAssertEqual(loadedPhase.nutritionFocus, "Protein")
        XCTAssertEqual(loadedPhase.milestone, "Progress")
        XCTAssertEqual(loadedPhase.entryCriteria, "Consistent")
        XCTAssertEqual(loadedPhase.program?.id, programID)
        XCTAssertEqual(loadedDay.id, dayID)
        XCTAssertEqual(loadedDay.createdAt, date)
        XCTAssertEqual(loadedDay.updatedAt, date)
        XCTAssertEqual(loadedDay.name, "Day A")
        XCTAssertEqual(loadedDay.orderIndex, 1)
        XCTAssertEqual(loadedDay.focus, "Squat")
        XCTAssertEqual(loadedDay.program?.id, programID)
        XCTAssertEqual(loadedDay.exerciseTemplates?.count, 1)
        XCTAssertEqual(loadedDay.warmupItems?.count, 1)
        XCTAssertEqual(loadedDay.cooldownItems?.count, 1)
        XCTAssertEqual(loadedExercise.id, exerciseID)
        XCTAssertEqual(loadedExercise.createdAt, date)
        XCTAssertEqual(loadedExercise.updatedAt, date)
        XCTAssertEqual(loadedExercise.name, "Goblet Squat")
        XCTAssertEqual(loadedExercise.orderIndex, 1)
        XCTAssertEqual(loadedExercise.targetSets, 3)
        XCTAssertEqual(loadedExercise.repLow, 8)
        XCTAssertEqual(loadedExercise.repHigh, 12)
        XCTAssertEqual(loadedExercise.rirLow, 1)
        XCTAssertEqual(loadedExercise.rirHigh, 2)
        XCTAssertEqual(loadedExercise.category, .compound)
        XCTAssertFalse(loadedExercise.allowFailure)
        XCTAssertEqual(loadedExercise.cues, "Brace")
        XCTAssertEqual(loadedExercise.safetyNote, "Slow")
        XCTAssertEqual(loadedExercise.startingWeightKg, 0)
        XCTAssertEqual(loadedExercise.progressionRule, .doubleProgression)
        XCTAssertEqual(loadedExercise.measurementKind, .weightReps)
        XCTAssertNotNil(loadedExercise.supersetGroupId)
        XCTAssertEqual(loadedExercise.supersetOrder, 2)
        XCTAssertEqual(loadedExercise.workoutDayTemplate?.id, dayID)
        XCTAssertEqual(loadedWarmup.id, warmupID)
        XCTAssertEqual(loadedWarmup.createdAt, date)
        XCTAssertEqual(loadedWarmup.updatedAt, date)
        XCTAssertEqual(loadedWarmup.phase, .activate)
        XCTAssertEqual(loadedWarmup.movement, "Band")
        XCTAssertEqual(loadedWarmup.dose, "10 reps")
        XCTAssertEqual(loadedWarmup.orderIndex, 1)
        XCTAssertEqual(loadedWarmup.workoutDayTemplate?.id, dayID)
        XCTAssertEqual(loadedCooldown.id, cooldownID)
        XCTAssertEqual(loadedCooldown.createdAt, date)
        XCTAssertEqual(loadedCooldown.updatedAt, date)
        XCTAssertEqual(loadedCooldown.movement, "Walk")
        XCTAssertEqual(loadedCooldown.dose, "5 min")
        XCTAssertEqual(loadedCooldown.note, "Easy")
        XCTAssertEqual(loadedCooldown.orderIndex, 1)
        XCTAssertEqual(loadedCooldown.workoutDayTemplate?.id, dayID)
        XCTAssertEqual(loadedSession.id, sessionID)
        XCTAssertEqual(loadedSession.createdAt, date)
        XCTAssertEqual(loadedSession.updatedAt, date)
        XCTAssertEqual(loadedSession.date, date)
        XCTAssertEqual(loadedSession.status, .completed)
        XCTAssertEqual(loadedSession.workoutDayTemplateId, dayID)
        XCTAssertEqual(loadedSession.perceivedRecovery, 8)
        XCTAssertEqual(loadedSession.note, "Good")
        XCTAssertEqual(loadedSession.ohpSymptomResponse, .symptomFree)
        XCTAssertEqual(loadedSession.ohpSymptomCheckedAt, date)
        XCTAssertEqual(loadedSession.setLogs?.count, 1)
        XCTAssertEqual(loadedSetLog.id, setLogID)
        XCTAssertEqual(loadedSetLog.createdAt, date)
        XCTAssertEqual(loadedSetLog.updatedAt, date)
        XCTAssertEqual(loadedSetLog.exerciseTemplateId, exerciseID)
        XCTAssertEqual(loadedSetLog.setIndex, 1)
        XCTAssertEqual(loadedSetLog.weightKg, 0)
        XCTAssertEqual(loadedSetLog.reps, 10)
        XCTAssertNil(loadedSetLog.durationSec)
        XCTAssertNil(loadedSetLog.distanceSteps)
        XCTAssertEqual(loadedSetLog.performedVariant, "Band green")
        XCTAssertEqual(loadedSetLog.rir, 2)
        XCTAssertFalse(loadedSetLog.isWarmupSet)
        XCTAssertEqual(loadedSetLog.completedAt, date)
        XCTAssertEqual(loadedSetLog.workoutSession?.id, sessionID)
        XCTAssertEqual(loadedState.id, stateID)
        XCTAssertEqual(loadedState.createdAt, date)
        XCTAssertEqual(loadedState.updatedAt, date)
        XCTAssertEqual(loadedState.programId, programID)
        XCTAssertEqual(loadedState.currentPhaseId, phaseID)
        XCTAssertEqual(loadedState.phaseStartedAt, date)
        XCTAssertEqual(loadedState.trainingWeekIndex, 3)
        XCTAssertEqual(loadedState.deloadStatus, .recommended)
        XCTAssertEqual(loadedState.deloadReason, .scheduled)
        XCTAssertEqual(loadedState.deloadUpdatedAt, date)
        XCTAssertEqual(loadedState.lastDeloadSkippedAt, date)
        XCTAssertEqual(loadedState.lastDeloadAction, .stay)
    }

    func testPullUpStyleNilRepRangeSurvivesRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let exerciseID = UUID()
        context.insert(ExerciseTemplate(id: exerciseID, name: "Pull-up / band", repLow: nil, repHigh: nil, measurementKind: .reps))
        try context.save()

        let loadedExercise = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ExerciseTemplate>(predicate: #Predicate { $0.id == exerciseID })).first)
        XCTAssertNil(loadedExercise.repLow)
        XCTAssertNil(loadedExercise.repHigh)
    }

    func testDeletingProgramNullifiesChildrenWithoutDeletingHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let programID = UUID()
        let phaseID = UUID()
        let dayID = UUID()
        let sessionID = UUID()
        let exerciseID = UUID()
        let program = Program(id: programID)
        let phase = ProgramPhase(id: phaseID, program: program)
        let day = WorkoutDayTemplate(id: dayID, program: program)
        let session = WorkoutSession(id: sessionID, workoutDayTemplateId: dayID)
        let setLog = SetLog(exerciseTemplateId: exerciseID, workoutSession: session)
        context.insert(program)
        context.insert(phase)
        context.insert(day)
        context.insert(session)
        context.insert(setLog)
        try context.save()

        context.delete(program)
        try context.save()

        let readContext = ModelContext(container)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<ProgramPhase>(predicate: #Predicate { $0.id == phaseID })).first).program)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<WorkoutDayTemplate>(predicate: #Predicate { $0.id == dayID })).first).program)
        let loadedSession = try XCTUnwrap(readContext.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first)
        let loadedSetLog = try XCTUnwrap(readContext.fetch(FetchDescriptor<SetLog>()).first)
        XCTAssertEqual(loadedSession.workoutDayTemplateId, dayID)
        XCTAssertEqual(loadedSetLog.exerciseTemplateId, exerciseID)
        XCTAssertEqual(loadedSetLog.workoutSession?.id, sessionID)
    }

    func testDeletingWorkoutDayTemplateNullifiesItemsWithoutDeletingHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let dayID = UUID()
        let exerciseID = UUID()
        let warmupID = UUID()
        let cooldownID = UUID()
        let sessionID = UUID()
        let stableExerciseReference = UUID()
        let day = WorkoutDayTemplate(id: dayID)
        let exercise = ExerciseTemplate(id: exerciseID, workoutDayTemplate: day)
        let warmup = WarmupItem(id: warmupID, workoutDayTemplate: day)
        let cooldown = CooldownItem(id: cooldownID, workoutDayTemplate: day)
        let session = WorkoutSession(id: sessionID, workoutDayTemplateId: dayID)
        let setLog = SetLog(exerciseTemplateId: stableExerciseReference, workoutSession: session)
        context.insert(day)
        context.insert(exercise)
        context.insert(warmup)
        context.insert(cooldown)
        context.insert(session)
        context.insert(setLog)
        try context.save()

        context.delete(day)
        try context.save()

        let readContext = ModelContext(container)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<ExerciseTemplate>(predicate: #Predicate { $0.id == exerciseID })).first).workoutDayTemplate)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<WarmupItem>(predicate: #Predicate { $0.id == warmupID })).first).workoutDayTemplate)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<CooldownItem>(predicate: #Predicate { $0.id == cooldownID })).first).workoutDayTemplate)
        let loadedSession = try XCTUnwrap(readContext.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first)
        let loadedSetLog = try XCTUnwrap(readContext.fetch(FetchDescriptor<SetLog>()).first)
        XCTAssertEqual(loadedSession.workoutDayTemplateId, dayID)
        XCTAssertEqual(loadedSetLog.exerciseTemplateId, stableExerciseReference)
        XCTAssertEqual(loadedSetLog.workoutSession?.id, sessionID)
    }

    func testOptionalRelationshipsRoundTripWhenParentsAreMissing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let phase = ProgramPhase(name: "Orphan phase")
        let day = WorkoutDayTemplate(name: "Orphan day")
        let exercise = ExerciseTemplate(name: "Orphan exercise")
        let warmup = WarmupItem()
        let cooldown = CooldownItem()
        let setLog = SetLog()
        context.insert(phase)
        context.insert(day)
        context.insert(exercise)
        context.insert(warmup)
        context.insert(cooldown)
        context.insert(setLog)
        try context.save()

        let readContext = ModelContext(container)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<ProgramPhase>()).first).program)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<WorkoutDayTemplate>()).first).program)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<ExerciseTemplate>()).first).workoutDayTemplate)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<WarmupItem>()).first).workoutDayTemplate)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<CooldownItem>()).first).workoutDayTemplate)
        XCTAssertNil(try XCTUnwrap(readContext.fetch(FetchDescriptor<SetLog>()).first).workoutSession)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: UserProfile.self, Program.self, ProgramPhase.self, WorkoutDayTemplate.self,
            ExerciseTemplate.self, WarmupItem.self, CooldownItem.self, WorkoutSession.self,
            SetLog.self, ProgramState.self,
            configurations: configuration
        )
    }
}
