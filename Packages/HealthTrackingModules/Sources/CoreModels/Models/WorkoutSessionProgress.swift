import Foundation
import SwiftData

@Model
public final class WorkoutSessionProgress {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var workoutSessionId: UUID = UUID()
    public var stage: WorkoutSessionProgressStage = WorkoutSessionProgressStage.warmup
    public var currentExerciseTemplateId: UUID?
    public var completedWarmupItemIdsData: Data = Data()
    public var completedCooldownItemIdsData: Data = Data()
    public var warmupDisposition: WorkoutChecklistDisposition = WorkoutChecklistDisposition.pending
    public var cooldownDisposition: WorkoutChecklistDisposition = WorkoutChecklistDisposition.pending

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        workoutSessionId: UUID = UUID(),
        stage: WorkoutSessionProgressStage = .warmup,
        currentExerciseTemplateId: UUID? = nil,
        completedWarmupItemIdsData: Data = WorkoutSessionProgressCodec.emptyPayload,
        completedCooldownItemIdsData: Data = WorkoutSessionProgressCodec.emptyPayload,
        warmupDisposition: WorkoutChecklistDisposition = .pending,
        cooldownDisposition: WorkoutChecklistDisposition = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workoutSessionId = workoutSessionId
        self.stage = stage
        self.currentExerciseTemplateId = currentExerciseTemplateId
        self.completedWarmupItemIdsData = completedWarmupItemIdsData
        self.completedCooldownItemIdsData = completedCooldownItemIdsData
        self.warmupDisposition = warmupDisposition
        self.cooldownDisposition = cooldownDisposition
    }
}
