import CoreModels
import Foundation

public struct M0SeedPayload: Equatable, Sendable {
    public let profile: Profile
    public let program: Program
    public let phases: [Phase]
    public let workoutDays: [WorkoutDay]

    public init(profile: Profile, program: Program, phases: [Phase], workoutDays: [WorkoutDay]) {
        self.profile = profile
        self.program = program
        self.phases = phases
        self.workoutDays = workoutDays
    }

    public struct Profile: Equatable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let updatedAt: Date
        public let displayName: String
        public let heightCm: Double
        public let startWeightKg: Double
        public let targetWeightKg: Double
        public let unitsSystem: UnitsSystem
        public let proteinTargetG: Double
        public let calorieTarget: Double?
        public let carbTargetG: Double?
        public let fatTargetG: Double?
        public let programStartDate: Date
        public let weeklyWorkoutTarget: Int
    }

    public struct Program: Equatable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let updatedAt: Date
        public let name: String
        public let descriptionText: String
        public let isActive: Bool
    }

    public struct Phase: Equatable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let updatedAt: Date
        public let name: String
        public let orderIndex: Int
        public let monthStart: Int
        public let monthEnd: Int
        public let trainingFocus: String
        public let nutritionFocus: String
        public let milestone: String
        public let entryCriteria: String
    }

    public struct WorkoutDay: Equatable, Sendable {
        public let id: UUID
        public let createdAt: Date
        public let updatedAt: Date
        public let name: String
        public let orderIndex: Int
        public let focus: String
    }
}
