public enum PhaseTrainingFocus {
    public enum ExerciseFocus: Equatable, Sendable {
        case standard
        case boneFocusHeavy
    }

    public enum Reason: Equatable, Sendable {
        case baseSuggestion
        case boneFocusLowerBound
    }

    public struct Input: Equatable, Sendable {
        public let phaseOrderIndex: Int
        public let exerciseFocus: ExerciseFocus
        public let templateRepLow: Int?
        public let baseSuggestedReps: Int?

        public init(
            phaseOrderIndex: Int,
            exerciseFocus: ExerciseFocus,
            templateRepLow: Int?,
            baseSuggestedReps: Int?
        ) {
            self.phaseOrderIndex = phaseOrderIndex
            self.exerciseFocus = exerciseFocus
            self.templateRepLow = templateRepLow
            self.baseSuggestedReps = baseSuggestedReps
        }
    }

    public struct Decision: Equatable, Sendable {
        public let suggestedReps: Int?
        public let reason: Reason

        public init(suggestedReps: Int?, reason: Reason) {
            self.suggestedReps = suggestedReps
            self.reason = reason
        }
    }

    public static func resolve(_ input: Input) -> Decision {
        guard input.phaseOrderIndex >= 3,
              input.exerciseFocus == .boneFocusHeavy,
              let templateRepLow = input.templateRepLow else {
            return Decision(
                suggestedReps: input.baseSuggestedReps,
                reason: .baseSuggestion
            )
        }

        return Decision(
            suggestedReps: templateRepLow,
            reason: .boneFocusLowerBound
        )
    }
}
