import CoreModels
import Foundation

public struct SetLogSaveRequest: Equatable, Sendable {
    public let id: UUID
    public let workoutSessionID: UUID
    public let exerciseTemplateID: UUID
    public let setIndex: Int
    public let measurement: SetMeasurementInput
    public let isWarmupSet: Bool
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        workoutSessionID: UUID,
        exerciseTemplateID: UUID,
        setIndex: Int,
        measurement: SetMeasurementInput,
        isWarmupSet: Bool = false,
        completedAt: Date
    ) {
        self.id = id
        self.workoutSessionID = workoutSessionID
        self.exerciseTemplateID = exerciseTemplateID
        self.setIndex = setIndex
        self.measurement = measurement
        self.isWarmupSet = isWarmupSet
        self.completedAt = completedAt
    }
}

public struct SetLogSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let workoutSessionID: UUID
    public let exerciseTemplateID: UUID
    public let setIndex: Int
    public let measurement: SetMeasurementInput
    public let isWarmupSet: Bool
    public let completedAt: Date

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        workoutSessionID: UUID,
        exerciseTemplateID: UUID,
        setIndex: Int,
        measurement: SetMeasurementInput,
        isWarmupSet: Bool,
        completedAt: Date
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workoutSessionID = workoutSessionID
        self.exerciseTemplateID = exerciseTemplateID
        self.setIndex = setIndex
        self.measurement = measurement
        self.isWarmupSet = isWarmupSet
        self.completedAt = completedAt
    }
}

public struct WorkoutSessionCreateRequest: Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let workoutDayTemplateID: UUID

    public init(
        id: UUID = UUID(),
        date: Date,
        workoutDayTemplateID: UUID
    ) {
        self.id = id
        self.date = date
        self.workoutDayTemplateID = workoutDayTemplateID
    }
}

public struct WorkoutSessionSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let date: Date
    public let status: WorkoutSessionStatus
    public let workoutDayTemplateID: UUID
    public let perceivedRecovery: Int?
    public let note: String?
    public let ohpSymptomResponse: OHPSymptomResponse
    public let ohpSymptomCheckedAt: Date?

    public init(
        id: UUID,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        date: Date,
        status: WorkoutSessionStatus,
        workoutDayTemplateID: UUID,
        perceivedRecovery: Int? = nil,
        note: String? = nil,
        ohpSymptomResponse: OHPSymptomResponse = .notAsked,
        ohpSymptomCheckedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt ?? date
        self.updatedAt = updatedAt ?? date
        self.date = date
        self.status = status
        self.workoutDayTemplateID = workoutDayTemplateID
        self.perceivedRecovery = perceivedRecovery
        self.note = note
        self.ohpSymptomResponse = ohpSymptomResponse
        self.ohpSymptomCheckedAt = ohpSymptomCheckedAt
    }
}

public struct SessionExerciseSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let orderIndex: Int
    public let targetSets: Int

    public init(id: UUID, orderIndex: Int, targetSets: Int) {
        self.id = id
        self.orderIndex = orderIndex
        self.targetSets = targetSets
    }
}

public struct SessionProgressState: Equatable, Sendable {
    public let stage: WorkoutSessionProgressStage
    public let currentExerciseTemplateID: UUID?
    public let completedWarmupItemIDs: Set<UUID>
    public let completedCooldownItemIDs: Set<UUID>
    public let warmupDisposition: WorkoutChecklistDisposition
    public let cooldownDisposition: WorkoutChecklistDisposition

    public init(
        stage: WorkoutSessionProgressStage,
        currentExerciseTemplateID: UUID? = nil,
        completedWarmupItemIDs: Set<UUID> = [],
        completedCooldownItemIDs: Set<UUID> = [],
        warmupDisposition: WorkoutChecklistDisposition = .pending,
        cooldownDisposition: WorkoutChecklistDisposition = .pending
    ) {
        self.stage = stage
        self.currentExerciseTemplateID = currentExerciseTemplateID
        self.completedWarmupItemIDs = completedWarmupItemIDs
        self.completedCooldownItemIDs = completedCooldownItemIDs
        self.warmupDisposition = warmupDisposition
        self.cooldownDisposition = cooldownDisposition
    }
}

public struct WorkoutSessionProgressUpdate: Equatable, Sendable {
    public let id: UUID
    public let workoutSessionID: UUID
    public let state: SessionProgressState
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        workoutSessionID: UUID,
        stage: WorkoutSessionProgressStage,
        currentExerciseTemplateID: UUID? = nil,
        completedWarmupItemIDs: Set<UUID> = [],
        completedCooldownItemIDs: Set<UUID> = [],
        warmupDisposition: WorkoutChecklistDisposition = .pending,
        cooldownDisposition: WorkoutChecklistDisposition = .pending,
        updatedAt: Date
    ) {
        self.id = id
        self.workoutSessionID = workoutSessionID
        state = SessionProgressState(
            stage: stage,
            currentExerciseTemplateID: currentExerciseTemplateID,
            completedWarmupItemIDs: completedWarmupItemIDs,
            completedCooldownItemIDs: completedCooldownItemIDs,
            warmupDisposition: warmupDisposition,
            cooldownDisposition: cooldownDisposition
        )
        self.updatedAt = updatedAt
    }
}

public struct WorkoutSessionProgressSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let workoutSessionID: UUID
    public let state: SessionProgressState

    public var stage: WorkoutSessionProgressStage { state.stage }
    public var currentExerciseTemplateID: UUID? { state.currentExerciseTemplateID }
    public var completedWarmupItemIDs: Set<UUID> { state.completedWarmupItemIDs }
    public var completedCooldownItemIDs: Set<UUID> { state.completedCooldownItemIDs }
    public var warmupDisposition: WorkoutChecklistDisposition { state.warmupDisposition }
    public var cooldownDisposition: WorkoutChecklistDisposition { state.cooldownDisposition }

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        workoutSessionID: UUID,
        stage: WorkoutSessionProgressStage,
        currentExerciseTemplateID: UUID? = nil,
        completedWarmupItemIDs: Set<UUID> = [],
        completedCooldownItemIDs: Set<UUID> = [],
        warmupDisposition: WorkoutChecklistDisposition = .pending,
        cooldownDisposition: WorkoutChecklistDisposition = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workoutSessionID = workoutSessionID
        state = SessionProgressState(
            stage: stage,
            currentExerciseTemplateID: currentExerciseTemplateID,
            completedWarmupItemIDs: completedWarmupItemIDs,
            completedCooldownItemIDs: completedCooldownItemIDs,
            warmupDisposition: warmupDisposition,
            cooldownDisposition: cooldownDisposition
        )
    }
}

public enum SessionRestoreSource: Equatable, Sendable {
    case stored
    case inferredMissingProgress
    case inferredCorruptProgress
    case inferredMissingExerciseReference
}

public struct RestoredWorkoutSession: Equatable, Sendable {
    public let session: WorkoutSessionSnapshot
    public let state: SessionProgressState
    public let source: SessionRestoreSource

    public init(
        session: WorkoutSessionSnapshot,
        state: SessionProgressState,
        source: SessionRestoreSource
    ) {
        self.session = session
        self.state = state
        self.source = source
    }
}
