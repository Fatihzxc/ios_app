import CoreModels
import Foundation
import TrainingKit
import XCTest

@MainActor
final class TrainingHistoryViewModelTests: XCTestCase {
    private let dayID = UUID(uuidString: "00000000-0000-4000-8000-000000000e01")!
    private let exerciseID = UUID(uuidString: "00000000-0000-4000-8000-000000000e02")!

    func testLoadSortsDeterministicallyAndPreservesMissingTemplateFallbackData() async {
        let date = Date(timeIntervalSinceReferenceDate: 50_000)
        let firstID = uuid("00000000-0000-4000-8000-000000000e11")
        let secondID = uuid("00000000-0000-4000-8000-000000000e12")
        let olderID = uuid("00000000-0000-4000-8000-000000000e13")
        let missingExerciseID = uuid("00000000-0000-4000-8000-000000000e14")
        let missing = history(
            id: firstID,
            date: date,
            reps: 8,
            exercise: nil,
            exerciseID: missingExerciseID
        )
        let repository = HistoryRepositorySpy(
            history: [
                history(id: olderID, date: date.addingTimeInterval(-1), reps: 7),
                history(id: secondID, date: date, reps: 9),
                missing,
            ]
        )
        let viewModel = TrainingHistoryViewModel(repository: repository)

        await viewModel.load()

        guard case let .content(sessions) = viewModel.state else {
            return XCTFail("Expected history content, got \(viewModel.state)")
        }
        XCTAssertEqual(sessions.map(\.id), [firstID, secondID, olderID])
        XCTAssertNil(sessions[0].workoutDayName)
        XCTAssertNil(sessions[0].exercises[0].exerciseName)
        XCTAssertNil(sessions[0].exercises[0].measurementKind)
        XCTAssertEqual(sessions[0].exercises[0].exerciseTemplateID, missingExerciseID)
        viewModel.beginEditing(setID: sessions[0].exercises[0].sets[0].id)
        XCTAssertNil(viewModel.editingSet, "A missing measurement contract must not be guessed.")
    }

    func testEmptyErrorAndRetryAreRecoverable() async {
        let repository = HistoryRepositorySpy(history: [])
        let viewModel = TrainingHistoryViewModel(repository: repository)

        await viewModel.load()
        XCTAssertEqual(viewModel.state, .empty)

        repository.fetchErrors = [FakeHistoryError.fetch]
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .error)
        XCTAssertEqual(repository.fetchCount, 2)

        repository.history = [history(id: UUID(), date: .now, reps: 8)]
        await viewModel.retry()
        guard case let .content(sessions) = viewModel.state else {
            return XCTFail("Retry must recover content.")
        }
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(repository.fetchCount, 3)
    }

    func testInvalidAndRepositoryFailedEditsPreserveTheUserDraft() async {
        let snapshot = history(id: UUID(), date: .now, reps: 8, weightKg: 10)
        let setID = snapshot.exercises[0].setLogs[0].id
        let repository = HistoryRepositorySpy(history: [snapshot])
        let viewModel = TrainingHistoryViewModel(repository: repository)
        await viewModel.load()
        viewModel.beginEditing(setID: setID)
        viewModel.updateEditingMeasurement(.init(weightKg: 20, reps: 0, rir: 1))

        await viewModel.saveEditingSet()

        XCTAssertEqual(viewModel.mutationState, .validationFailed)
        XCTAssertEqual(viewModel.editingSet?.measurement.reps, 0)
        XCTAssertTrue(repository.updateRequests.isEmpty)

        viewModel.updateEditingMeasurement(.init(weightKg: 20, reps: 10, rir: 1))
        repository.updateError = FakeHistoryError.update
        await viewModel.saveEditingSet()

        XCTAssertEqual(viewModel.mutationState, .repositoryFailed)
        XCTAssertEqual(
            viewModel.editingSet?.measurement,
            .init(weightKg: 20, reps: 10, rir: 1)
        )
        XCTAssertEqual(repository.updateRequests.count, 1)
    }

    func testSuccessfulEditReloadsHistoryRecalculatesPRAndEmitsOneRefresh() async {
        let olderDate = Date(timeIntervalSinceReferenceDate: 51_000)
        let newerDate = olderDate.addingTimeInterval(100)
        let older = history(id: UUID(), date: olderDate, reps: 10)
        let newer = history(id: UUID(), date: newerDate, reps: 12)
        let newerSetID = newer.exercises[0].setLogs[0].id
        let repository = HistoryRepositorySpy(history: [newer, older])
        var refreshCount = 0
        let viewModel = TrainingHistoryViewModel(
            repository: repository,
            now: { newerDate.addingTimeInterval(10) },
            onHistoryChanged: { refreshCount += 1 }
        )
        await viewModel.load()
        XCTAssertTrue(try! setPresentation(id: newerSetID, in: viewModel).isPersonalRecord)

        viewModel.beginEditing(setID: newerSetID)
        viewModel.updateEditingMeasurement(.init(reps: 9))
        await viewModel.saveEditingSet()

        XCTAssertNil(viewModel.editingSet)
        XCTAssertEqual(viewModel.mutationState, .idle)
        XCTAssertFalse(try! setPresentation(id: newerSetID, in: viewModel).isPersonalRecord)
        XCTAssertEqual(repository.fetchCount, 2)
        XCTAssertEqual(repository.updateRequests.first?.updatedAt, newerDate.addingTimeInterval(10))
        XCTAssertEqual(refreshCount, 1)
    }

    func testSetAndSessionDeletionRequireConfirmationThenReloadAndRefresh() async {
        let snapshot = history(id: UUID(), date: .now, reps: 8)
        let sessionID = snapshot.id
        let setID = snapshot.exercises[0].setLogs[0].id
        let repository = HistoryRepositorySpy(history: [snapshot])
        var refreshCount = 0
        let viewModel = TrainingHistoryViewModel(
            repository: repository,
            onHistoryChanged: { refreshCount += 1 }
        )
        await viewModel.load()

        viewModel.requestSetDeletion(id: setID)
        XCTAssertEqual(viewModel.pendingDeletion, .set(setID))
        viewModel.cancelDeletion()
        await viewModel.confirmDeletion()
        XCTAssertTrue(repository.deletedSetIDs.isEmpty)

        viewModel.requestSetDeletion(id: setID)
        await viewModel.confirmDeletion()
        XCTAssertEqual(repository.deletedSetIDs, [setID])
        guard case let .content(afterSetDelete) = viewModel.state else {
            return XCTFail("Deleting the final set must preserve the completed session.")
        }
        XCTAssertEqual(afterSetDelete.map(\.id), [sessionID])
        XCTAssertTrue(afterSetDelete[0].exercises.isEmpty)
        XCTAssertNil(viewModel.pendingDeletion)
        XCTAssertEqual(refreshCount, 1)

        viewModel.requestSessionDeletion(id: sessionID)
        XCTAssertEqual(viewModel.pendingDeletion, .session(sessionID))
        await viewModel.confirmDeletion()
        XCTAssertEqual(repository.deletedSessionIDs, [sessionID])
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.pendingDeletion)
        XCTAssertEqual(refreshCount, 2)
    }

    private func setPresentation(
        id: UUID,
        in viewModel: TrainingHistoryViewModel
    ) throws -> TrainingHistorySetPresentation {
        guard case let .content(sessions) = viewModel.state,
              let set = sessions
                .flatMap(\.exercises)
                .flatMap(\.sets)
                .first(where: { $0.id == id }) else {
            throw FakeHistoryError.missingSet
        }
        return set
    }

    private func history(
        id: UUID,
        date: Date,
        reps: Int,
        weightKg: Double? = nil,
        exercise: SessionExerciseSnapshot? = SessionExerciseSnapshot(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000e02")!,
            name: "Test hareketi",
            orderIndex: 1,
            targetSets: 3,
            measurementKind: .reps
        ),
        exerciseID: UUID? = nil
    ) -> TrainingHistorySessionSnapshot {
        let resolvedExerciseID = exerciseID ?? exercise?.id ?? self.exerciseID
        let set = SetLogSnapshot(
            id: UUID(),
            createdAt: date,
            updatedAt: date,
            workoutSessionID: id,
            exerciseTemplateID: resolvedExerciseID,
            setIndex: 1,
            measurement: .init(weightKg: weightKg, reps: reps),
            isWarmupSet: false,
            completedAt: date
        )
        let resolvedExercise: SessionExerciseSnapshot?
        if weightKg != nil, let exercise {
            resolvedExercise = SessionExerciseSnapshot(
                id: exercise.id,
                name: exercise.name,
                orderIndex: exercise.orderIndex,
                targetSets: exercise.targetSets,
                measurementKind: .weightReps
            )
        } else {
            resolvedExercise = exercise
        }
        return TrainingHistorySessionSnapshot(
            session: WorkoutSessionSnapshot(
                id: id,
                date: date,
                status: .completed,
                workoutDayTemplateID: dayID
            ),
            workoutDayName: exercise == nil ? nil : "Gün A",
            workoutDayFocus: exercise == nil ? nil : "Test",
            exercises: [
                TrainingHistoryExerciseSnapshot(
                    exerciseTemplateID: resolvedExerciseID,
                    exercise: resolvedExercise,
                    setLogs: [set]
                )
            ]
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

private enum FakeHistoryError: Error {
    case fetch
    case update
    case missingSet
    case unsupported
}

@MainActor
private final class HistoryRepositorySpy: TrainingRepository {
    var history: [TrainingHistorySessionSnapshot]
    var fetchErrors: [Error] = []
    var updateError: Error?
    private(set) var fetchCount = 0
    private(set) var updateRequests: [SetLogUpdateRequest] = []
    private(set) var deletedSetIDs: [UUID] = []
    private(set) var deletedSessionIDs: [UUID] = []

    init(history: [TrainingHistorySessionSnapshot]) {
        self.history = history
    }

    func fetchTrainingHistory() async throws -> [TrainingHistorySessionSnapshot] {
        fetchCount += 1
        if !fetchErrors.isEmpty { throw fetchErrors.removeFirst() }
        return history
    }

    func updateSet(_ request: SetLogUpdateRequest) async throws -> SetLogSnapshot {
        updateRequests.append(request)
        if let updateError { throw updateError }
        var updatedSet: SetLogSnapshot?
        history = history.map { session in
            TrainingHistorySessionSnapshot(
                session: session.session,
                workoutDayName: session.workoutDayName,
                workoutDayFocus: session.workoutDayFocus,
                exercises: session.exercises.map { exercise in
                    TrainingHistoryExerciseSnapshot(
                        exerciseTemplateID: exercise.exerciseTemplateID,
                        exercise: exercise.exercise,
                        setLogs: exercise.setLogs.map { set in
                            guard set.id == request.id else { return set }
                            let replacement = SetLogSnapshot(
                                id: set.id,
                                createdAt: set.createdAt,
                                updatedAt: request.updatedAt,
                                workoutSessionID: set.workoutSessionID,
                                exerciseTemplateID: set.exerciseTemplateID,
                                setIndex: set.setIndex,
                                measurement: request.measurement,
                                isWarmupSet: set.isWarmupSet,
                                completedAt: set.completedAt
                            )
                            updatedSet = replacement
                            return replacement
                        }
                    )
                }
            )
        }
        guard let updatedSet else { throw FakeHistoryError.missingSet }
        return updatedSet
    }

    func deleteSet(id: UUID, at _: Date) async throws {
        deletedSetIDs.append(id)
        history = history.compactMap { session in
            let exercises = session.exercises.compactMap { exercise in
                let sets = exercise.setLogs.filter { $0.id != id }
                return sets.isEmpty ? nil : TrainingHistoryExerciseSnapshot(
                    exerciseTemplateID: exercise.exerciseTemplateID,
                    exercise: exercise.exercise,
                    setLogs: sets
                )
            }
            return TrainingHistorySessionSnapshot(
                session: session.session,
                workoutDayName: session.workoutDayName,
                workoutDayFocus: session.workoutDayFocus,
                exercises: exercises
            )
        }
    }

    func deleteWorkoutSession(id: UUID) async throws {
        deletedSessionIDs.append(id)
        history.removeAll { $0.id == id }
    }

    func fetchUserProfile() async throws -> UserProfile? { nil }
    func fetchActiveProgram() async throws -> Program? { nil }
    func fetchProgramPhases(programID _: UUID) async throws -> [ProgramPhase] { [] }
    func fetchWorkoutDays(programID _: UUID) async throws -> [WorkoutDayTemplate] { [] }
    func fetchExerciseTemplates(workoutDayID _: UUID) async throws -> [ExerciseTemplate] { [] }
    func fetchWarmupItems(workoutDayID _: UUID) async throws -> [WarmupItem] { [] }
    func fetchCooldownItems(workoutDayID _: UUID) async throws -> [CooldownItem] { [] }
    func fetchProgramState(programID _: UUID) async throws -> ProgramState? { nil }
    func saveSet(_: SetLogSaveRequest) async throws -> SetLogSnapshot {
        throw FakeHistoryError.unsupported
    }
    func createWorkoutSession(
        _: WorkoutSessionCreateRequest
    ) async throws -> WorkoutSessionSnapshot { throw FakeHistoryError.unsupported }
    func fetchInProgressWorkoutSession() async throws -> WorkoutSessionSnapshot? { nil }
    func transitionWorkoutSession(
        id _: UUID,
        to _: WorkoutSessionStatus,
        at _: Date
    ) async throws -> WorkoutSessionSnapshot { throw FakeHistoryError.unsupported }
    func fetchWorkoutSessionProgress(
        sessionID _: UUID
    ) async throws -> WorkoutSessionProgressSnapshot? { nil }
    func saveWorkoutSessionProgress(
        _: WorkoutSessionProgressUpdate
    ) async throws -> WorkoutSessionProgressSnapshot { throw FakeHistoryError.unsupported }
    func fetchSessionExercises(
        workoutDayID _: UUID
    ) async throws -> [SessionExerciseSnapshot] { [] }
    func fetchSessionPlan(
        workoutDayID _: UUID
    ) async throws -> SessionWorkoutPlanSnapshot? { nil }
    func fetchSetLogs(workoutSessionID _: UUID) async throws -> [SetLogSnapshot] { [] }
    func fetchCompletedExerciseHistory(
        exerciseTemplateID _: UUID
    ) async throws -> [CompletedExerciseHistorySnapshot] { [] }
    func fetchWeeklyPallofHistory() async throws -> WeeklyPallofHistorySnapshot {
        .init(eligibleExerciseTemplateIDs: [], completions: [])
    }
    func fetchOHPSafeAlternative() async throws -> SessionExerciseSnapshot {
        throw FakeHistoryError.unsupported
    }
    func updateWorkoutSessionOHPSymptomResponse(
        id _: UUID,
        response _: OHPSymptomResponse,
        at _: Date
    ) async throws -> WorkoutSessionSnapshot { throw FakeHistoryError.unsupported }
    func updateWorkoutSessionSummary(
        id _: UUID,
        perceivedRecovery _: Int?,
        note _: String?,
        at _: Date
    ) async throws -> WorkoutSessionSnapshot { throw FakeHistoryError.unsupported }
}
