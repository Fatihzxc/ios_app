public struct SetMeasurementInput: Equatable, Sendable {
    public var weightKg: Double?
    public var reps: Int?
    public var durationSec: Int?
    public var distanceSteps: Int?
    public var performedVariant: String?
    public var rir: Int?

    public init(
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSec: Int? = nil,
        distanceSteps: Int? = nil,
        performedVariant: String? = nil,
        rir: Int? = nil
    ) {
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.distanceSteps = distanceSteps
        self.performedVariant = performedVariant
        self.rir = rir
    }
}
