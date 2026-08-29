import Foundation

public enum LifestyleObservationKind: String, Equatable, Sendable {
    case sleep
    case mood
    case posture
}

public enum LifestylePhaseDatasetError: Error, Equatable, Sendable {
    case invalidInterval
    case invalidRecord(kind: LifestyleObservationKind, id: UUID)
    case duplicateRecordID(kind: LifestyleObservationKind, id: UUID)
    case duplicateLocalDay(kind: LifestyleObservationKind, localDay: Date, recordIDs: [UUID])
    case duplicatePhaseID(id: UUID)
    case invalidPhase(id: UUID)
    case missingPhase(id: UUID)
    case invalidCurrentState(programID: UUID)
    case duplicateTransitionID(id: UUID)
    case duplicateLogicalTransition(recordIDs: [UUID])
    case duplicateTransitionTimestamp(transitionedAt: Date, recordIDs: [UUID])
    case invalidTransition(id: UUID)
    case crossProgramTransition(id: UUID)
    case brokenTransitionChain(previousID: UUID, id: UUID)
    case inconsistentCurrentState(programID: UUID)
}

public enum LifestylePhaseDatasetBuilder {
    public static func build(
        source: ReportsDashboardSource,
        interval: ReportDateInterval,
        calendar: Calendar
    ) throws -> LifestylePhaseReport {
        try build(
            sleepRecords: source.sleepRecords,
            moodRecords: source.moodRecords,
            postureRecords: source.postureRecords,
            phases: source.programPhases,
            currentState: source.currentPhaseState,
            transitions: source.phaseTransitions,
            interval: interval,
            calendar: calendar
        )
    }

    public static func build(
        sleepRecords: [ReportSleepRecord],
        moodRecords: [ReportMoodRecord],
        postureRecords: [ReportPostureRecord],
        phases: [ReportProgramPhaseRecord],
        currentState: ReportCurrentPhaseStateRecord?,
        transitions: [ReportPhaseTransitionRecord],
        interval: ReportDateInterval,
        calendar: Calendar
    ) throws -> LifestylePhaseReport {
        guard validDate(interval.start), validDate(interval.endExclusive),
              interval.start < interval.endExclusive else {
            throw LifestylePhaseDatasetError.invalidInterval
        }

        let sleep = try sleepPoints(sleepRecords, interval: interval, calendar: calendar)
        let mood = try moodPoints(moodRecords, interval: interval, calendar: calendar)
        let posture = try posturePoints(postureRecords, interval: interval, calendar: calendar)
        let timeline = try phaseTimeline(
            phases: phases,
            state: currentState,
            transitions: transitions,
            interval: interval
        )
        return LifestylePhaseReport(
            sleepDurationSeries: splitAtMissingDays(sleep, calendar: calendar),
            moodScoreSeries: splitAtMissingDays(mood, calendar: calendar),
            postureSymptomSeries: splitAtMissingDays(posture, calendar: calendar),
            sleepCoverage: ReportCoverage(observationDates: sleep.map(\.date)),
            moodCoverage: ReportCoverage(observationDates: mood.map(\.date)),
            postureCoverage: ReportCoverage(observationDates: posture.map(\.date)),
            phaseSegments: timeline.segments,
            phaseTimelineProvenance: timeline.provenance
        )
    }

    private static func sleepPoints(
        _ records: [ReportSleepRecord],
        interval: ReportDateInterval,
        calendar: Calendar
    ) throws -> [ReportNumericPoint] {
        let selected = records.filter { interval.contains($0.date) }
        try rejectDuplicateIDs(selected, kind: .sleep, id: \.id)
        if let invalid = selected
            .filter({
                !validDate($0.date) || !validDate($0.createdAt)
                    || !$0.durationHours.isFinite
                    || !($0.durationHours > 0 && $0.durationHours <= 24)
                    || !(1...10).contains($0.quality)
            })
            .min(by: stableIDOrder) {
            throw LifestylePhaseDatasetError.invalidRecord(kind: .sleep, id: invalid.id)
        }
        try rejectDuplicateDays(selected, kind: .sleep, calendar: calendar, id: \.id, date: \.date)
        return selected.map {
            ReportNumericPoint(
                observationID: $0.id,
                date: $0.date,
                localDay: calendar.startOfDay(for: $0.date),
                value: $0.durationHours
            )
        }.sorted(by: pointOrder)
    }

    private static func moodPoints(
        _ records: [ReportMoodRecord],
        interval: ReportDateInterval,
        calendar: Calendar
    ) throws -> [ReportNumericPoint] {
        let selected = records.filter { interval.contains($0.date) }
        try rejectDuplicateIDs(selected, kind: .mood, id: \.id)
        if let invalid = selected
            .filter({
                !validDate($0.date) || !validDate($0.createdAt)
                    || $0.score.map { !(0...10).contains($0) } == true
                    || $0.energy.map { !(0...10).contains($0) } == true
            })
            .min(by: stableIDOrder) {
            throw LifestylePhaseDatasetError.invalidRecord(kind: .mood, id: invalid.id)
        }
        try rejectDuplicateDays(selected, kind: .mood, calendar: calendar, id: \.id, date: \.date)
        return selected.compactMap { record in
            record.score.map {
                ReportNumericPoint(
                    observationID: record.id,
                    date: record.date,
                    localDay: calendar.startOfDay(for: record.date),
                    value: Double($0)
                )
            }
        }.sorted(by: pointOrder)
    }

    private static func posturePoints(
        _ records: [ReportPostureRecord],
        interval: ReportDateInterval,
        calendar: Calendar
    ) throws -> [ReportNumericPoint] {
        let selected = records.filter { interval.contains($0.date) }
        try rejectDuplicateIDs(selected, kind: .posture, id: \.id)
        if let invalid = selected
            .filter({
                !validDate($0.date) || !validDate($0.createdAt)
                    || $0.symptomScore.map { !(0...10).contains($0) } == true
            })
            .min(by: stableIDOrder) {
            throw LifestylePhaseDatasetError.invalidRecord(kind: .posture, id: invalid.id)
        }
        try rejectDuplicateDays(selected, kind: .posture, calendar: calendar, id: \.id, date: \.date)
        return selected.compactMap { record in
            record.symptomScore.map {
                ReportNumericPoint(
                    observationID: record.id,
                    date: record.date,
                    localDay: calendar.startOfDay(for: record.date),
                    value: Double($0)
                )
            }
        }.sorted(by: pointOrder)
    }

    private static func phaseTimeline(
        phases: [ReportProgramPhaseRecord],
        state: ReportCurrentPhaseStateRecord?,
        transitions: [ReportPhaseTransitionRecord],
        interval: ReportDateInterval
    ) throws -> (segments: [ReportPhaseSegment], provenance: PhaseTimelineProvenance) {
        let groupedPhases = Dictionary(grouping: phases, by: \.id)
        if let duplicate = groupedPhases
            .filter({ $0.value.count > 1 })
            .sorted(by: { uuidOrder($0.key, $1.key) })
            .first {
            throw LifestylePhaseDatasetError.duplicatePhaseID(id: duplicate.key)
        }
        if let invalid = phases
            .filter({
                let trimmed = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty || trimmed != $0.name || $0.orderIndex < 0
            })
            .min(by: stableIDOrder) {
            throw LifestylePhaseDatasetError.invalidPhase(id: invalid.id)
        }
        let phaseByID = Dictionary(uniqueKeysWithValues: phases.map { ($0.id, $0) })
        guard let state else {
            guard transitions.isEmpty else {
                throw LifestylePhaseDatasetError.inconsistentCurrentState(
                    programID: transitions.sorted(by: transitionOrder)[0].programID
                )
            }
            return ([], .unavailable)
        }
        guard validDate(state.phaseStartedAt) else {
            throw LifestylePhaseDatasetError.invalidCurrentState(programID: state.programID)
        }
        guard phaseByID[state.phaseID] != nil else {
            throw LifestylePhaseDatasetError.missingPhase(id: state.phaseID)
        }

        let ordered = transitions.sorted(by: transitionOrder)
        let transitionIDs = Dictionary(grouping: ordered, by: \.id)
        if let duplicate = transitionIDs
            .filter({ $0.value.count > 1 })
            .sorted(by: { uuidOrder($0.key, $1.key) })
            .first {
            throw LifestylePhaseDatasetError.duplicateTransitionID(id: duplicate.key)
        }
        let logicalTransitions = Dictionary(
            grouping: ordered,
            by: ReportLogicalTransitionKey.init
        )
        if let duplicate = logicalTransitions
            .filter({ $0.value.count > 1 })
            .sorted(by: { logicalTransitionKeyOrder($0.key, $1.key) })
            .first {
            throw LifestylePhaseDatasetError.duplicateLogicalTransition(
                recordIDs: duplicate.value.map(\.id).sorted(by: uuidOrder)
            )
        }
        let timestamps = Dictionary(grouping: ordered, by: \.transitionedAt)
        if let duplicate = timestamps
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key < $1.key })
            .first {
            throw LifestylePhaseDatasetError.duplicateTransitionTimestamp(
                transitionedAt: duplicate.key,
                recordIDs: duplicate.value.map(\.id).sorted(by: uuidOrder)
            )
        }
        for record in ordered {
            guard record.programID == state.programID else {
                throw LifestylePhaseDatasetError.crossProgramTransition(id: record.id)
            }
            guard validDate(record.fromStartedAt), validDate(record.transitionedAt),
                  record.fromStartedAt < record.transitionedAt,
                  record.fromPhaseID != record.toPhaseID else {
                throw LifestylePhaseDatasetError.invalidTransition(id: record.id)
            }
            guard phaseByID[record.fromPhaseID] != nil else {
                throw LifestylePhaseDatasetError.missingPhase(id: record.fromPhaseID)
            }
            guard phaseByID[record.toPhaseID] != nil else {
                throw LifestylePhaseDatasetError.missingPhase(id: record.toPhaseID)
            }
        }
        for index in ordered.indices.dropFirst() {
            let previous = ordered[index - 1]
            let current = ordered[index]
            guard current.fromPhaseID == previous.toPhaseID,
                  current.fromStartedAt == previous.transitionedAt else {
                throw LifestylePhaseDatasetError.brokenTransitionChain(
                    previousID: previous.id,
                    id: current.id
                )
            }
        }

        guard let last = ordered.last else {
            let phase = phaseByID[state.phaseID]!
            return (
                clippedSegment(
                    phase: phase,
                    startedAt: state.phaseStartedAt,
                    endedAt: nil,
                    interval: interval
                ).map { [$0] } ?? [],
                .partialCurrentState
            )
        }
        guard state.phaseID == last.toPhaseID,
              state.phaseStartedAt == last.transitionedAt else {
            throw LifestylePhaseDatasetError.inconsistentCurrentState(programID: state.programID)
        }

        let first = ordered[0]
        var evidence: [(phaseID: UUID, start: Date, end: Date?)] = [
            (first.fromPhaseID, first.fromStartedAt, first.transitionedAt)
        ]
        for index in ordered.indices {
            let record = ordered[index]
            let end = index + 1 < ordered.count ? ordered[index + 1].transitionedAt : nil
            evidence.append((record.toPhaseID, record.transitionedAt, end))
        }
        let segments = evidence.compactMap { item -> ReportPhaseSegment? in
            clippedSegment(
                phase: phaseByID[item.phaseID]!,
                startedAt: item.start,
                endedAt: item.end,
                interval: interval
            )
        }
        return (segments, .actualTransitions)
    }

    private static func clippedSegment(
        phase: ReportProgramPhaseRecord,
        startedAt: Date,
        endedAt: Date?,
        interval: ReportDateInterval
    ) -> ReportPhaseSegment? {
        let visibleStart = max(startedAt, interval.start)
        let visibleEnd = min(endedAt ?? interval.endExclusive, interval.endExclusive)
        guard visibleStart < visibleEnd else { return nil }
        return ReportPhaseSegment(
            phaseID: phase.id,
            phaseName: phase.name,
            startedAt: startedAt,
            endedAt: endedAt,
            visibleStart: visibleStart,
            visibleEndExclusive: visibleEnd
        )
    }

    private static func splitAtMissingDays(
        _ points: [ReportNumericPoint],
        calendar: Calendar
    ) -> [ReportNumericSeries] {
        guard let first = points.first else { return [] }
        var groups: [[ReportNumericPoint]] = [[first]]
        for point in points.dropFirst() {
            let previous = groups[groups.count - 1][groups[groups.count - 1].count - 1]
            let nextDay = calendar.date(byAdding: .day, value: 1, to: previous.localDay)
            if nextDay == point.localDay {
                groups[groups.count - 1].append(point)
            } else {
                groups.append([point])
            }
        }
        return groups.map { ReportNumericSeries(points: $0) }
    }

    private static func rejectDuplicateIDs<Record>(
        _ records: [Record],
        kind: LifestyleObservationKind,
        id: KeyPath<Record, UUID>
    ) throws {
        let grouped = Dictionary(grouping: records) { $0[keyPath: id] }
        if let duplicate = grouped.filter({ $0.value.count > 1 })
            .sorted(by: { uuidOrder($0.key, $1.key) }).first {
            throw LifestylePhaseDatasetError.duplicateRecordID(kind: kind, id: duplicate.key)
        }
    }

    private static func rejectDuplicateDays<Record>(
        _ records: [Record],
        kind: LifestyleObservationKind,
        calendar: Calendar,
        id: KeyPath<Record, UUID>,
        date: KeyPath<Record, Date>
    ) throws {
        let grouped = Dictionary(grouping: records) {
            calendar.startOfDay(for: $0[keyPath: date])
        }
        if let duplicate = grouped.filter({ $0.value.count > 1 })
            .sorted(by: { $0.key < $1.key }).first {
            throw LifestylePhaseDatasetError.duplicateLocalDay(
                kind: kind,
                localDay: duplicate.key,
                recordIDs: duplicate.value.map { $0[keyPath: id] }.sorted(by: uuidOrder)
            )
        }
    }

    private static func pointOrder(_ lhs: ReportNumericPoint, _ rhs: ReportNumericPoint) -> Bool {
        if lhs.localDay != rhs.localDay { return lhs.localDay < rhs.localDay }
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return uuidOrder(lhs.observationID, rhs.observationID)
    }

    private static func transitionOrder(
        _ lhs: ReportPhaseTransitionRecord,
        _ rhs: ReportPhaseTransitionRecord
    ) -> Bool {
        if lhs.transitionedAt != rhs.transitionedAt { return lhs.transitionedAt < rhs.transitionedAt }
        return uuidOrder(lhs.id, rhs.id)
    }

    private static func logicalTransitionKeyOrder(
        _ lhs: ReportLogicalTransitionKey,
        _ rhs: ReportLogicalTransitionKey
    ) -> Bool {
        if lhs.transitionedAt != rhs.transitionedAt { return lhs.transitionedAt < rhs.transitionedAt }
        if lhs.fromStartedAt != rhs.fromStartedAt { return lhs.fromStartedAt < rhs.fromStartedAt }
        if lhs.programID != rhs.programID { return uuidOrder(lhs.programID, rhs.programID) }
        if lhs.fromPhaseID != rhs.fromPhaseID { return uuidOrder(lhs.fromPhaseID, rhs.fromPhaseID) }
        return uuidOrder(lhs.toPhaseID, rhs.toPhaseID)
    }

    private static func stableIDOrder<Record>(
        _ lhs: Record,
        _ rhs: Record
    ) -> Bool where Record: ReportIdentifiedRecord {
        uuidOrder(lhs.id, rhs.id)
    }

    private static func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    private static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }
}

private protocol ReportIdentifiedRecord { var id: UUID { get } }
extension ReportSleepRecord: ReportIdentifiedRecord {}
extension ReportMoodRecord: ReportIdentifiedRecord {}
extension ReportPostureRecord: ReportIdentifiedRecord {}
extension ReportProgramPhaseRecord: ReportIdentifiedRecord {}

private struct ReportLogicalTransitionKey: Hashable {
    let programID: UUID
    let fromPhaseID: UUID
    let toPhaseID: UUID
    let fromStartedAt: Date
    let transitionedAt: Date

    init(_ record: ReportPhaseTransitionRecord) {
        programID = record.programID
        fromPhaseID = record.fromPhaseID
        toPhaseID = record.toPhaseID
        fromStartedAt = record.fromStartedAt
        transitionedAt = record.transitionedAt
    }
}
