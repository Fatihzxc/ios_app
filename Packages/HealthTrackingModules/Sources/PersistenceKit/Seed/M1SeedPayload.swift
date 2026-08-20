import CoreModels
import Foundation

public struct M1SeedPayload: Equatable, Sendable {
    public let exercises: [Exercise]
    public let warmups: [Warmup]
    public let cooldowns: [Cooldown]
    public let reminders: [Reminder]
    public let programState: State

    public init(
        exercises: [Exercise],
        warmups: [Warmup],
        cooldowns: [Cooldown],
        reminders: [Reminder],
        programState: State
    ) {
        self.exercises = exercises
        self.warmups = warmups
        self.cooldowns = cooldowns
        self.reminders = reminders
        self.programState = programState
    }

    public struct Exercise: Equatable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let updatedAt: Date
        public let workoutDayID: UUID
        public let name: String
        public let orderIndex: Int
        public let targetSets: Int
        public let repLow: Int?
        public let repHigh: Int?
        public let rirLow: Int
        public let rirHigh: Int
        public let category: ExerciseCategory
        public let allowFailure: Bool
        public let cues: String
        public let safetyNote: String?
        public let startingWeightKg: Double?
        public let progressionRule: ProgressionRule
        public let measurementKind: ExerciseMeasurementKind
        public let supersetGroupID: UUID?
        public let supersetOrder: Int?
    }

    public struct Warmup: Equatable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let updatedAt: Date
        public let workoutDayID: UUID
        public let phase: WarmupPhase
        public let movement: String
        public let dose: String
        public let orderIndex: Int
    }

    public struct Cooldown: Equatable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let updatedAt: Date
        public let workoutDayID: UUID
        public let movement: String
        public let dose: String
        public let note: String?
        public let orderIndex: Int
    }

    public struct Reminder: Equatable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let updatedAt: Date
        public let name: String
        public let dueDate: Date
        public let recurrence: HealthCheckRecurrence
        public let status: HealthCheckStatus
    }

    public struct State: Equatable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let updatedAt: Date
        public let programID: UUID
        public let currentPhaseID: UUID
        public let phaseStartedAt: Date
        public let trainingWeekIndex: Int
        public let deloadStatus: DeloadStatus
        public let deloadReason: DeloadReason?
        public let deloadUpdatedAt: Date?
        public let lastDeloadSkippedAt: Date?
        public let lastDeloadAction: DeloadAction?
    }
}
