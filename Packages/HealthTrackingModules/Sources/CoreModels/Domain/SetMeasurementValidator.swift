public enum SetMeasurementValidator {
    public static func validate(
        _ input: SetMeasurementInput,
        for kind: ExerciseMeasurementKind
    ) throws {
        try validateOptionalMetadata(input)

        switch kind {
        case .weightReps:
            guard let reps = input.reps, input.weightKg != nil else {
                throw SetMeasurementValidationError.requiredMeasurementMissing
            }
            try validatePositive(reps)
            try rejectIfPresent(input.durationSec != nil || input.distanceSteps != nil)
        case .reps:
            guard let reps = input.reps else {
                throw SetMeasurementValidationError.requiredMeasurementMissing
            }
            try validatePositive(reps)
            try rejectIfPresent(input.durationSec != nil || input.distanceSteps != nil)
        case .duration:
            guard let durationSec = input.durationSec else {
                throw SetMeasurementValidationError.requiredMeasurementMissing
            }
            try validatePositive(durationSec)
            try rejectIfPresent(input.weightKg != nil || input.reps != nil || input.distanceSteps != nil)
        case .steps:
            guard let distanceSteps = input.distanceSteps else {
                throw SetMeasurementValidationError.requiredMeasurementMissing
            }
            try validatePositive(distanceSteps)
            try rejectIfPresent(input.reps != nil || input.durationSec != nil)
        case .quality:
            try rejectIfPresent(input.weightKg != nil || input.distanceSteps != nil)
            try rejectIfPresent(input.reps != nil && input.durationSec != nil)
            if let reps = input.reps {
                try validatePositive(reps)
            }
            if let durationSec = input.durationSec {
                try validatePositive(durationSec)
            }
        }
    }

    private static func validateOptionalMetadata(_ input: SetMeasurementInput) throws {
        if let weightKg = input.weightKg, (!weightKg.isFinite || weightKg < 0) {
            throw SetMeasurementValidationError.invalidWeight
        }
        if let rir = input.rir, !(0...10).contains(rir) {
            throw SetMeasurementValidationError.invalidRIR
        }
    }

    private static func validatePositive(_ value: Int) throws {
        guard value > 0 else {
            throw SetMeasurementValidationError.invalidMeasurement
        }
    }

    private static func rejectIfPresent(_ condition: Bool) throws {
        guard !condition else {
            throw SetMeasurementValidationError.ambiguousMeasurement
        }
    }
}

public enum SetMeasurementValidationError: Error, Equatable, Sendable {
    case requiredMeasurementMissing
    case invalidMeasurement
    case invalidWeight
    case invalidRIR
    case ambiguousMeasurement
}
