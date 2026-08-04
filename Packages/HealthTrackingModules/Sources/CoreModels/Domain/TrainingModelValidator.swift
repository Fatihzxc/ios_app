public enum TrainingModelValidationError: Error, Equatable, Sendable {
    case weeklyWorkoutTargetOutOfRange
    case trainingWeekIndexOutOfRange
}

public enum TrainingModelValidator {
    public static func validateWeeklyWorkoutTarget(_ weeklyWorkoutTarget: Int) throws {
        guard (1...7).contains(weeklyWorkoutTarget) else {
            throw TrainingModelValidationError.weeklyWorkoutTargetOutOfRange
        }
    }

    public static func validateTrainingWeekIndex(_ trainingWeekIndex: Int) throws {
        guard trainingWeekIndex >= 1 else {
            throw TrainingModelValidationError.trainingWeekIndexOutOfRange
        }
    }
}
