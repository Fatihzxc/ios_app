public enum UnitsSystem: String, Codable, CaseIterable, Sendable {
    case metric
    case imperial
}

public enum ExerciseCategory: String, Codable, CaseIterable, Sendable {
    case compound
    case accessory
    case core
}

public enum ProgressionRule: String, Codable, CaseIterable, Sendable {
    case doubleProgression
    case gradedEntryOHP
    case boneFocusHeavy
    case timeQuality
    case bodyweightProgression
}

public enum ExerciseMeasurementKind: String, Codable, CaseIterable, Sendable {
    case weightReps
    case reps
    case duration
    case steps
    case quality
}

public enum WorkoutSessionStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case inProgress
    case completed
    case skipped
}

public enum WarmupPhase: String, Codable, CaseIterable, Sendable {
    case raise
    case activate
    case potentiate
}

public enum BodyMetricType: String, Codable, CaseIterable, Sendable {
    case weight
    case waist
    case custom
}

public enum ProgressPhotoPose: String, Codable, CaseIterable, Sendable {
    case front
    case side
    case back
}

public enum HealthCheckRecurrence: String, Codable, CaseIterable, Sendable {
    case none
    case monthly
    case quarterly
    case yearly
}

public enum HealthCheckStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case done
}

public enum FoodSource: String, Codable, CaseIterable, Sendable {
    case userCreated
    case healthKit
}

public enum AppReminderType: String, Codable, CaseIterable, Sendable {
    case workout
    case measurement
    case bloodwork
    case mealLog
    case custom
}

public enum DeloadStatus: String, Codable, CaseIterable, Sendable {
    case none
    case recommended
    case active
    case skipped
}

public enum DeloadReason: String, Codable, CaseIterable, Sendable {
    case scheduled
    case reactive
}

public enum DeloadAction: String, Codable, CaseIterable, Sendable {
    case accepted
    case stay
    case techniqueReview
    case skipped
}

public enum OHPSymptomResponse: String, Codable, CaseIterable, Sendable {
    case notAsked
    case symptomFree
    case symptomsPresent
    case uncertain
}
