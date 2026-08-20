import CoreModels
import Foundation
import GuidanceKit
import Observation

public struct TrainingHistorySetPresentation: Equatable, Sendable, Identifiable {
    public let setLog: SetLogSnapshot
    public let isPersonalRecord: Bool

    public var id: UUID { setLog.id }

    public init(setLog: SetLogSnapshot, isPersonalRecord: Bool) {
        self.setLog = setLog
        self.isPersonalRecord = isPersonalRecord
    }
}

public struct TrainingHistoryExercisePresentation: Equatable, Sendable, Identifiable {
    public let exerciseTemplateID: UUID
    public let exerciseName: String?
    public let measurementKind: ExerciseMeasurementKind?
    public let sets: [TrainingHistorySetPresentation]

    public var id: UUID { exerciseTemplateID }

    public init(
        exerciseTemplateID: UUID,
        exerciseName: String?,
        measurementKind: ExerciseMeasurementKind?,
        sets: [TrainingHistorySetPresentation]
    ) {
        self.exerciseTemplateID = exerciseTemplateID
        self.exerciseName = exerciseName
        self.measurementKind = measurementKind
        self.sets = sets
    }
}

public struct TrainingHistorySessionPresentation: Equatable, Sendable, Identifiable {
    public let session: WorkoutSessionSnapshot
    public let workoutDayName: String?
    public let workoutDayFocus: String?
    public let exercises: [TrainingHistoryExercisePresentation]

    public var id: UUID { session.id }

    public init(
        session: WorkoutSessionSnapshot,
        workoutDayName: String?,
        workoutDayFocus: String?,
        exercises: [TrainingHistoryExercisePresentation]
    ) {
        self.session = session
        self.workoutDayName = workoutDayName
        self.workoutDayFocus = workoutDayFocus
        self.exercises = exercises
    }
}

public enum TrainingHistoryViewState: Equatable, Sendable {
    case loading
    case content([TrainingHistorySessionPresentation])
    case empty
    case error
}

public struct TrainingHistoryEditingSet: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let measurementKind: ExerciseMeasurementKind
    public let measurement: SetMeasurementInput

    public init(
        id: UUID,
        measurementKind: ExerciseMeasurementKind,
        measurement: SetMeasurementInput
    ) {
        self.id = id
        self.measurementKind = measurementKind
        self.measurement = measurement
    }
}

public enum TrainingHistoryMutationState: Equatable, Sendable {
    case idle
    case saving
    case validationFailed
    case repositoryFailed
}

public enum TrainingHistoryDeletionTarget: Equatable, Sendable {
    case set(UUID)
    case session(UUID)
}

@MainActor
@Observable
public final class TrainingHistoryViewModel {
    public private(set) var state: TrainingHistoryViewState = .loading
    public private(set) var editingSet: TrainingHistoryEditingSet?
    public private(set) var mutationState: TrainingHistoryMutationState = .idle
    public private(set) var pendingDeletion: TrainingHistoryDeletionTarget?

    @ObservationIgnored
    private let repository: any TrainingRepository
    @ObservationIgnored
    private let now: @MainActor () -> Date
    @ObservationIgnored
    private let onHistoryChanged: @MainActor () async -> Void

    public init(
        repository: any TrainingRepository,
        now: @escaping @MainActor () -> Date = { .now },
        onHistoryChanged: @escaping @MainActor () async -> Void = {}
    ) {
        self.repository = repository
        self.now = now
        self.onHistoryChanged = onHistoryChanged
    }

    public func load() async {
        state = .loading
        do {
            let snapshots = try await repository.fetchTrainingHistory()
            let presentations = Self.makePresentations(snapshots)
            state = presentations.isEmpty ? .empty : .content(presentations)
        } catch {
            state = .error
        }
    }

    public func retry() async {
        await load()
    }

    public func beginEditing(setID: UUID) {
        guard let match = setMatch(id: setID),
              let measurementKind = match.exercise.measurementKind else {
            editingSet = nil
            return
        }
        editingSet = TrainingHistoryEditingSet(
            id: match.set.id,
            measurementKind: measurementKind,
            measurement: match.set.setLog.measurement
        )
        mutationState = .idle
    }

    public func updateEditingMeasurement(_ measurement: SetMeasurementInput) {
        guard let editingSet else { return }
        self.editingSet = TrainingHistoryEditingSet(
            id: editingSet.id,
            measurementKind: editingSet.measurementKind,
            measurement: measurement
        )
        mutationState = .idle
    }

    public func cancelEditing() {
        editingSet = nil
        mutationState = .idle
    }

    public func saveEditingSet() async {
        guard let editingSet else { return }
        do {
            try SetMeasurementValidator.validate(
                editingSet.measurement,
                for: editingSet.measurementKind
            )
        } catch {
            mutationState = .validationFailed
            return
        }

        mutationState = .saving
        do {
            _ = try await repository.updateSet(
                SetLogUpdateRequest(
                    id: editingSet.id,
                    measurement: editingSet.measurement,
                    updatedAt: now()
                )
            )
            self.editingSet = nil
            await refreshAfterMutation()
        } catch {
            mutationState = .repositoryFailed
        }
    }

    public func requestSetDeletion(id: UUID) {
        guard setMatch(id: id) != nil else { return }
        pendingDeletion = .set(id)
    }

    public func requestSessionDeletion(id: UUID) {
        guard session(id: id) != nil else { return }
        pendingDeletion = .session(id)
    }

    public func cancelDeletion() {
        pendingDeletion = nil
        mutationState = .idle
    }

    public func confirmDeletion() async {
        guard let pendingDeletion else { return }
        mutationState = .saving
        do {
            switch pendingDeletion {
            case let .set(id):
                try await repository.deleteSet(id: id, at: now())
            case let .session(id):
                try await repository.deleteWorkoutSession(id: id)
            }
            self.pendingDeletion = nil
            await refreshAfterMutation()
        } catch {
            mutationState = .repositoryFailed
        }
    }

    public func session(id: UUID) -> TrainingHistorySessionPresentation? {
        guard case let .content(sessions) = state else { return nil }
        return sessions.first { $0.id == id }
    }

    private func refreshAfterMutation() async {
        await load()
        await onHistoryChanged()
        mutationState = .idle
    }

    private func setMatch(
        id: UUID
    ) -> (
        exercise: TrainingHistoryExercisePresentation,
        set: TrainingHistorySetPresentation
    )? {
        guard case let .content(sessions) = state else { return nil }
        for session in sessions {
            for exercise in session.exercises {
                if let set = exercise.sets.first(where: { $0.id == id }) {
                    return (exercise, set)
                }
            }
        }
        return nil
    }

    private static func makePresentations(
        _ snapshots: [TrainingHistorySessionSnapshot]
    ) -> [TrainingHistorySessionPresentation] {
        let recordSetIDs = personalRecordSetIDs(in: snapshots)
        return snapshots
            .sorted(by: reverseChronologicalOrder)
            .map { snapshot in
                TrainingHistorySessionPresentation(
                    session: snapshot.session,
                    workoutDayName: snapshot.workoutDayName,
                    workoutDayFocus: snapshot.workoutDayFocus,
                    exercises: snapshot.exercises
                        .sorted(by: exerciseOrder)
                        .map { exercise in
                            TrainingHistoryExercisePresentation(
                                exerciseTemplateID: exercise.exerciseTemplateID,
                                exerciseName: exercise.exercise?.name,
                                measurementKind: exercise.exercise?.measurementKind,
                                sets: exercise.setLogs
                                    .sorted(by: setOrder)
                                    .map {
                                        TrainingHistorySetPresentation(
                                            setLog: $0,
                                            isPersonalRecord: recordSetIDs.contains($0.id)
                                        )
                                    }
                            )
                        }
                )
            }
    }

    private static func personalRecordSetIDs(
        in snapshots: [TrainingHistorySessionSnapshot]
    ) -> Set<UUID> {
        var attemptsByExerciseID: [UUID: [PersonalRecordDetector.Attempt]] = [:]
        for snapshot in snapshots {
            for exercise in snapshot.exercises {
                guard let kind = exercise.exercise?.measurementKind else { continue }
                for setLog in exercise.setLogs {
                    guard let measurement = recordMeasurement(
                        setLog.measurement,
                        kind: kind
                    ) else {
                        continue
                    }
                    attemptsByExerciseID[exercise.exerciseTemplateID, default: []].append(
                        PersonalRecordDetector.Attempt(
                            id: setLog.id,
                            completedAt: setLog.completedAt,
                            measurement: measurement,
                            isWarmupSet: setLog.isWarmupSet
                        )
                    )
                }
            }
        }

        var recordSetIDs = Set<UUID>()
        for attempts in attemptsByExerciseID.values {
            for result in PersonalRecordDetector.evaluate(attempts) {
                if case .newRecord = result.outcome {
                    recordSetIDs.insert(result.attemptID)
                }
            }
        }
        return recordSetIDs
    }

    private static func recordMeasurement(
        _ input: SetMeasurementInput,
        kind: ExerciseMeasurementKind
    ) -> PersonalRecordDetector.Measurement? {
        switch kind {
        case .weightReps:
            .weightedReps(weightKg: input.weightKg, reps: input.reps)
        case .reps:
            .bodyweightReps(
                reps: input.reps,
                performedVariant: input.performedVariant
            )
        case .duration:
            .duration(
                seconds: input.durationSec,
                performedVariant: input.performedVariant
            )
        case .steps:
            .steps(count: input.distanceSteps, loadKg: input.weightKg)
        case .quality:
            nil
        }
    }

    private static func reverseChronologicalOrder(
        _ lhs: TrainingHistorySessionSnapshot,
        _ rhs: TrainingHistorySessionSnapshot
    ) -> Bool {
        if lhs.session.date != rhs.session.date {
            return lhs.session.date > rhs.session.date
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func exerciseOrder(
        _ lhs: TrainingHistoryExerciseSnapshot,
        _ rhs: TrainingHistoryExerciseSnapshot
    ) -> Bool {
        let lhsOrder = lhs.exercise?.orderIndex ?? .max
        let rhsOrder = rhs.exercise?.orderIndex ?? .max
        if lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }
        return lhs.exerciseTemplateID.uuidString < rhs.exerciseTemplateID.uuidString
    }

    private static func setOrder(_ lhs: SetLogSnapshot, _ rhs: SetLogSnapshot) -> Bool {
        if lhs.setIndex != rhs.setIndex {
            return lhs.setIndex < rhs.setIndex
        }
        if lhs.completedAt != rhs.completedAt {
            return lhs.completedAt < rhs.completedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
