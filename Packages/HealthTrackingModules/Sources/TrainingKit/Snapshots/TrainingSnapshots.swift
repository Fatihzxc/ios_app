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

public struct CompletedExerciseHistorySnapshot: Equatable, Sendable {
    public let session: WorkoutSessionSnapshot
    public let setLogs: [SetLogSnapshot]

    public init(
        session: WorkoutSessionSnapshot,
        setLogs: [SetLogSnapshot]
    ) {
        self.session = session
        self.setLogs = setLogs
    }
}

public struct WeeklyPallofCompletionSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let exerciseTemplateID: UUID
    public let completedAt: Date
    public let performedVariant: String?

    public init(
        id: UUID,
        exerciseTemplateID: UUID,
        completedAt: Date,
        performedVariant: String?
    ) {
        self.id = id
        self.exerciseTemplateID = exerciseTemplateID
        self.completedAt = completedAt
        self.performedVariant = performedVariant
    }
}

public struct WeeklyPallofHistorySnapshot: Equatable, Sendable {
    public let eligibleExerciseTemplateIDs: Set<UUID>
    public let completions: [WeeklyPallofCompletionSnapshot]

    public init(
        eligibleExerciseTemplateIDs: Set<UUID>,
        completions: [WeeklyPallofCompletionSnapshot]
    ) {
        self.eligibleExerciseTemplateIDs = eligibleExerciseTemplateIDs
        self.completions = completions
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
    public let name: String
    public let orderIndex: Int
    public let targetSets: Int
    public let repLow: Int?
    public let repHigh: Int?
    public let rirLow: Int
    public let rirHigh: Int
    public let allowFailure: Bool
    public let cues: String
    public let safetyNote: String?
    public let startingWeightKg: Double?
    public let progressionRule: ProgressionRule
    public let measurementKind: ExerciseMeasurementKind

    public init(
        id: UUID,
        name: String = "",
        orderIndex: Int,
        targetSets: Int,
        repLow: Int? = nil,
        repHigh: Int? = nil,
        rirLow: Int = 0,
        rirHigh: Int = 0,
        allowFailure: Bool = false,
        cues: String = "",
        safetyNote: String? = nil,
        startingWeightKg: Double? = nil,
        progressionRule: ProgressionRule = .doubleProgression,
        measurementKind: ExerciseMeasurementKind = .weightReps
    ) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.repLow = repLow
        self.repHigh = repHigh
        self.rirLow = rirLow
        self.rirHigh = rirHigh
        self.allowFailure = allowFailure
        self.cues = cues
        self.safetyNote = safetyNote
        self.startingWeightKg = startingWeightKg
        self.progressionRule = progressionRule
        self.measurementKind = measurementKind
    }
}

public struct SessionChecklistItemSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let note: String?
    public let orderIndex: Int

    public init(
        id: UUID,
        title: String,
        detail: String,
        note: String? = nil,
        orderIndex: Int
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.note = note
        self.orderIndex = orderIndex
    }
}

public struct SessionWorkoutPlanSnapshot: Equatable, Sendable {
    public let workoutDayID: UUID
    public let name: String
    public let focus: String
    public let warmupItems: [SessionChecklistItemSnapshot]
    public let exercises: [SessionExerciseSnapshot]
    public let cooldownItems: [SessionChecklistItemSnapshot]

    public init(
        workoutDayID: UUID,
        name: String,
        focus: String,
        warmupItems: [SessionChecklistItemSnapshot],
        exercises: [SessionExerciseSnapshot],
        cooldownItems: [SessionChecklistItemSnapshot]
    ) {
        self.workoutDayID = workoutDayID
        self.name = name
        self.focus = focus
        self.warmupItems = warmupItems
        self.exercises = exercises
        self.cooldownItems = cooldownItems
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

public struct SessionPresentation: Equatable, Sendable {
    public let session: WorkoutSessionSnapshot
    public let plan: SessionWorkoutPlanSnapshot
    public let progress: SessionProgressState
    public let setLogs: [SetLogSnapshot]
    public let restoreSource: SessionRestoreSource

    public init(
        session: WorkoutSessionSnapshot,
        plan: SessionWorkoutPlanSnapshot,
        progress: SessionProgressState,
        setLogs: [SetLogSnapshot],
        restoreSource: SessionRestoreSource
    ) {
        self.session = session
        self.plan = plan
        self.progress = progress
        self.setLogs = setLogs
        self.restoreSource = restoreSource
    }

    public var currentExercise: SessionExerciseSnapshot? {
        guard progress.stage == .movement,
              let currentExerciseTemplateID = progress.currentExerciseTemplateID else {
            return nil
        }
        return plan.exercises.first { $0.id == currentExerciseTemplateID }
    }

    public var currentExerciseIndex: Int? {
        guard let currentExercise else { return nil }
        return plan.exercises.firstIndex { $0.id == currentExercise.id }
    }

    public var completedWorkingSetsForCurrentExercise: [SetLogSnapshot] {
        guard let currentExercise else { return [] }
        return setLogs
            .filter {
                !$0.isWarmupSet &&
                    $0.exerciseTemplateID == currentExercise.id
            }
            .sorted { lhs, rhs in
                if lhs.setIndex != rhs.setIndex {
                    return lhs.setIndex < rhs.setIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }
}

public enum SessionViewFailure: Equatable, Sendable {
    case load
    case progress
    case completion
    case deletion
    case summary
    case ohpSafety
}

public enum SessionViewState: Equatable, Sendable {
    case idle
    case loading
    case active(SessionPresentation)
    case failed(SessionViewFailure)
    case dismissed
}

public enum SessionSetSaveState: Equatable, Sendable {
    case idle
    case saving
    case saved(setID: UUID)
    case validationFailed
    case repositoryFailed
}

public enum SessionRecommendationReason: Equatable, Sendable {
    case templateStartingValues
    case sameSessionPrevious
    case priorSessionSameIndex
    case doubleProgressionIncrease
    case doubleProgressionHold(SessionDoubleProgressionHoldReason)
    case bodyweight(SessionBodyweightRecommendationReason)
    case weeklyPallof(SessionWeeklyPallofRecommendationReason)
    case ohp(SessionOHPRecommendationReason)
    case noPrefill
}

public enum SessionDoubleProgressionHoldReason: Equatable, Sendable {
    case noWorkingSets
    case missingRepCeiling
    case repetitionsBelowCeiling
    case missingRIR
    case rirAboveThreshold
    case missingExternalWeight
}

public enum SessionBodyweightRecommendationReason: Equatable, Sendable {
    case noWorkingSets
    case missingRepCeiling
    case inconsistentVariants
    case buildRepetitions
    case advanceToDefinedVariant
    case programAdjustmentRequired
}

public enum SessionWeeklyPallofRecommendationReason: Equatable, Sendable {
    case pallofDue
    case pallofCompletedThisWeek
}

public enum SessionOHPEntryVariant: String, Equatable, Sendable {
    case seatedNeutral = "seated-neutral"
    case standingNeutral = "standing-neutral"
    case standingStandard = "standing-standard"
}

public enum SessionOHPLoadIncreaseBlockReason: Equatable, Sendable {
    case firstSession
    case previousResponseRequired
    case previousSymptomsPresent
    case previousResponseUncertain
    case currentSymptomsPresent
}

public enum SessionOHPLoadIncreasePolicy: Equatable, Sendable {
    case allowed
    case blocked(SessionOHPLoadIncreaseBlockReason)
}

public enum SessionOHPSafetyState: Equatable, Sendable {
    case notRequired
    case awaitingPreviousSessionResponse(
        sessionID: UUID,
        entryVariant: SessionOHPEntryVariant
    )
    case ready(
        entryVariant: SessionOHPEntryVariant,
        loadIncreasePolicy: SessionOHPLoadIncreasePolicy
    )
    case stopped(alternative: SessionExerciseSnapshot)
}

public enum SessionOHPRecommendationReason: Equatable, Sendable {
    case firstSession
    case previousResponseRequired
    case previousSymptomsPresent
    case previousResponseUncertain
    case currentSymptomsPresent
    case increaseAllowed
    case progressionHold(SessionDoubleProgressionHoldReason)
}

public enum SessionVariantOption: String, CaseIterable, Equatable, Hashable, Sendable {
    case pallof
    case plank
}
