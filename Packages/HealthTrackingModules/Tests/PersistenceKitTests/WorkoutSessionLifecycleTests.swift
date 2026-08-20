import CoreModels
import Foundation
@testable import PersistenceKit
import SwiftData
import TrainingKit
import XCTest

@MainActor
final class WorkoutSessionLifecycleTests: XCTestCase {
    func testLegalTransitionsSucceedAndTerminalOrInProgressSkipTransitionsFail() async throws {
        let repository = try makeRepository()
        let dayID = uuid("00000000-0000-0000-0000-000000000101")
        let completedID = uuid("00000000-0000-0000-0000-000000000102")
        let skippedID = uuid("00000000-0000-0000-0000-000000000103")
        let interruptedID = uuid("00000000-0000-0000-0000-000000000104")
        let startedAt = Date(timeIntervalSinceReferenceDate: 20_000)

        let planned = try await repository.createWorkoutSession(
            .init(id: completedID, date: startedAt, workoutDayTemplateID: dayID)
        )
        XCTAssertEqual(planned.status, .planned)
        let inProgress = try await repository.transitionWorkoutSession(
            id: completedID,
            to: .inProgress,
            at: startedAt.addingTimeInterval(1)
        )
        XCTAssertEqual(inProgress.status, .inProgress)
        let completed = try await repository.transitionWorkoutSession(
            id: completedID,
            to: .completed,
            at: startedAt.addingTimeInterval(2)
        )
        XCTAssertEqual(completed.status, .completed)
        await assertTransitionError(
            repository,
            id: completedID,
            from: .completed,
            to: .inProgress
        )

        _ = try await repository.createWorkoutSession(
            .init(id: skippedID, date: startedAt, workoutDayTemplateID: dayID)
        )
        let skipped = try await repository.transitionWorkoutSession(
            id: skippedID,
            to: .skipped,
            at: startedAt.addingTimeInterval(3)
        )
        XCTAssertEqual(skipped.status, .skipped)
        await assertTransitionError(
            repository,
            id: skippedID,
            from: .skipped,
            to: .inProgress
        )

        _ = try await repository.createWorkoutSession(
            .init(id: interruptedID, date: startedAt, workoutDayTemplateID: dayID)
        )
        _ = try await repository.transitionWorkoutSession(
            id: interruptedID,
            to: .inProgress,
            at: startedAt.addingTimeInterval(4)
        )
        await assertTransitionError(
            repository,
            id: interruptedID,
            from: .inProgress,
            to: .skipped
        )
    }

    func testRepositoryEnforcesAndReadsAtMostOneInProgressSession() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))
        let date = Date(timeIntervalSinceReferenceDate: 21_000)
        let firstID = uuid("00000000-0000-0000-0000-000000000111")
        let secondID = uuid("00000000-0000-0000-0000-000000000112")
        let dayID = uuid("00000000-0000-0000-0000-000000000113")
        _ = try await repository.createWorkoutSession(
            .init(id: firstID, date: date, workoutDayTemplateID: dayID)
        )
        _ = try await repository.createWorkoutSession(
            .init(id: secondID, date: date, workoutDayTemplateID: dayID)
        )
        _ = try await repository.transitionWorkoutSession(id: firstID, to: .inProgress, at: date)

        let activeSession = try await repository.fetchInProgressWorkoutSession()
        XCTAssertEqual(activeSession?.id, firstID)
        do {
            _ = try await repository.transitionWorkoutSession(
                id: secondID,
                to: .inProgress,
                at: date
            )
            XCTFail("Expected a second in-progress session to fail")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryIntegrityError,
                .inProgressSessionAlreadyExists(existingID: firstID)
            )
        }

        let corruptContext = ModelContext(container)
        corruptContext.insert(
            WorkoutSession(
                id: uuid("00000000-0000-0000-0000-000000000114"),
                status: .inProgress,
                workoutDayTemplateId: dayID
            )
        )
        try corruptContext.save()
        do {
            _ = try await SwiftDataTrainingRepository(
                modelContext: ModelContext(container)
            ).fetchInProgressWorkoutSession()
            XCTFail("Expected duplicate in-progress integrity failure")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryIntegrityError,
                .duplicateInProgressWorkoutSessions(count: 2)
            )
        }
    }

    func testProgressSaveCreatesThenUpdatesOneRowPerSession() async throws {
        let fixture = try makeSessionFixture()
        let progressID = uuid("00000000-0000-0000-0000-000000000121")
        let warmupID = uuid("00000000-0000-0000-0000-000000000122")
        let exerciseID = uuid("00000000-0000-0000-0000-000000000123")
        let first = WorkoutSessionProgressUpdate(
            id: progressID,
            workoutSessionID: fixture.sessionID,
            stage: .warmup,
            completedWarmupItemIDs: [warmupID],
            warmupDisposition: .pending,
            updatedAt: Date(timeIntervalSinceReferenceDate: 22_000)
        )
        let second = WorkoutSessionProgressUpdate(
            id: UUID(),
            workoutSessionID: fixture.sessionID,
            stage: .movement,
            currentExerciseTemplateID: exerciseID,
            completedWarmupItemIDs: [warmupID],
            warmupDisposition: .completed,
            updatedAt: Date(timeIntervalSinceReferenceDate: 22_100)
        )

        let created = try await fixture.repository.saveWorkoutSessionProgress(first)
        XCTAssertEqual(created.id, progressID)
        let updated = try await fixture.repository.saveWorkoutSessionProgress(second)

        XCTAssertEqual(updated.id, progressID)
        XCTAssertEqual(updated.stage, .movement)
        XCTAssertEqual(updated.currentExerciseTemplateID, exerciseID)
        XCTAssertEqual(updated.completedWarmupItemIDs, [warmupID])
        XCTAssertEqual(updated.warmupDisposition, .completed)
        XCTAssertEqual(
            try ModelContext(fixture.container).fetchCount(
                FetchDescriptor<WorkoutSessionProgress>()
            ),
            1
        )
    }

    func testDuplicateProgressRowsAndCorruptPayloadsProduceErrorsWithoutDeletingData() async throws {
        let fixture = try makeSessionFixture()
        let context = ModelContext(fixture.container)
        let valid = try WorkoutSessionProgressCodec.encode([])
        context.insert(
            WorkoutSessionProgress(
                workoutSessionId: fixture.sessionID,
                completedWarmupItemIdsData: valid,
                completedCooldownItemIdsData: valid
            )
        )
        context.insert(
            WorkoutSessionProgress(
                workoutSessionId: fixture.sessionID,
                completedWarmupItemIdsData: valid,
                completedCooldownItemIdsData: valid
            )
        )
        try context.save()

        do {
            _ = try await fixture.repository.fetchWorkoutSessionProgress(
                sessionID: fixture.sessionID
            )
            XCTFail("Expected duplicate progress integrity failure")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryIntegrityError,
                .duplicateWorkoutSessionProgress(
                    workoutSessionID: fixture.sessionID,
                    count: 2
                )
            )
        }

        for progress in try context.fetch(FetchDescriptor<WorkoutSessionProgress>()) {
            context.delete(progress)
        }
        context.insert(
            WorkoutSessionProgress(
                workoutSessionId: fixture.sessionID,
                completedWarmupItemIdsData: Data("{".utf8),
                completedCooldownItemIdsData: valid
            )
        )
        try context.save()

        do {
            _ = try await fixture.repository.fetchWorkoutSessionProgress(
                sessionID: fixture.sessionID
            )
            XCTFail("Expected corrupt progress payload failure")
        } catch {
            XCTAssertEqual(error as? WorkoutSessionProgressCodecError, .malformedPayload)
        }
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<WorkoutSessionProgress>()),
            1
        )
    }

    func testSetAndProgressMutationsSurviveRepositoryAndContainerRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("lifecycle.store")
        let sessionID = uuid("00000000-0000-0000-0000-000000000131")
        let exerciseID = uuid("00000000-0000-0000-0000-000000000132")
        let setID = uuid("00000000-0000-0000-0000-000000000133")
        let warmupID = uuid("00000000-0000-0000-0000-000000000134")

        try await writeLifecycleStore(
            at: storeURL,
            sessionID: sessionID,
            exerciseID: exerciseID,
            setID: setID,
            warmupID: warmupID
        )

        let reopened = try ModelContainerFactory.make(for: .local(storeURL: storeURL))
        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(reopened))
        let sets = try await repository.fetchSetLogs(workoutSessionID: sessionID)
        let progressResult = try await repository.fetchWorkoutSessionProgress(
            sessionID: sessionID
        )
        let progress = try XCTUnwrap(progressResult)

        XCTAssertEqual(sets.map(\.id), [setID])
        XCTAssertEqual(sets.first?.measurement, .init(weightKg: 10, reps: 8, rir: 2))
        XCTAssertEqual(progress.stage, .movement)
        XCTAssertEqual(progress.completedWarmupItemIDs, [warmupID])
    }

    func testIncompleteCompletionKeepsValidSetsAndCreatesNoPlaceholder() async throws {
        let fixture = try makeSessionFixture(kind: .reps)
        let setID = uuid("00000000-0000-0000-0000-000000000141")
        _ = try await fixture.repository.saveSet(
            .init(
                id: setID,
                workoutSessionID: fixture.sessionID,
                exerciseTemplateID: fixture.exerciseID,
                setIndex: 1,
                measurement: .init(reps: 8),
                completedAt: Date(timeIntervalSinceReferenceDate: 24_000)
            )
        )

        _ = try await fixture.repository.transitionWorkoutSession(
            id: fixture.sessionID,
            to: .completed,
            at: Date(timeIntervalSinceReferenceDate: 24_100)
        )

        let sets = try await fixture.repository.fetchSetLogs(
            workoutSessionID: fixture.sessionID
        )
        XCTAssertEqual(sets.map(\.id), [setID])
    }

    func testSessionDeletionCleansSetsAndProgressIdempotently() async throws {
        let fixture = try makeSessionFixture(kind: .reps)
        _ = try await fixture.repository.saveSet(
            .init(
                workoutSessionID: fixture.sessionID,
                exerciseTemplateID: fixture.exerciseID,
                setIndex: 1,
                measurement: .init(reps: 8),
                completedAt: Date(timeIntervalSinceReferenceDate: 25_000)
            )
        )
        _ = try await fixture.repository.saveWorkoutSessionProgress(
            .init(
                workoutSessionID: fixture.sessionID,
                stage: .movement,
                currentExerciseTemplateID: fixture.exerciseID,
                updatedAt: Date(timeIntervalSinceReferenceDate: 25_000)
            )
        )

        try await fixture.repository.deleteWorkoutSession(id: fixture.sessionID)
        try await fixture.repository.deleteWorkoutSession(id: fixture.sessionID)

        let context = ModelContext(fixture.container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSessionProgress>()), 0)
    }

    private func assertTransitionError(
        _ repository: SwiftDataTrainingRepository,
        id: UUID,
        from: WorkoutSessionStatus,
        to: WorkoutSessionStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await repository.transitionWorkoutSession(id: id, to: to, at: .now)
            XCTFail("Expected illegal transition", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryMutationError,
                .illegalWorkoutSessionTransition(id: id, from: from, to: to),
                file: file,
                line: line
            )
        }
    }

    private func makeRepository() throws -> SwiftDataTrainingRepository {
        let container = try ModelContainerFactory.make(for: .inMemory)
        return SwiftDataTrainingRepository(modelContext: ModelContext(container))
    }

    private func makeSessionFixture(
        kind: ExerciseMeasurementKind = .weightReps
    ) throws -> (
        container: ModelContainer,
        repository: SwiftDataTrainingRepository,
        sessionID: UUID,
        exerciseID: UUID
    ) {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let sessionID = UUID()
        let exerciseID = UUID()
        context.insert(
            WorkoutSession(
                id: sessionID,
                status: .inProgress,
                workoutDayTemplateId: UUID()
            )
        )
        context.insert(ExerciseTemplate(id: exerciseID, measurementKind: kind))
        try context.save()
        return (
            container,
            SwiftDataTrainingRepository(modelContext: ModelContext(container)),
            sessionID,
            exerciseID
        )
    }

    private func writeLifecycleStore(
        at storeURL: URL,
        sessionID: UUID,
        exerciseID: UUID,
        setID: UUID,
        warmupID: UUID
    ) async throws {
        let container = try ModelContainerFactory.make(for: .local(storeURL: storeURL))
        let context = ModelContext(container)
        context.insert(
            WorkoutSession(
                id: sessionID,
                status: .inProgress,
                workoutDayTemplateId: UUID()
            )
        )
        context.insert(
            ExerciseTemplate(id: exerciseID, measurementKind: .weightReps)
        )
        try context.save()
        let repository = SwiftDataTrainingRepository(modelContext: ModelContext(container))
        _ = try await repository.saveSet(
            .init(
                id: setID,
                workoutSessionID: sessionID,
                exerciseTemplateID: exerciseID,
                setIndex: 1,
                measurement: .init(weightKg: 10, reps: 8, rir: 2),
                completedAt: Date(timeIntervalSinceReferenceDate: 23_000)
            )
        )
        _ = try await repository.saveWorkoutSessionProgress(
            .init(
                workoutSessionID: sessionID,
                stage: .movement,
                currentExerciseTemplateID: exerciseID,
                completedWarmupItemIDs: [warmupID],
                warmupDisposition: .completed,
                updatedAt: Date(timeIntervalSinceReferenceDate: 23_000)
            )
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
