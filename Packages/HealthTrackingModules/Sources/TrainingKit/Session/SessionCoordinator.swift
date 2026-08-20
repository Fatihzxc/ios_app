import CoreModels
import Foundation

@MainActor
public final class SessionCoordinator {
    private let repository: any TrainingRepository

    public init(repository: any TrainingRepository) {
        self.repository = repository
    }

    public func beginSession(
        _ request: WorkoutSessionCreateRequest
    ) async throws -> WorkoutSessionSnapshot {
        if let existing = try await repository.fetchInProgressWorkoutSession() {
            return existing
        }
        let planned = try await repository.createWorkoutSession(request)
        return try await repository.transitionWorkoutSession(
            id: planned.id,
            to: .inProgress,
            at: request.date
        )
    }

    public func restoreInProgressSession() async throws -> RestoredWorkoutSession? {
        guard let session = try await repository.fetchInProgressWorkoutSession() else {
            return nil
        }

        let progress: WorkoutSessionProgressSnapshot?
        do {
            progress = try await repository.fetchWorkoutSessionProgress(sessionID: session.id)
        } catch is WorkoutSessionProgressCodecError {
            return try await inferredRestore(
                session: session,
                source: .inferredCorruptProgress
            )
        }

        guard let progress else {
            return try await inferredRestore(
                session: session,
                source: .inferredMissingProgress
            )
        }

        if progress.stage == .movement {
            let exercises = try await repository.fetchSessionExercises(
                workoutDayID: session.workoutDayTemplateID
            )
            guard let currentID = progress.currentExerciseTemplateID,
                  exercises.contains(where: { $0.id == currentID }) else {
                return try await inferredRestore(
                    session: session,
                    exercises: exercises,
                    source: .inferredMissingExerciseReference
                )
            }
        }

        return RestoredWorkoutSession(
            session: session,
            state: progress.state,
            source: .stored
        )
    }

    public func recordOHPSymptomResponse(
        sessionID: UUID,
        response: OHPSymptomResponse,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        try await repository.updateWorkoutSessionOHPSymptomResponse(
            id: sessionID,
            response: response,
            at: date
        )
    }

    private func inferredRestore(
        session: WorkoutSessionSnapshot,
        exercises suppliedExercises: [SessionExerciseSnapshot]? = nil,
        source: SessionRestoreSource
    ) async throws -> RestoredWorkoutSession {
        let exercises: [SessionExerciseSnapshot]
        if let suppliedExercises {
            exercises = suppliedExercises
        } else {
            exercises = try await repository.fetchSessionExercises(
                workoutDayID: session.workoutDayTemplateID
            )
        }
        let resolvedExercises = exercises.sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex < rhs.orderIndex
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let sets = try await repository.fetchSetLogs(workoutSessionID: session.id)
            .filter { !$0.isWarmupSet }

        let state: SessionProgressState
        if sets.isEmpty || resolvedExercises.isEmpty {
            state = SessionProgressState(stage: .warmup)
        } else if let incomplete = resolvedExercises.first(where: { exercise in
            sets.filter { $0.exerciseTemplateID == exercise.id }.count < exercise.targetSets
        }) {
            state = SessionProgressState(
                stage: .movement,
                currentExerciseTemplateID: incomplete.id,
                warmupDisposition: .completed
            )
        } else {
            state = SessionProgressState(
                stage: .cooldown,
                warmupDisposition: .completed
            )
        }

        return RestoredWorkoutSession(session: session, state: state, source: source)
    }
}
