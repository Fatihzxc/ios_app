import CoreModels
import Foundation
@testable import PersistenceKit
import SwiftData
import TrainingKit
import XCTest

@MainActor
final class TrainingHistoryRepositoryTests: XCTestCase {
    func testHistoryUsesReverseChronologyUUIDTieBreakAndStableNestedOrdering() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let day = WorkoutDayTemplate(name: "Gün A", focus: "Tam vücut")
        let laterExercise = ExerciseTemplate(
            id: uuid("00000000-0000-4000-8000-000000000d04"),
            name: "İkinci hareket",
            orderIndex: 2,
            measurementKind: .reps,
            workoutDayTemplate: day
        )
        let firstExercise = ExerciseTemplate(
            id: uuid("00000000-0000-4000-8000-000000000d03"),
            name: "İlk hareket",
            orderIndex: 1,
            measurementKind: .reps,
            workoutDayTemplate: day
        )
        let sharedDate = Date(timeIntervalSinceReferenceDate: 40_000)
        let firstAtTie = WorkoutSession(
            id: uuid("00000000-0000-4000-8000-000000000d01"),
            date: sharedDate,
            status: .completed,
            workoutDayTemplateId: day.id
        )
        let secondAtTie = WorkoutSession(
            id: uuid("00000000-0000-4000-8000-000000000d02"),
            date: sharedDate,
            status: .completed,
            workoutDayTemplateId: day.id
        )
        let older = WorkoutSession(
            id: uuid("00000000-0000-4000-8000-000000000d05"),
            date: sharedDate.addingTimeInterval(-1),
            status: .completed,
            workoutDayTemplateId: day.id
        )
        let activeDecoy = WorkoutSession(
            date: sharedDate.addingTimeInterval(100),
            status: .inProgress,
            workoutDayTemplateId: day.id
        )
        context.insert(day)
        context.insert(firstExercise)
        context.insert(laterExercise)
        context.insert(firstAtTie)
        context.insert(secondAtTie)
        context.insert(older)
        context.insert(activeDecoy)
        context.insert(
            set(
                id: uuid("00000000-0000-4000-8000-000000000d12"),
                session: firstAtTie,
                exerciseID: firstExercise.id,
                index: 2,
                reps: 9
            )
        )
        context.insert(
            set(
                id: uuid("00000000-0000-4000-8000-000000000d11"),
                session: firstAtTie,
                exerciseID: firstExercise.id,
                index: 1,
                reps: 8
            )
        )
        context.insert(
            set(
                id: uuid("00000000-0000-4000-8000-000000000d13"),
                session: firstAtTie,
                exerciseID: laterExercise.id,
                index: 1,
                reps: 10
            )
        )
        try context.save()

        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))
        let history = try await repository.fetchTrainingHistory()

        XCTAssertEqual(history.map(\.id), [firstAtTie.id, secondAtTie.id, older.id])
        XCTAssertEqual(history[0].workoutDayName, "Gün A")
        XCTAssertEqual(history[0].workoutDayFocus, "Tam vücut")
        XCTAssertEqual(
            history[0].exercises.map(\.exerciseTemplateID),
            [firstExercise.id, laterExercise.id]
        )
        XCTAssertEqual(history[0].exercises[0].setLogs.map(\.setIndex), [1, 2])
    }

    func testMissingDayAndExerciseTemplatesRemainRecoverableHistory() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let missingDayID = uuid("00000000-0000-4000-8000-000000000d21")
        let missingExerciseID = uuid("00000000-0000-4000-8000-000000000d22")
        let session = WorkoutSession(
            date: Date(timeIntervalSinceReferenceDate: 41_000),
            status: .completed,
            workoutDayTemplateId: missingDayID
        )
        context.insert(session)
        context.insert(
            set(
                id: uuid("00000000-0000-4000-8000-000000000d23"),
                session: session,
                exerciseID: missingExerciseID,
                index: 1,
                reps: 7
            )
        )
        try context.save()

        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))
        let history = try await repository.fetchTrainingHistory()

        XCTAssertEqual(history.count, 1)
        XCTAssertNil(history[0].workoutDayName)
        XCTAssertNil(history[0].workoutDayFocus)
        XCTAssertEqual(history[0].exercises.count, 1)
        XCTAssertEqual(history[0].exercises[0].exerciseTemplateID, missingExerciseID)
        XCTAssertNil(history[0].exercises[0].exercise)
        XCTAssertEqual(history[0].exercises[0].setLogs.count, 1)
    }

    func testSetEditUsesCentralValidationUpdatesTimestampsAndRollsBackFailure() async throws {
        let fixture = try makeEditableFixture()
        let invalidDate = fixture.originalDate.addingTimeInterval(100)

        do {
            _ = try await fixture.repository.updateSet(
                SetLogUpdateRequest(
                    id: fixture.setID,
                    measurement: .init(weightKg: 20, reps: 0),
                    updatedAt: invalidDate
                )
            )
            XCTFail("Invalid history edit must fail.")
        } catch {
            XCTAssertEqual(
                error as? SetMeasurementValidationError,
                .invalidMeasurement
            )
        }
        let logsAfterRejectedEdit = try await fixture.repository
            .fetchSetLogs(workoutSessionID: fixture.sessionID)
        var stored = try XCTUnwrap(logsAfterRejectedEdit.first)
        XCTAssertEqual(stored.measurement, .init(weightKg: 10, reps: 8, rir: 2))
        XCTAssertEqual(stored.updatedAt, fixture.originalDate)

        let editedAt = fixture.originalDate.addingTimeInterval(200)
        let edited = try await fixture.repository.updateSet(
            SetLogUpdateRequest(
                id: fixture.setID,
                measurement: .init(weightKg: 20, reps: 10, rir: 1),
                updatedAt: editedAt
            )
        )
        XCTAssertEqual(edited.id, fixture.setID)
        XCTAssertEqual(edited.createdAt, fixture.originalDate)
        XCTAssertEqual(edited.completedAt, fixture.originalDate)
        XCTAssertEqual(edited.updatedAt, editedAt)
        XCTAssertEqual(edited.measurement, .init(weightKg: 20, reps: 10, rir: 1))

        let logsAfterEdit = try await SwiftDataTrainingRepository(
            modelContext: ModelContext(fixture.container)
        ).fetchSetLogs(workoutSessionID: fixture.sessionID)
        stored = try XCTUnwrap(logsAfterEdit.first)
        XCTAssertEqual(stored, edited)
        let session = try XCTUnwrap(
            try ModelContext(fixture.container)
                .fetch(FetchDescriptor<WorkoutSession>())
                .first
        )
        XCTAssertEqual(session.updatedAt, editedAt)
    }

    func testSetDeleteIsIdempotentAndSessionDeleteCleansAllChildren() async throws {
        let fixture = try makeEditableFixture()
        let progressContext = ModelContext(fixture.container)
        progressContext.insert(
            WorkoutSessionProgress(workoutSessionId: fixture.sessionID)
        )
        try progressContext.save()
        let deletedAt = fixture.originalDate.addingTimeInterval(300)

        try await fixture.repository.deleteSet(id: fixture.setID, at: deletedAt)
        try await fixture.repository.deleteSet(id: fixture.setID, at: deletedAt)
        let logsAfterDelete = try await fixture.repository
            .fetchSetLogs(workoutSessionID: fixture.sessionID)
        XCTAssertTrue(logsAfterDelete.isEmpty)
        let sessionContext = ModelContext(fixture.container)
        XCTAssertEqual(
            try XCTUnwrap(sessionContext.fetch(FetchDescriptor<WorkoutSession>()).first)
                .updatedAt,
            deletedAt
        )

        try await fixture.repository.deleteWorkoutSession(id: fixture.sessionID)
        try await fixture.repository.deleteWorkoutSession(id: fixture.sessionID)
        let verificationContext = ModelContext(fixture.container)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<SetLog>()), 0)
        XCTAssertEqual(
            try verificationContext.fetchCount(FetchDescriptor<WorkoutSessionProgress>()),
            0
        )
    }

    private func makeEditableFixture() throws -> EditableFixture {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let originalDate = Date(timeIntervalSinceReferenceDate: 42_000)
        let day = WorkoutDayTemplate(name: "Gün A")
        let exercise = ExerciseTemplate(
            name: "Goblet Squat",
            measurementKind: .weightReps,
            workoutDayTemplate: day
        )
        let session = WorkoutSession(
            createdAt: originalDate,
            updatedAt: originalDate,
            date: originalDate,
            status: .completed,
            workoutDayTemplateId: day.id
        )
        let setID = uuid("00000000-0000-4000-8000-000000000d31")
        context.insert(day)
        context.insert(exercise)
        context.insert(session)
        context.insert(
            SetLog(
                id: setID,
                createdAt: originalDate,
                updatedAt: originalDate,
                exerciseTemplateId: exercise.id,
                setIndex: 1,
                weightKg: 10,
                reps: 8,
                rir: 2,
                completedAt: originalDate,
                workoutSession: session
            )
        )
        try context.save()
        return EditableFixture(
            container: container,
            repository: SwiftDataTrainingRepository(modelContext: ModelContext(container)),
            sessionID: session.id,
            setID: setID,
            originalDate: originalDate
        )
    }

    private func set(
        id: UUID,
        session: WorkoutSession,
        exerciseID: UUID,
        index: Int,
        reps: Int
    ) -> SetLog {
        SetLog(
            id: id,
            exerciseTemplateId: exerciseID,
            setIndex: index,
            reps: reps,
            completedAt: session.date,
            workoutSession: session
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

@MainActor
private struct EditableFixture {
    let container: ModelContainer
    let repository: SwiftDataTrainingRepository
    let sessionID: UUID
    let setID: UUID
    let originalDate: Date
}
