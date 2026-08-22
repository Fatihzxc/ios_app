import CoreModels
import Foundation

public struct TodayRepositorySnapshot: Equatable, Sendable {
    public struct Profile: Equatable, Sendable {
        public let proteinTargetG: Double
        public let weeklyWorkoutTarget: Int
        public let programStartDate: Date

        public init(
            proteinTargetG: Double,
            weeklyWorkoutTarget: Int,
            programStartDate: Date
        ) {
            self.proteinTargetG = proteinTargetG
            self.weeklyWorkoutTarget = weeklyWorkoutTarget
            self.programStartDate = programStartDate
        }
    }

    public struct Program: Equatable, Sendable {
        public let id: UUID
        public let name: String

        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Phase: Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let orderIndex: Int
        public let monthStart: Int
        public let monthEnd: Int
        public let entryCriteria: String
        public let milestone: String

        public init(
            id: UUID,
            name: String,
            orderIndex: Int,
            monthStart: Int,
            monthEnd: Int,
            entryCriteria: String,
            milestone: String
        ) {
            self.id = id
            self.name = name
            self.orderIndex = orderIndex
            self.monthStart = monthStart
            self.monthEnd = monthEnd
            self.entryCriteria = entryCriteria
            self.milestone = milestone
        }
    }

    public struct WorkoutDay: Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let orderIndex: Int
        public let focus: String
        public let containsOHP: Bool

        public init(
            id: UUID,
            name: String,
            orderIndex: Int,
            focus: String,
            containsOHP: Bool
        ) {
            self.id = id
            self.name = name
            self.orderIndex = orderIndex
            self.focus = focus
            self.containsOHP = containsOHP
        }
    }

    public struct ProgramState: Equatable, Sendable {
        public let currentPhaseID: UUID
        public let trainingWeekIndex: Int
        public let deloadStatus: DeloadStatus
        public let deloadReason: DeloadReason?

        public init(
            currentPhaseID: UUID,
            trainingWeekIndex: Int,
            deloadStatus: DeloadStatus,
            deloadReason: DeloadReason?
        ) {
            self.currentPhaseID = currentPhaseID
            self.trainingWeekIndex = trainingWeekIndex
            self.deloadStatus = deloadStatus
            self.deloadReason = deloadReason
        }
    }

    public struct Reminder: Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let dueDate: Date

        public init(id: UUID, title: String, dueDate: Date) {
            self.id = id
            self.title = title
            self.dueDate = dueDate
        }
    }

    public struct MeasurementReminder: Equatable, Sendable {
        public let id: UUID
        public let message: String

        public init(id: UUID, message: String) {
            self.id = id
            self.message = message
        }
    }

    public struct ExerciseHistory: Equatable, Sendable {
        public let exerciseID: UUID
        public let sessions: [CompletedExerciseHistorySnapshot]

        public init(
            exerciseID: UUID,
            sessions: [CompletedExerciseHistorySnapshot]
        ) {
            self.exerciseID = exerciseID
            self.sessions = sessions
        }
    }

    public let profile: Profile
    public let program: Program
    public let phases: [Phase]
    public let workoutDays: [WorkoutDay]
    public let programState: ProgramState
    public let sessions: [WorkoutSessionSnapshot]
    public let healthChecks: [Reminder]
    public let measurementReminders: [MeasurementReminder]
    public let exerciseHistories: [ExerciseHistory]

    public init(
        profile: Profile,
        program: Program,
        phases: [Phase],
        workoutDays: [WorkoutDay],
        programState: ProgramState,
        sessions: [WorkoutSessionSnapshot],
        healthChecks: [Reminder],
        measurementReminders: [MeasurementReminder],
        exerciseHistories: [ExerciseHistory]
    ) {
        self.profile = profile
        self.program = program
        self.phases = phases
        self.workoutDays = workoutDays
        self.programState = programState
        self.sessions = sessions
        self.healthChecks = healthChecks
        self.measurementReminders = measurementReminders
        self.exerciseHistories = exerciseHistories
    }
}

public struct TodayPhasePresentation: Equatable, Sendable {
    public let name: String
    public let position: Int
    public let count: Int

    public init(name: String, position: Int, count: Int) {
        self.name = name
        self.position = position
        self.count = count
    }
}

public struct TodayWorkoutDayPresentation: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let focus: String

    public init(id: UUID, name: String, focus: String) {
        self.id = id
        self.name = name
        self.focus = focus
    }
}

public enum TodayTrainReason: Equatable, Sendable {
    case scheduled
}

public enum TodayRestReason: Equatable, Sendable {
    case completedToday
    case completedPreviousCalendarDay
    case weeklyTargetReached(completed: Int, target: Int)
}

public enum TodayDirectivePresentation: Equatable, Sendable {
    case train(workoutDay: TodayWorkoutDayPresentation, reason: TodayTrainReason)
    case resume(sessionID: UUID, workoutDay: TodayWorkoutDayPresentation)
    case rest(reason: TodayRestReason, nextWorkoutDay: TodayWorkoutDayPresentation)
}

public enum TodayDeloadMode: Equatable, Sendable {
    case recommended
    case active
}

public enum TodayDeloadReason: Equatable, Sendable {
    case scheduled
    case reactive
}

public enum TodayAlertPresentation: Equatable, Sendable {
    case activeSymptoms
    case ohp
    case deload(
        mode: TodayDeloadMode,
        reason: TodayDeloadReason,
        trainingWeekIndex: Int
    )
    case phase(nextPhaseName: String)
    case bloodwork(title: String, dueDate: Date)
    case measurement(message: String)
}

public enum TodayMainAction: Equatable, Sendable {
    case start(workoutDayID: UUID)
    case resume(sessionID: UUID, workoutDayID: UUID)
    case overrideRest(workoutDayID: UUID)

    public var workoutDayID: UUID {
        switch self {
        case let .start(workoutDayID),
             let .resume(_, workoutDayID),
             let .overrideRest(workoutDayID):
            workoutDayID
        }
    }
}

public struct TodayPresentation: Equatable, Sendable {
    public let phase: TodayPhasePresentation
    public let directive: TodayDirectivePresentation
    public let alert: TodayAlertPresentation?
    public let additionalAlertCount: Int
    public let mainAction: TodayMainAction
    public let proteinTargetG: Double
    public let firstMeaningfulContentElapsed: TimeInterval?

    public init(
        phase: TodayPhasePresentation,
        directive: TodayDirectivePresentation,
        alert: TodayAlertPresentation?,
        additionalAlertCount: Int,
        mainAction: TodayMainAction,
        proteinTargetG: Double,
        firstMeaningfulContentElapsed: TimeInterval?
    ) {
        self.phase = phase
        self.directive = directive
        self.alert = alert
        self.additionalAlertCount = additionalAlertCount
        self.mainAction = mainAction
        self.proteinTargetG = proteinTargetG
        self.firstMeaningfulContentElapsed = firstMeaningfulContentElapsed
    }
}

public enum TodayViewState: Equatable, Sendable {
    case loading
    case content(TodayPresentation)
    case empty
    case error
}

public struct TodayNutritionMetricPresentation: Equatable, Sendable {
    public let consumed: Decimal
    public let target: Decimal?
    public let remaining: Decimal?
    public let progress: Decimal?

    public init(
        consumed: Decimal,
        target: Decimal?,
        remaining: Decimal?,
        progress: Decimal?
    ) {
        self.consumed = consumed
        self.target = target
        self.remaining = remaining
        self.progress = progress
    }
}

public struct TodayNutritionPresentation: Equatable, Sendable {
    public let calories: TodayNutritionMetricPresentation
    public let protein: TodayNutritionMetricPresentation
    public let carbs: TodayNutritionMetricPresentation
    public let fat: TodayNutritionMetricPresentation

    public init(
        calories: TodayNutritionMetricPresentation,
        protein: TodayNutritionMetricPresentation,
        carbs: TodayNutritionMetricPresentation,
        fat: TodayNutritionMetricPresentation
    ) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

public enum TodayNutritionViewState: Equatable, Sendable {
    case loading
    case empty(TodayNutritionPresentation)
    case content(TodayNutritionPresentation)
    case error
}
