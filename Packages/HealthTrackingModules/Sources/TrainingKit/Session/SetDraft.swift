import CoreModels
import Foundation
import Observation

@MainActor
@Observable
public final class SetDraft {
    public enum PrefillSource: Equatable, Sendable {
        case guidance
        case sameSessionPrevious
        case priorSessionSameIndex
        case seed
    }

    public enum Field: Equatable, Hashable, Sendable {
        case weightKg
        case reps
        case durationSec
        case distanceSteps
        case performedVariant
        case rir
    }

    public let workoutSessionID: UUID
    public let exerciseTemplateID: UUID
    public let setIndex: Int
    public let measurementKind: ExerciseMeasurementKind
    public let isWarmupSet: Bool
    public let prefillSource: PrefillSource?
    public var measurement: SetMeasurementInput

    public init(
        workoutSessionID: UUID,
        exerciseTemplateID: UUID,
        setIndex: Int,
        measurementKind: ExerciseMeasurementKind,
        isWarmupSet: Bool,
        guidance: SetMeasurementInput? = nil,
        sameSessionPrevious: SetMeasurementInput? = nil,
        priorSessionSameIndex: SetMeasurementInput? = nil,
        seed: SetMeasurementInput? = nil
    ) {
        self.workoutSessionID = workoutSessionID
        self.exerciseTemplateID = exerciseTemplateID
        self.setIndex = setIndex
        self.measurementKind = measurementKind
        self.isWarmupSet = isWarmupSet

        if let guidance {
            prefillSource = .guidance
            measurement = guidance
        } else if let sameSessionPrevious {
            prefillSource = .sameSessionPrevious
            measurement = sameSessionPrevious
        } else if let priorSessionSameIndex {
            prefillSource = .priorSessionSameIndex
            measurement = priorSessionSameIndex
        } else if let seed {
            prefillSource = .seed
            measurement = seed
        } else {
            prefillSource = nil
            measurement = SetMeasurementInput()
        }
    }

    public var enabledFields: Set<Field> {
        switch measurementKind {
        case .weightReps:
            [.weightKg, .reps, .performedVariant, .rir]
        case .reps:
            [.weightKg, .reps, .performedVariant, .rir]
        case .duration:
            [.durationSec, .performedVariant, .rir]
        case .steps:
            [.weightKg, .distanceSteps, .performedVariant, .rir]
        case .quality:
            [.reps, .durationSec, .performedVariant, .rir]
        }
    }

    public func selectRIR(_ rir: Int?) {
        measurement.rir = rir
    }

    public func selectPerformedVariant(_ performedVariant: String?) {
        let normalized = performedVariant?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        measurement.performedVariant = normalized?.isEmpty == false ? normalized : nil
    }

    public func makeSaveRequest(
        id: UUID = UUID(),
        completedAt: Date = .now
    ) throws -> SetLogSaveRequest {
        try SetMeasurementValidator.validate(measurement, for: measurementKind)
        return SetLogSaveRequest(
            id: id,
            workoutSessionID: workoutSessionID,
            exerciseTemplateID: exerciseTemplateID,
            setIndex: setIndex,
            measurement: measurement,
            isWarmupSet: isWarmupSet,
            completedAt: completedAt
        )
    }
}
