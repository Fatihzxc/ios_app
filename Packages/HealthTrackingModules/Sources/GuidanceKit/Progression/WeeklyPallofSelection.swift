import Foundation

public enum WeeklyPallofSelection {
    public enum Variant: String, Equatable, Sendable {
        case pallof
        case plank
    }

    public struct Completion: Equatable, Sendable {
        public let id: UUID
        public let exerciseTemplateID: UUID
        public let completedAt: Date
        public let performedVariant: Variant?

        public init(
            id: UUID,
            exerciseTemplateID: UUID,
            completedAt: Date,
            performedVariant: Variant?
        ) {
            self.id = id
            self.exerciseTemplateID = exerciseTemplateID
            self.completedAt = completedAt
            self.performedVariant = performedVariant
        }
    }

    public struct Input: Equatable, Sendable {
        public let eligibleExerciseTemplateIDs: Set<UUID>
        public let completions: [Completion]

        public init(
            eligibleExerciseTemplateIDs: Set<UUID>,
            completions: [Completion]
        ) {
            self.eligibleExerciseTemplateIDs = eligibleExerciseTemplateIDs
            self.completions = completions
        }
    }

    public enum Reason: Equatable, Sendable {
        case pallofDue
        case pallofCompletedThisWeek
    }

    public struct Suggestion: Equatable, Sendable {
        public let proposedVariant: Variant
        public let reason: Reason

        public init(proposedVariant: Variant, reason: Reason) {
            self.proposedVariant = proposedVariant
            self.reason = reason
        }
    }

    public enum DataError: Error, Equatable, Sendable {
        case missingEligibleTemplates
        case calendarCalculationFailed
    }

    public enum Outcome: Equatable, Sendable {
        case suggestion(Suggestion)
        case invalid(DataError)
    }

    public static func resolve(
        input: Input,
        now: Date,
        calendar: Calendar
    ) -> Outcome {
        guard !input.eligibleExerciseTemplateIDs.isEmpty else {
            return .invalid(.missingEligibleTemplates)
        }
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return .invalid(.calendarCalculationFailed)
        }

        let completedPallof = input.completions.contains {
            input.eligibleExerciseTemplateIDs.contains($0.exerciseTemplateID)
                && currentWeek.contains($0.completedAt)
                && $0.performedVariant == .pallof
        }
        if completedPallof {
            return .suggestion(
                Suggestion(
                    proposedVariant: .plank,
                    reason: .pallofCompletedThisWeek
                )
            )
        }
        return .suggestion(
            Suggestion(proposedVariant: .pallof, reason: .pallofDue)
        )
    }
}
