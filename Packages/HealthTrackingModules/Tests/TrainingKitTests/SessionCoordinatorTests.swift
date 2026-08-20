import CoreModels
import Foundation
import TrainingKit
import XCTest

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    func testRestoreUsesStoredStageExerciseAndChecklistState() async throws {
        let repository = FakeLifecycleRepository()
        let session = makeSession()
        let exerciseID = uuid("00000000-0000-0000-0000-000000000201")
        let warmupID = uuid("00000000-0000-0000-0000-000000000202")
        let cooldownID = uuid("00000000-0000-0000-0000-000000000203")
        let progress = WorkoutSessionProgressSnapshot(
            id: uuid("00000000-0000-0000-0000-000000000204"),
            createdAt: Date(timeIntervalSinceReferenceDate: 30_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 30_100),
            workoutSessionID: session.id,
            stage: .movement,
            currentExerciseTemplateID: exerciseID,
            completedWarmupItemIDs: [warmupID],
            completedCooldownItemIDs: [cooldownID],
            warmupDisposition: .completed,
            cooldownDisposition: .pending
        )
        repository.inProgressSession = session
        repository.progressResult = .success(progress)
        repository.exercises = [
            .init(id: exerciseID, orderIndex: 1, targetSets: 3)
        ]
        let coordinator = SessionCoordinator(repository: repository)

        let result = try await coordinator.restoreInProgressSession()
        let restored = try XCTUnwrap(result)

        XCTAssertEqual(restored.session, session)
        XCTAssertEqual(restored.state, progress.state)
        XCTAssertEqual(restored.source, .stored)
        XCTAssertEqual(repository.fetchSetLogsCallCount, 0)
    }

    func testMissingProgressWithoutSetsFallsBackToWarmup() async throws {
        let repository = FakeLifecycleRepository()
        let session = makeSession()
        repository.inProgressSession = session
        repository.progressResult = .success(nil)
        repository.exercises = [
            .init(id: UUID(), orderIndex: 1, targetSets: 3)
        ]
        let coordinator = SessionCoordinator(repository: repository)

        let result = try await coordinator.restoreInProgressSession()
        let restored = try XCTUnwrap(result)

        XCTAssertEqual(restored.state.stage, .warmup)
        XCTAssertNil(restored.state.currentExerciseTemplateID)
        XCTAssertEqual(restored.source, .inferredMissingProgress)
    }

    func testMissingProgressUsesFirstIncompleteExerciseThenCooldownWhenAllSetsExist() async throws {
        let session = makeSession()
        let firstID = uuid("00000000-0000-0000-0000-000000000211")
        let secondID = uuid("00000000-0000-0000-0000-000000000212")
        let exercises = [
            SessionExerciseSnapshot(id: secondID, orderIndex: 2, targetSets: 2),
            SessionExerciseSnapshot(id: firstID, orderIndex: 1, targetSets: 2)
        ]
        let firstComplete = [
            makeSet(sessionID: session.id, exerciseID: firstID, index: 1),
            makeSet(sessionID: session.id, exerciseID: firstID, index: 2)
        ]
        let repository = FakeLifecycleRepository()
        repository.inProgressSession = session
        repository.progressResult = .success(nil)
        repository.exercises = exercises
        repository.setLogs = firstComplete + [
            makeSet(sessionID: session.id, exerciseID: secondID, index: 1)
        ]
        let coordinator = SessionCoordinator(repository: repository)

        let movementResult = try await coordinator.restoreInProgressSession()
        let movement = try XCTUnwrap(movementResult)
        XCTAssertEqual(movement.state.stage, .movement)
        XCTAssertEqual(movement.state.currentExerciseTemplateID, secondID)

        repository.setLogs.append(
            makeSet(sessionID: session.id, exerciseID: secondID, index: 2)
        )
        let cooldownResult = try await coordinator.restoreInProgressSession()
        let cooldown = try XCTUnwrap(cooldownResult)
        XCTAssertEqual(cooldown.state.stage, .cooldown)
        XCTAssertNil(cooldown.state.currentExerciseTemplateID)
    }

    func testCorruptProgressFallsBackFromSetHistoryWithoutDeletingSafeData() async throws {
        let repository = FakeLifecycleRepository()
        let session = makeSession()
        let exerciseID = uuid("00000000-0000-0000-0000-000000000221")
        repository.inProgressSession = session
        repository.progressResult = .failure(WorkoutSessionProgressCodecError.malformedPayload)
        repository.exercises = [.init(id: exerciseID, orderIndex: 1, targetSets: 3)]
        repository.setLogs = [makeSet(sessionID: session.id, exerciseID: exerciseID, index: 1)]
        let coordinator = SessionCoordinator(repository: repository)

        let result = try await coordinator.restoreInProgressSession()
        let restored = try XCTUnwrap(result)

        XCTAssertEqual(restored.state.stage, .movement)
        XCTAssertEqual(restored.state.currentExerciseTemplateID, exerciseID)
        XCTAssertEqual(restored.source, .inferredCorruptProgress)
        XCTAssertEqual(repository.deleteWorkoutSessionCallCount, 0)
        XCTAssertEqual(repository.setLogs.count, 1)
    }

    func testDeletedCurrentExerciseReferenceUsesSafeHistoryFallback() async throws {
        let repository = FakeLifecycleRepository()
        let session = makeSession()
        let deletedID = uuid("00000000-0000-0000-0000-000000000231")
        let remainingID = uuid("00000000-0000-0000-0000-000000000232")
        repository.inProgressSession = session
        repository.progressResult = .success(
            WorkoutSessionProgressSnapshot(
                id: UUID(),
                createdAt: .now,
                updatedAt: .now,
                workoutSessionID: session.id,
                stage: .movement,
                currentExerciseTemplateID: deletedID
            )
        )
        repository.exercises = [.init(id: remainingID, orderIndex: 2, targetSets: 2)]
        let coordinator = SessionCoordinator(repository: repository)

        let result = try await coordinator.restoreInProgressSession()
        let restored = try XCTUnwrap(result)

        XCTAssertEqual(restored.state.stage, .warmup)
        XCTAssertNil(restored.state.currentExerciseTemplateID)
        XCTAssertEqual(restored.source, .inferredMissingExerciseReference)
        XCTAssertEqual(repository.deleteWorkoutSessionCallCount, 0)
    }

    func testBeginSessionResumesExistingOrCreatesAndStartsPlannedSession() async throws {
        let repository = FakeLifecycleRepository()
        let existing = makeSession()
        repository.inProgressSession = existing
        let coordinator = SessionCoordinator(repository: repository)
        let request = WorkoutSessionCreateRequest(
            id: UUID(),
            date: .now,
            workoutDayTemplateID: UUID()
        )

        let resumed = try await coordinator.beginSession(request)
        XCTAssertEqual(resumed, existing)
        XCTAssertEqual(repository.createWorkoutSessionCallCount, 0)

        repository.inProgressSession = nil
        let planned = WorkoutSessionSnapshot(
            id: request.id,
            date: request.date,
            status: .planned,
            workoutDayTemplateID: request.workoutDayTemplateID
        )
        let started = WorkoutSessionSnapshot(
            id: request.id,
            date: request.date,
            status: .inProgress,
            workoutDayTemplateID: request.workoutDayTemplateID
        )
        repository.createdSession = planned
        repository.transitionedSession = started

        let newlyStarted = try await coordinator.beginSession(request)
        XCTAssertEqual(newlyStarted, started)
        XCTAssertEqual(repository.createWorkoutSessionCallCount, 1)
        XCTAssertEqual(repository.transitionWorkoutSessionCallCount, 1)
    }

    func testRestoreReturnsNilWithoutAnInProgressSessionAndPublicValuesAreSendable() async throws {
        let repository = FakeLifecycleRepository()
        let coordinator = SessionCoordinator(repository: repository)

        let restored = try await coordinator.restoreInProgressSession()
        XCTAssertNil(restored)
        assertEquatableSendable(SessionRestoreSource.stored)
        assertEquatableSendable(SessionProgressState(stage: .summary))
        assertEquatableSendable(makeSession())
    }

    private func makeSession() -> WorkoutSessionSnapshot {
        WorkoutSessionSnapshot(
            id: uuid("00000000-0000-0000-0000-000000000200"),
            date: Date(timeIntervalSinceReferenceDate: 30_000),
            status: .inProgress,
            workoutDayTemplateID: uuid("00000000-0000-0000-0000-000000000299")
        )
    }

    private func makeSet(
        sessionID: UUID,
        exerciseID: UUID,
        index: Int
    ) -> SetLogSnapshot {
        let date = Date(timeIntervalSinceReferenceDate: Double(31_000 + index))
        return SetLogSnapshot(
            id: UUID(),
            createdAt: date,
            updatedAt: date,
            workoutSessionID: sessionID,
            exerciseTemplateID: exerciseID,
            setIndex: index,
            measurement: .init(reps: 8),
            isWarmupSet: false,
            completedAt: date
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}
}

@MainActor
private final class FakeLifecycleRepository: TrainingRepository {
    var inProgressSession: WorkoutSessionSnapshot?
    var progressResult: Result<WorkoutSessionProgressSnapshot?, Error> = .success(nil)
    var exercises: [SessionExerciseSnapshot] = []
    var setLogs: [SetLogSnapshot] = []
    var createdSession: WorkoutSessionSnapshot?
    var transitionedSession: WorkoutSessionSnapshot?

    private(set) var fetchSetLogsCallCount = 0
    private(set) var createWorkoutSessionCallCount = 0
    private(set) var transitionWorkoutSessionCallCount = 0
    private(set) var deleteWorkoutSessionCallCount = 0

    func fetchUserProfile() async throws -> UserProfile? { nil }
    func fetchActiveProgram() async throws -> Program? { nil }
    func fetchProgramPhases(programID: UUID) async throws -> [ProgramPhase] { [] }
    func fetchWorkoutDays(programID: UUID) async throws -> [WorkoutDayTemplate] { [] }
    func fetchExerciseTemplates(workoutDayID: UUID) async throws -> [ExerciseTemplate] { [] }
    func fetchWarmupItems(workoutDayID: UUID) async throws -> [WarmupItem] { [] }
    func fetchCooldownItems(workoutDayID: UUID) async throws -> [CooldownItem] { [] }
    func fetchHealthCheckReminders() async throws -> [HealthCheckReminder] { [] }
    func fetchProgramState(programID: UUID) async throws -> ProgramState? { nil }

    func saveSet(_ request: SetLogSaveRequest) async throws -> SetLogSnapshot {
        throw FakeLifecycleError.unexpectedCall("saveSet")
    }

    func createWorkoutSession(
        _ request: WorkoutSessionCreateRequest
    ) async throws -> WorkoutSessionSnapshot {
        createWorkoutSessionCallCount += 1
        guard let createdSession else {
            throw FakeLifecycleError.unexpectedCall("createWorkoutSession")
        }
        return createdSession
    }

    func fetchInProgressWorkoutSession() async throws -> WorkoutSessionSnapshot? {
        inProgressSession
    }

    func transitionWorkoutSession(
        id: UUID,
        to status: WorkoutSessionStatus,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        transitionWorkoutSessionCallCount += 1
        guard let transitionedSession else {
            throw FakeLifecycleError.unexpectedCall("transitionWorkoutSession")
        }
        return transitionedSession
    }

    func fetchWorkoutSessionProgress(
        sessionID: UUID
    ) async throws -> WorkoutSessionProgressSnapshot? {
        try progressResult.get()
    }

    func saveWorkoutSessionProgress(
        _ update: WorkoutSessionProgressUpdate
    ) async throws -> WorkoutSessionProgressSnapshot {
        throw FakeLifecycleError.unexpectedCall("saveWorkoutSessionProgress")
    }

    func fetchSessionExercises(
        workoutDayID: UUID
    ) async throws -> [SessionExerciseSnapshot] {
        exercises
    }

    func fetchSessionPlan(
        workoutDayID: UUID
    ) async throws -> SessionWorkoutPlanSnapshot? {
        throw FakeLifecycleError.unexpectedCall("fetchSessionPlan")
    }

    func fetchSetLogs(workoutSessionID: UUID) async throws -> [SetLogSnapshot] {
        fetchSetLogsCallCount += 1
        return setLogs
    }

    func fetchCompletedExerciseHistory(
        exerciseTemplateID: UUID
    ) async throws -> [CompletedExerciseHistorySnapshot] {
        []
    }

    func fetchWeeklyPallofHistory() async throws -> WeeklyPallofHistorySnapshot {
        WeeklyPallofHistorySnapshot(
            eligibleExerciseTemplateIDs: [],
            completions: []
        )
    }

    func fetchOHPSafeAlternative() async throws -> SessionExerciseSnapshot {
        throw FakeLifecycleError.unexpectedCall("fetchOHPSafeAlternative")
    }

    func updateWorkoutSessionOHPSymptomResponse(
        id: UUID,
        response: OHPSymptomResponse,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        throw FakeLifecycleError.unexpectedCall("updateWorkoutSessionOHPSymptomResponse")
    }

    func updateWorkoutSessionSummary(
        id: UUID,
        perceivedRecovery: Int?,
        note: String?,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        throw FakeLifecycleError.unexpectedCall("updateWorkoutSessionSummary")
    }

    func deleteWorkoutSession(id: UUID) async throws {
        deleteWorkoutSessionCallCount += 1
    }
}

private enum FakeLifecycleError: Error {
    case unexpectedCall(String)
}
