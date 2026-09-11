import Foundation
import GuidanceKit

public enum BodyStrengthDatasetError: Error, Equatable, Sendable {
    case invalidRepetitionRange(recordID: UUID, reps: Int)
    case duplicateSetIndex(
        sessionID: UUID,
        exerciseTemplateID: UUID,
        setIndex: Int,
        recordIDs: [UUID]
    )
    case inconsistentStrengthGroup(
        sessionID: UUID,
        exerciseTemplateID: UUID,
        field: ReportStrengthGroupField
    )
    case nonFiniteVolume(sessionID: UUID, exerciseTemplateID: UUID)
    case nonFiniteEpleyEstimate(sessionID: UUID, exerciseTemplateID: UUID)
}

public enum ReportStrengthGroupField: Equatable, Sendable {
    case sessionDate
    case sessionCreatedAt
    case exerciseName
    case measurement
}

public enum BodyStrengthDatasetBuilder {
    public static func build(
        bodyMetricRecords: [ReportBodyMetricRecord],
        exerciseSetRecords: [ReportExerciseSetRecord],
        interval: ReportDateInterval,
        calendar: Calendar
    ) throws -> BodyStrengthReport {
        let bodyMetricPoints = reduceBodyMetrics(
            bodyMetricRecords,
            interval: interval,
            calendar: calendar
        )
        let strengthSessionPoints = try reduceStrengthSets(
            exerciseSetRecords,
            interval: interval
        )
        return BodyStrengthReport(
            bodyMetricPoints: bodyMetricPoints,
            strengthSessionPoints: strengthSessionPoints
        )
    }

    private static func reduceBodyMetrics(
        _ records: [ReportBodyMetricRecord],
        interval: ReportDateInterval,
        calendar: Calendar
    ) -> [ReportBodyMetricPoint] {
        var latestByDayAndSeries: [BodyDaySeriesKey: ReportBodyMetricRecord] = [:]

        for record in records where interval.contains(record.date) {
            let key = BodyDaySeriesKey(
                localDay: calendar.startOfDay(for: record.date),
                kind: record.kind.rawValue,
                customName: record.customName,
                unit: record.unit
            )
            if let current = latestByDayAndSeries[key],
               !bodyObservationIsLater(record, than: current) {
                continue
            }
            latestByDayAndSeries[key] = record
        }

        return latestByDayAndSeries.map { key, record in
            ReportBodyMetricPoint(
                observationID: record.id,
                date: record.date,
                localDay: key.localDay,
                createdAt: record.createdAt,
                kind: record.kind,
                customName: record.customName,
                value: record.value,
                unit: record.unit
            )
        }
        .sorted(by: bodyPointOrderedBefore)
    }

    private static func reduceStrengthSets(
        _ records: [ReportExerciseSetRecord],
        interval: ReportDateInterval
    ) throws -> [ReportStrengthSessionPoint] {
        let relevant = records
            .filter {
                interval.contains($0.sessionDate)
                    && $0.sessionCompleted
            }
            .sorted(by: exerciseSetOrderedBefore)
        try rejectLogicalDuplicateSets(relevant)
        let eligible = relevant.filter { !$0.isWarmup }
        let groups = Dictionary(grouping: eligible) { record in
            StrengthGroupKey(
                sessionID: record.sessionID,
                exerciseTemplateID: record.exerciseTemplateID
            )
        }

        let orderedGroups = groups
            .sorted { strengthGroupKeyOrderedBefore($0.key, $1.key) }
            .map { $0.value }

        return try orderedGroups.map { group in
            let first = group[0]
            try validateGroupMetadata(group, against: first)
            var volume: Double?
            var estimatedOneRepMax: Double?

            for record in group {
                if record.measurement == .weightedRepetitions,
                   let reps = record.reps,
                   reps > Int.max - 30 {
                    throw BodyStrengthDatasetError.invalidRepetitionRange(
                        recordID: record.id,
                        reps: reps
                    )
                }
                if let weightKg = record.weightKg, let reps = record.reps {
                    let contribution = weightKg * Double(reps)
                    let accumulated = volume.map { $0 + contribution } ?? contribution
                    guard contribution.isFinite, accumulated.isFinite else {
                        throw BodyStrengthDatasetError.nonFiniteVolume(
                            sessionID: first.sessionID,
                            exerciseTemplateID: first.exerciseTemplateID
                        )
                    }
                    volume = accumulated
                }

                guard record.measurement == .weightedRepetitions else { continue }
                guard
                      let estimate = EpleyEstimate.calculate(
                          weightKg: record.weightKg,
                          reps: record.reps
                      ) else {
                    continue
                }
                guard estimate.isFinite else {
                    throw BodyStrengthDatasetError.nonFiniteEpleyEstimate(
                        sessionID: first.sessionID,
                        exerciseTemplateID: first.exerciseTemplateID
                    )
                }
                if estimatedOneRepMax.map({ estimate > $0 }) != false {
                    estimatedOneRepMax = estimate
                }
            }

            return ReportStrengthSessionPoint(
                sessionID: first.sessionID,
                sessionDate: first.sessionDate,
                sessionCreatedAt: first.sessionCreatedAt,
                exerciseTemplateID: first.exerciseTemplateID,
                exerciseName: first.exerciseName,
                measurement: first.measurement,
                eligibleSetCount: group.count,
                volumeKg: volume,
                estimatedOneRepMaxKg: estimatedOneRepMax
            )
        }
        .sorted(by: strengthPointOrderedBefore)
    }

    private static func rejectLogicalDuplicateSets(
        _ records: [ReportExerciseSetRecord]
    ) throws {
        let grouped = Dictionary(grouping: records) {
            LogicalSetKey(
                sessionID: $0.sessionID,
                exerciseTemplateID: $0.exerciseTemplateID,
                setIndex: $0.setIndex
            )
        }
        guard let duplicate = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { logicalSetKeyOrderedBefore($0.key, $1.key) })
            .first else {
            return
        }
        throw BodyStrengthDatasetError.duplicateSetIndex(
            sessionID: duplicate.key.sessionID,
            exerciseTemplateID: duplicate.key.exerciseTemplateID,
            setIndex: duplicate.key.setIndex,
            recordIDs: duplicate.value.map(\.id).sorted { uuidOrderedBefore($0, $1) }
        )
    }

    private static func validateGroupMetadata(
        _ group: [ReportExerciseSetRecord],
        against first: ReportExerciseSetRecord
    ) throws {
        let field: ReportStrengthGroupField?
        if group.contains(where: { $0.sessionDate != first.sessionDate }) {
            field = .sessionDate
        } else if group.contains(where: { $0.sessionCreatedAt != first.sessionCreatedAt }) {
            field = .sessionCreatedAt
        } else if group.contains(where: { $0.exerciseName != first.exerciseName }) {
            field = .exerciseName
        } else if group.contains(where: { $0.measurement != first.measurement }) {
            field = .measurement
        } else {
            field = nil
        }
        guard let field else { return }
        throw BodyStrengthDatasetError.inconsistentStrengthGroup(
            sessionID: first.sessionID,
            exerciseTemplateID: first.exerciseTemplateID,
            field: field
        )
    }

    private static func logicalSetKeyOrderedBefore(
        _ lhs: LogicalSetKey,
        _ rhs: LogicalSetKey
    ) -> Bool {
        if lhs.sessionID != rhs.sessionID {
            return uuidOrderedBefore(lhs.sessionID, rhs.sessionID)
        }
        if lhs.exerciseTemplateID != rhs.exerciseTemplateID {
            return uuidOrderedBefore(lhs.exerciseTemplateID, rhs.exerciseTemplateID)
        }
        return lhs.setIndex < rhs.setIndex
    }

    private static func strengthGroupKeyOrderedBefore(
        _ lhs: StrengthGroupKey,
        _ rhs: StrengthGroupKey
    ) -> Bool {
        if lhs.sessionID != rhs.sessionID {
            return uuidOrderedBefore(lhs.sessionID, rhs.sessionID)
        }
        return uuidOrderedBefore(lhs.exerciseTemplateID, rhs.exerciseTemplateID)
    }

    private static func uuidOrderedBefore(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    private static func bodyObservationIsLater(
        _ candidate: ReportBodyMetricRecord,
        than current: ReportBodyMetricRecord
    ) -> Bool {
        if candidate.date != current.date { return candidate.date > current.date }
        if candidate.createdAt != current.createdAt {
            return candidate.createdAt > current.createdAt
        }
        return candidate.id.uuidString < current.id.uuidString
    }

    private static func bodyPointOrderedBefore(
        _ lhs: ReportBodyMetricPoint,
        _ rhs: ReportBodyMetricPoint
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.observationID.uuidString < rhs.observationID.uuidString
    }

    private static func exerciseSetOrderedBefore(
        _ lhs: ReportExerciseSetRecord,
        _ rhs: ReportExerciseSetRecord
    ) -> Bool {
        if lhs.sessionDate != rhs.sessionDate { return lhs.sessionDate < rhs.sessionDate }
        if lhs.sessionCreatedAt != rhs.sessionCreatedAt {
            return lhs.sessionCreatedAt < rhs.sessionCreatedAt
        }
        if lhs.sessionID != rhs.sessionID {
            return lhs.sessionID.uuidString < rhs.sessionID.uuidString
        }
        if lhs.exerciseTemplateID != rhs.exerciseTemplateID {
            return lhs.exerciseTemplateID.uuidString < rhs.exerciseTemplateID.uuidString
        }
        if lhs.setIndex != rhs.setIndex { return lhs.setIndex < rhs.setIndex }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func strengthPointOrderedBefore(
        _ lhs: ReportStrengthSessionPoint,
        _ rhs: ReportStrengthSessionPoint
    ) -> Bool {
        if lhs.sessionDate != rhs.sessionDate { return lhs.sessionDate < rhs.sessionDate }
        if lhs.sessionCreatedAt != rhs.sessionCreatedAt {
            return lhs.sessionCreatedAt < rhs.sessionCreatedAt
        }
        if lhs.sessionID != rhs.sessionID {
            return lhs.sessionID.uuidString < rhs.sessionID.uuidString
        }
        return lhs.exerciseTemplateID.uuidString < rhs.exerciseTemplateID.uuidString
    }
}

private struct BodyDaySeriesKey: Hashable {
    let localDay: Date
    let kind: String
    let customName: String?
    let unit: String
}

private struct StrengthGroupKey: Hashable {
    let sessionID: UUID
    let exerciseTemplateID: UUID
}

private struct LogicalSetKey: Hashable {
    let sessionID: UUID
    let exerciseTemplateID: UUID
    let setIndex: Int
}
