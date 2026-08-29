import Foundation

public enum ProteinAdherenceBuilderError: Error, Equatable, Sendable {
    case invalidObservedDay(id: UUID)
    case duplicateObservedDay(date: Date, recordIDs: [UUID])
}

public enum ProteinAdherenceBuilder {
    public static func build(
        days: [ReportNutritionDayRecord]
    ) throws -> ProteinAdherenceReport {
        let observedDays = days.filter { $0.entryCount > 0 }
        if let invalid = observedDays
            .filter({
                !$0.date.timeIntervalSinceReferenceDate.isFinite
                    || !$0.createdAt.timeIntervalSinceReferenceDate.isFinite
                    || !$0.proteinTotalG.isFinite
                    || $0.proteinTotalG < 0
            })
            .min(by: { $0.id.uuidString < $1.id.uuidString }) {
            throw ProteinAdherenceBuilderError.invalidObservedDay(id: invalid.id)
        }

        let groupedByDay = Dictionary(grouping: observedDays, by: \.date)
        if let duplicate = groupedByDay
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key < $1.key })
            .first {
            throw ProteinAdherenceBuilderError.duplicateObservedDay(
                date: duplicate.key,
                recordIDs: duplicate.value
                    .map(\.id)
                    .sorted { $0.uuidString < $1.uuidString }
            )
        }

        let targetDays = observedDays.filter { day in
            day.proteinTargetG.map { $0.isFinite && $0 > 0 } == true
        }
        let hitDays = targetDays.filter { day in
            guard let target = day.proteinTargetG else { return false }
            return day.proteinTotalG >= target
        }
        let adherencePercent = targetDays.isEmpty
            ? nil
            : Double(hitDays.count) / Double(targetDays.count) * 100

        return ProteinAdherenceReport(
            observedDayCount: observedDays.count,
            targetDayCount: targetDays.count,
            hitDayCount: hitDays.count,
            excludedTargetlessDayCount: observedDays.count - targetDays.count,
            adherencePercent: adherencePercent,
            provenance: .currentProfileAppliedToObservedDays
        )
    }
}
