import Foundation

public enum ProteinTargetProvenance: String, Equatable, Sendable {
    case currentProfileAppliedToObservedDays
}

public struct ProteinAdherenceReport: Equatable, Sendable {
    public let observedDayCount: Int
    public let targetDayCount: Int
    public let hitDayCount: Int
    public let excludedTargetlessDayCount: Int
    public let adherencePercent: Double?
    public let provenance: ProteinTargetProvenance

    public init(
        observedDayCount: Int,
        targetDayCount: Int,
        hitDayCount: Int,
        excludedTargetlessDayCount: Int,
        adherencePercent: Double?,
        provenance: ProteinTargetProvenance
    ) {
        self.observedDayCount = observedDayCount
        self.targetDayCount = targetDayCount
        self.hitDayCount = hitDayCount
        self.excludedTargetlessDayCount = excludedTargetlessDayCount
        self.adherencePercent = adherencePercent
        self.provenance = provenance
    }
}
