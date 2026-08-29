import Foundation

public struct ReportSleepRecord: Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let createdAt: Date
    public let durationHours: Double
    public let quality: Int

    public init(id: UUID, date: Date, createdAt: Date, durationHours: Double, quality: Int) {
        self.id = id
        self.date = date
        self.createdAt = createdAt
        self.durationHours = durationHours
        self.quality = quality
    }
}

public struct ReportMoodRecord: Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let createdAt: Date
    public let score: Int?
    public let energy: Int?

    public init(id: UUID, date: Date, createdAt: Date, score: Int?, energy: Int?) {
        self.id = id
        self.date = date
        self.createdAt = createdAt
        self.score = score
        self.energy = energy
    }
}

public struct ReportPostureRecord: Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let createdAt: Date
    public let symptomScore: Int?
    public let wallTestPass: Bool?

    public init(
        id: UUID,
        date: Date,
        createdAt: Date,
        symptomScore: Int?,
        wallTestPass: Bool?
    ) {
        self.id = id
        self.date = date
        self.createdAt = createdAt
        self.symptomScore = symptomScore
        self.wallTestPass = wallTestPass
    }
}

public struct ReportProgramPhaseRecord: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let orderIndex: Int

    public init(id: UUID, name: String, orderIndex: Int) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
    }
}

public struct ReportCurrentPhaseStateRecord: Equatable, Sendable {
    public let programID: UUID
    public let phaseID: UUID
    public let phaseStartedAt: Date

    public init(programID: UUID, phaseID: UUID, phaseStartedAt: Date) {
        self.programID = programID
        self.phaseID = phaseID
        self.phaseStartedAt = phaseStartedAt
    }
}

public struct ReportPhaseTransitionRecord: Equatable, Sendable {
    public let id: UUID
    public let programID: UUID
    public let fromPhaseID: UUID
    public let toPhaseID: UUID
    public let fromStartedAt: Date
    public let transitionedAt: Date

    public init(
        id: UUID,
        programID: UUID,
        fromPhaseID: UUID,
        toPhaseID: UUID,
        fromStartedAt: Date,
        transitionedAt: Date
    ) {
        self.id = id
        self.programID = programID
        self.fromPhaseID = fromPhaseID
        self.toPhaseID = toPhaseID
        self.fromStartedAt = fromStartedAt
        self.transitionedAt = transitionedAt
    }
}

public struct ReportNumericPoint: Equatable, Sendable {
    public let observationID: UUID
    public let date: Date
    public let localDay: Date
    public let value: Double

    public init(observationID: UUID, date: Date, localDay: Date, value: Double) {
        self.observationID = observationID
        self.date = date
        self.localDay = localDay
        self.value = value
    }
}

public struct ReportNumericSeries: Equatable, Sendable {
    public let points: [ReportNumericPoint]

    public init(points: [ReportNumericPoint]) {
        self.points = points
    }
}

public struct ReportPhaseSegment: Equatable, Sendable {
    public let phaseID: UUID
    public let phaseName: String
    public let startedAt: Date
    public let endedAt: Date?
    public let visibleStart: Date
    public let visibleEndExclusive: Date

    public init(
        phaseID: UUID,
        phaseName: String,
        startedAt: Date,
        endedAt: Date?,
        visibleStart: Date,
        visibleEndExclusive: Date
    ) {
        self.phaseID = phaseID
        self.phaseName = phaseName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.visibleStart = visibleStart
        self.visibleEndExclusive = visibleEndExclusive
    }
}

public enum PhaseTimelineProvenance: String, Equatable, Sendable {
    case unavailable
    case partialCurrentState
    case actualTransitions
}

public struct LifestylePhaseReport: Equatable, Sendable {
    public let sleepDurationSeries: [ReportNumericSeries]
    public let moodScoreSeries: [ReportNumericSeries]
    public let postureSymptomSeries: [ReportNumericSeries]
    public let sleepCoverage: ReportCoverage
    public let moodCoverage: ReportCoverage
    public let postureCoverage: ReportCoverage
    public let phaseSegments: [ReportPhaseSegment]
    public let phaseTimelineProvenance: PhaseTimelineProvenance

    public init(
        sleepDurationSeries: [ReportNumericSeries],
        moodScoreSeries: [ReportNumericSeries],
        postureSymptomSeries: [ReportNumericSeries],
        sleepCoverage: ReportCoverage,
        moodCoverage: ReportCoverage,
        postureCoverage: ReportCoverage,
        phaseSegments: [ReportPhaseSegment],
        phaseTimelineProvenance: PhaseTimelineProvenance
    ) {
        self.sleepDurationSeries = sleepDurationSeries
        self.moodScoreSeries = moodScoreSeries
        self.postureSymptomSeries = postureSymptomSeries
        self.sleepCoverage = sleepCoverage
        self.moodCoverage = moodCoverage
        self.postureCoverage = postureCoverage
        self.phaseSegments = phaseSegments
        self.phaseTimelineProvenance = phaseTimelineProvenance
    }
}
