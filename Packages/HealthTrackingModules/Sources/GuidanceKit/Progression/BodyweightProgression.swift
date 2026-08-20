import Foundation

public enum BodyweightProgression {
    public struct WorkingSet: Equatable, Sendable {
        public let setIndex: Int
        public let weightKg: Double?
        public let reps: Int?
        public let performedVariant: String?
        public let isWarmupSet: Bool

        public init(
            setIndex: Int,
            weightKg: Double?,
            reps: Int?,
            performedVariant: String?,
            isWarmupSet: Bool
        ) {
            self.setIndex = setIndex
            self.weightKg = weightKg
            self.reps = reps
            self.performedVariant = performedVariant
            self.isWarmupSet = isWarmupSet
        }
    }

    public struct Input: Equatable, Sendable {
        public let repLow: Int
        public let repHigh: Int?
        public let definedHarderVariant: String?
        public let sets: [WorkingSet]

        public init(
            repLow: Int,
            repHigh: Int?,
            definedHarderVariant: String?,
            sets: [WorkingSet]
        ) {
            self.repLow = repLow
            self.repHigh = repHigh
            self.definedHarderVariant = definedHarderVariant
            self.sets = sets
        }
    }

    public struct ProposedMeasurement: Equatable, Sendable {
        public let weightKg: Double?
        public let reps: Int?
        public let performedVariant: String?

        public init(
            weightKg: Double?,
            reps: Int?,
            performedVariant: String?
        ) {
            self.weightKg = weightKg
            self.reps = reps
            self.performedVariant = performedVariant
        }
    }

    public enum Reason: Equatable, Sendable {
        case noWorkingSets
        case missingRepCeiling
        case inconsistentVariants
        case buildRepetitions
        case advanceToDefinedVariant
        case programAdjustmentRequired
    }

    public struct Suggestion: Equatable, Sendable {
        public let proposedMeasurement: ProposedMeasurement
        public let reason: Reason

        public init(proposedMeasurement: ProposedMeasurement, reason: Reason) {
            self.proposedMeasurement = proposedMeasurement
            self.reason = reason
        }
    }

    public static func suggest(_ input: Input) -> Suggestion {
        let workingSets = input.sets
            .filter { !$0.isWarmupSet }
            .sorted { $0.setIndex < $1.setIndex }
        guard let lastSet = workingSets.last else {
            return suggestion(
                weightKg: nil,
                reps: nil,
                variant: nil,
                reason: .noWorkingSets
            )
        }

        let lastWeight = validOptionalWeight(lastSet.weightKg)
        let lastVariant = normalizedVariant(lastSet.performedVariant)
        guard let repHigh = input.repHigh else {
            return suggestion(
                weightKg: lastWeight,
                reps: lastSet.reps,
                variant: lastVariant,
                reason: .missingRepCeiling
            )
        }

        let variants = Set(workingSets.map { normalizedVariant($0.performedVariant) })
        guard variants.count <= 1 else {
            return suggestion(
                weightKg: lastWeight,
                reps: repHigh,
                variant: lastVariant,
                reason: .inconsistentVariants
            )
        }

        guard workingSets.allSatisfy({ ($0.reps ?? Int.min) >= repHigh }) else {
            return suggestion(
                weightKg: lastWeight,
                reps: repHigh,
                variant: lastVariant,
                reason: .buildRepetitions
            )
        }

        let harderVariant = normalizedVariant(input.definedHarderVariant)
        if let harderVariant, harderVariant != lastVariant {
            return suggestion(
                weightKg: lastWeight,
                reps: input.repLow,
                variant: harderVariant,
                reason: .advanceToDefinedVariant
            )
        }
        return suggestion(
            weightKg: lastWeight,
            reps: repHigh,
            variant: lastVariant,
            reason: .programAdjustmentRequired
        )
    }

    private static func normalizedVariant(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func validOptionalWeight(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func suggestion(
        weightKg: Double?,
        reps: Int?,
        variant: String?,
        reason: Reason
    ) -> Suggestion {
        Suggestion(
            proposedMeasurement: ProposedMeasurement(
                weightKg: weightKg,
                reps: reps,
                performedVariant: variant
            ),
            reason: reason
        )
    }
}
