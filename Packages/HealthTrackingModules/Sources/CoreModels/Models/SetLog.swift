import Foundation
import SwiftData

@Model
public final class SetLog {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var exerciseTemplateId: UUID = UUID()
    public var setIndex: Int = 0
    public var weightKg: Double?
    public var reps: Int?
    public var durationSec: Int?
    public var distanceSteps: Int?
    public var performedVariant: String?
    public var rir: Int?
    public var isWarmupSet: Bool = false
    public var completedAt: Date = Foundation.Date.now
    public var workoutSession: WorkoutSession?

    public var measurementInput: SetMeasurementInput {
        SetMeasurementInput(
            weightKg: weightKg, reps: reps, durationSec: durationSec,
            distanceSteps: distanceSteps, performedVariant: performedVariant, rir: rir
        )
    }

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        exerciseTemplateId: UUID = UUID(), setIndex: Int = 0, weightKg: Double? = nil,
        reps: Int? = nil, durationSec: Int? = nil, distanceSteps: Int? = nil,
        performedVariant: String? = nil, rir: Int? = nil, isWarmupSet: Bool = false,
        completedAt: Date = .now, workoutSession: WorkoutSession? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exerciseTemplateId = exerciseTemplateId
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.distanceSteps = distanceSteps
        self.performedVariant = performedVariant
        self.rir = rir
        self.isWarmupSet = isWarmupSet
        self.completedAt = completedAt
        self.workoutSession = workoutSession
    }

    public func validate(for kind: ExerciseMeasurementKind) throws {
        try SetMeasurementValidator.validate(measurementInput, for: kind)
    }
}
