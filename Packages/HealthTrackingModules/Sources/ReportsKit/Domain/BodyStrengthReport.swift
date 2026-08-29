import Foundation

public struct ReportBodyMetricPoint: Equatable, Sendable {
    public let observationID: UUID
    public let date: Date
    public let localDay: Date
    public let createdAt: Date
    public let kind: ReportBodyMetricKind
    public let customName: String?
    public let value: Double
    public let unit: String

    public init(
        observationID: UUID,
        date: Date,
        localDay: Date,
        createdAt: Date,
        kind: ReportBodyMetricKind,
        customName: String?,
        value: Double,
        unit: String
    ) {
        self.observationID = observationID
        self.date = date
        self.localDay = localDay
        self.createdAt = createdAt
        self.kind = kind
        self.customName = customName
        self.value = value
        self.unit = unit
    }
}

public struct ReportStrengthSessionPoint: Equatable, Sendable {
    public let sessionID: UUID
    public let sessionDate: Date
    public let sessionCreatedAt: Date
    public let exerciseTemplateID: UUID
    public let exerciseName: String
    public let measurement: ReportExerciseMeasurement
    public let eligibleSetCount: Int
    public let volumeKg: Double?
    public let estimatedOneRepMaxKg: Double?

    public init(
        sessionID: UUID,
        sessionDate: Date,
        sessionCreatedAt: Date,
        exerciseTemplateID: UUID,
        exerciseName: String,
        measurement: ReportExerciseMeasurement,
        eligibleSetCount: Int,
        volumeKg: Double?,
        estimatedOneRepMaxKg: Double?
    ) {
        self.sessionID = sessionID
        self.sessionDate = sessionDate
        self.sessionCreatedAt = sessionCreatedAt
        self.exerciseTemplateID = exerciseTemplateID
        self.exerciseName = exerciseName
        self.measurement = measurement
        self.eligibleSetCount = eligibleSetCount
        self.volumeKg = volumeKg
        self.estimatedOneRepMaxKg = estimatedOneRepMaxKg
    }
}

public struct BodyStrengthReport: Equatable, Sendable {
    public let bodyMetricPoints: [ReportBodyMetricPoint]
    public let strengthSessionPoints: [ReportStrengthSessionPoint]
    public let bodyMetricCoverage: ReportCoverage
    public let strengthCoverage: ReportCoverage

    public init(
        bodyMetricPoints: [ReportBodyMetricPoint],
        strengthSessionPoints: [ReportStrengthSessionPoint]
    ) {
        self.bodyMetricPoints = bodyMetricPoints
        self.strengthSessionPoints = strengthSessionPoints
        bodyMetricCoverage = ReportCoverage(
            observationDates: bodyMetricPoints.map(\.date)
        )
        strengthCoverage = ReportCoverage(
            observationDates: strengthSessionPoints.map(\.sessionDate)
        )
    }
}
