public enum EquipmentCeiling {
    public static let maximumWeightKg = 20.0

    public enum NextStep: Equatable, Sendable {
        case repetitions
        case tempo
        case unilateral
    }

    public enum Reason: Equatable, Sendable {
        case belowCeiling
        case atCeiling
    }

    public struct Input: Equatable, Sendable {
        public let suggestedWeightKg: Double?
        public let suggestedReps: Int?
        public let definedTempo: String?
        public let definedUnilateralVariant: String?

        public init(
            suggestedWeightKg: Double?,
            suggestedReps: Int?,
            definedTempo: String? = nil,
            definedUnilateralVariant: String? = nil
        ) {
            self.suggestedWeightKg = suggestedWeightKg
            self.suggestedReps = suggestedReps
            self.definedTempo = definedTempo
            self.definedUnilateralVariant = definedUnilateralVariant
        }
    }

    public struct Decision: Equatable, Sendable {
        public let suggestedWeightKg: Double?
        public let suggestedReps: Int?
        public let reason: Reason
        public let orderedNextSteps: [NextStep]
        public let definedTempo: String?
        public let definedUnilateralVariant: String?
        public let showsInvestmentInformation: Bool

        public init(
            suggestedWeightKg: Double?,
            suggestedReps: Int?,
            reason: Reason,
            orderedNextSteps: [NextStep],
            definedTempo: String?,
            definedUnilateralVariant: String?,
            showsInvestmentInformation: Bool
        ) {
            self.suggestedWeightKg = suggestedWeightKg
            self.suggestedReps = suggestedReps
            self.reason = reason
            self.orderedNextSteps = orderedNextSteps
            self.definedTempo = definedTempo
            self.definedUnilateralVariant = definedUnilateralVariant
            self.showsInvestmentInformation = showsInvestmentInformation
        }
    }

    public static func apply(_ input: Input) -> Decision {
        guard let weightKg = realWeight(input.suggestedWeightKg),
              weightKg >= maximumWeightKg else {
            return Decision(
                suggestedWeightKg: input.suggestedWeightKg,
                suggestedReps: input.suggestedReps,
                reason: .belowCeiling,
                orderedNextSteps: [],
                definedTempo: input.definedTempo,
                definedUnilateralVariant: input.definedUnilateralVariant,
                showsInvestmentInformation: false
            )
        }

        return Decision(
            suggestedWeightKg: maximumWeightKg,
            suggestedReps: input.suggestedReps,
            reason: .atCeiling,
            orderedNextSteps: [.repetitions, .tempo, .unilateral],
            definedTempo: input.definedTempo,
            definedUnilateralVariant: input.definedUnilateralVariant,
            showsInvestmentInformation: true
        )
    }

    private static func realWeight(_ weightKg: Double?) -> Double? {
        guard let weightKg, weightKg.isFinite, weightKg > 0 else { return nil }
        return weightKg
    }
}
