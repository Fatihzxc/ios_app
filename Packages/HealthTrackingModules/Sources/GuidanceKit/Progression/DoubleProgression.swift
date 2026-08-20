import Foundation

public enum DoubleProgression {
    public struct WorkingSet: Equatable, Sendable {
        public let setIndex: Int
        public let weightKg: Double?
        public let reps: Int?
        public let rir: Int?
        public let isWarmupSet: Bool

        public init(
            setIndex: Int,
            weightKg: Double?,
            reps: Int?,
            rir: Int?,
            isWarmupSet: Bool
        ) {
            self.setIndex = setIndex
            self.weightKg = weightKg
            self.reps = reps
            self.rir = rir
            self.isWarmupSet = isWarmupSet
        }
    }

    public struct Input: Equatable, Sendable {
        public let repLow: Int
        public let repHigh: Int?
        public let rirLow: Int
        public let sets: [WorkingSet]

        public init(
            repLow: Int,
            repHigh: Int?,
            rirLow: Int,
            sets: [WorkingSet]
        ) {
            self.repLow = repLow
            self.repHigh = repHigh
            self.rirLow = rirLow
            self.sets = sets
        }
    }

    public struct ProposedMeasurement: Equatable, Sendable {
        public let weightKg: Double?
        public let reps: Int?

        public init(weightKg: Double?, reps: Int?) {
            self.weightKg = weightKg
            self.reps = reps
        }
    }

    public enum HoldReason: Equatable, Sendable {
        case noWorkingSets
        case missingRepCeiling
        case repetitionsBelowCeiling
        case missingRIR
        case rirAboveThreshold
        case missingExternalWeight
    }

    public enum Reason: Equatable, Sendable {
        case increase
        case hold(HoldReason)
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
            return hold(weightKg: nil, reps: nil, reason: .noWorkingSets)
        }

        let lastExternalWeight = realExternalWeight(lastSet.weightKg)
        guard let repHigh = input.repHigh else {
            return hold(
                weightKg: lastExternalWeight,
                reps: lastSet.reps,
                reason: .missingRepCeiling
            )
        }
        guard workingSets.allSatisfy({ ($0.reps ?? Int.min) >= repHigh }) else {
            return hold(
                weightKg: lastExternalWeight,
                reps: repHigh,
                reason: .repetitionsBelowCeiling
            )
        }
        guard workingSets.allSatisfy({ $0.rir != nil }) else {
            return hold(
                weightKg: lastExternalWeight,
                reps: repHigh,
                reason: .missingRIR
            )
        }
        guard workingSets.allSatisfy({ ($0.rir ?? Int.max) <= input.rirLow }) else {
            return hold(
                weightKg: lastExternalWeight,
                reps: repHigh,
                reason: .rirAboveThreshold
            )
        }
        guard let lastExternalWeight else {
            return hold(
                weightKg: nil,
                reps: repHigh,
                reason: .missingExternalWeight
            )
        }

        return Suggestion(
            proposedMeasurement: ProposedMeasurement(
                weightKg: lastExternalWeight + 2.5,
                reps: input.repLow
            ),
            reason: .increase
        )
    }

    private static func realExternalWeight(_ weightKg: Double?) -> Double? {
        guard let weightKg, weightKg.isFinite, weightKg > 0 else { return nil }
        return weightKg
    }

    private static func hold(
        weightKg: Double?,
        reps: Int?,
        reason: HoldReason
    ) -> Suggestion {
        Suggestion(
            proposedMeasurement: ProposedMeasurement(weightKg: weightKg, reps: reps),
            reason: .hold(reason)
        )
    }
}
