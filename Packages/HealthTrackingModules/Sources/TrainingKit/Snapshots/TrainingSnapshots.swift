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
