import CoreModels
import SwiftData
import XCTest

final class TrainingModelDefaultsTests: XCTestCase {
    func testDefaultsAndTypedRangeValidationRemainHydrationSafe() throws {
        XCTAssertEqual(UserProfile().weeklyWorkoutTarget, 3)
        XCTAssertEqual(ProgramState().trainingWeekIndex, 1)
        XCTAssertThrowsError(try TrainingModelValidator.validateWeeklyWorkoutTarget(0)) { error in
            XCTAssertEqual(error as? TrainingModelValidationError, .weeklyWorkoutTargetOutOfRange)
        }
        XCTAssertThrowsError(try TrainingModelValidator.validateWeeklyWorkoutTarget(8)) { error in
            XCTAssertEqual(error as? TrainingModelValidationError, .weeklyWorkoutTargetOutOfRange)
        }
        XCTAssertThrowsError(try TrainingModelValidator.validateTrainingWeekIndex(0)) { error in
            XCTAssertEqual(error as? TrainingModelValidationError, .trainingWeekIndexOutOfRange)
        }
        XCTAssertNoThrow(try TrainingModelValidator.validateWeeklyWorkoutTarget(1))
        XCTAssertNoThrow(try TrainingModelValidator.validateWeeklyWorkoutTarget(7))
        XCTAssertNoThrow(try TrainingModelValidator.validateTrainingWeekIndex(1))
    }

    func testSetLogPreservesNilMeasurementsZeroWeightAndPerformedVariant() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let setLog = SetLog(weightKg: 0, reps: nil, durationSec: nil, distanceSteps: nil, performedVariant: "Pallof")
        context.insert(setLog)
        try context.save()

        let roundTripped = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<SetLog>()).first)
        XCTAssertEqual(roundTripped.weightKg, 0)
        XCTAssertNil(roundTripped.reps)
        XCTAssertNil(roundTripped.durationSec)
        XCTAssertNil(roundTripped.distanceSteps)
        XCTAssertEqual(roundTripped.performedVariant, "Pallof")
        XCTAssertThrowsError(try roundTripped.validate(for: .quality))
        XCTAssertThrowsError(try roundTripped.validate(for: .weightReps))
    }

    func testDuplicateIDsPersistBecauseUniquenessIsRepositoryOwned() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let duplicatedID = UUID()
        context.insert(UserProfile(id: duplicatedID, displayName: "First"))
        context.insert(UserProfile(id: duplicatedID, displayName: "Second"))
        try context.save()

        let profiles = try ModelContext(container).fetch(FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == duplicatedID }))
        XCTAssertEqual(profiles.count, 2)
    }

    func testSetLogDelegatesRIRRangeValidationToCentralValidator() {
        let setLog = SetLog(weightKg: 0, reps: 8, rir: 11)
        XCTAssertThrowsError(try setLog.validate(for: .weightReps))
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
