import Foundation

public struct ReportCoverage: Equatable, Sendable {
    public static let empty = ReportCoverage(observationDates: [])

    public let observedCount: Int
    public let firstObservationAt: Date?
    public let lastObservationAt: Date?

    public init(observationDates: [Date]) {
        observedCount = observationDates.count
        firstObservationAt = observationDates.min()
        lastObservationAt = observationDates.max()
    }

    public init<Value>(observations: [(date: Date, value: Value?)]) {
        self.init(
            observationDates: observations.compactMap { observation in
                observation.value == nil ? nil : observation.date
            }
        )
    }
}

public enum ReportBodyMetricKind: String, CaseIterable, Equatable, Sendable {
    case weight
    case waist
    case custom
}

public struct ReportBodyMetricRecord: Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let createdAt: Date
    public let kind: ReportBodyMetricKind
    public let customName: String?
    public let value: Double
    public let unit: String

    public init(
        id: UUID,
        date: Date,
        createdAt: Date,
        kind: ReportBodyMetricKind,
        customName: String?,
        value: Double,
        unit: String
    ) {
        self.id = id
        self.date = date
        self.createdAt = createdAt
        self.kind = kind
        self.customName = customName
        self.value = value
        self.unit = unit
    }
}

public enum ReportExerciseMeasurement: String, CaseIterable, Equatable, Sendable {
    case weightedRepetitions
    case repetitions
    case duration
    case steps
    case quality
}

public struct ReportExerciseSetRecord: Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let sessionID: UUID
    public let sessionDate: Date
    public let sessionCreatedAt: Date
    public let exerciseTemplateID: UUID
    public let exerciseName: String
    public let setIndex: Int
    public let sessionCompleted: Bool
    public let isWarmup: Bool
    public let measurement: ReportExerciseMeasurement
    public let weightKg: Double?
    public let reps: Int?
    public let durationSec: Int?
    public let distanceSteps: Int?

    public init(
        id: UUID,
        createdAt: Date,
        sessionID: UUID,
        sessionDate: Date,
        sessionCreatedAt: Date,
        exerciseTemplateID: UUID,
        exerciseName: String,
        setIndex: Int,
        sessionCompleted: Bool,
        isWarmup: Bool,
        measurement: ReportExerciseMeasurement,
        weightKg: Double?,
        reps: Int?,
        durationSec: Int?,
        distanceSteps: Int?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sessionID = sessionID
        self.sessionDate = sessionDate
        self.sessionCreatedAt = sessionCreatedAt
        self.exerciseTemplateID = exerciseTemplateID
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.sessionCompleted = sessionCompleted
        self.isWarmup = isWarmup
        self.measurement = measurement
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.distanceSteps = distanceSteps
    }
}

public struct ReportNutritionDayRecord: Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let createdAt: Date
    public let entryCount: Int
    public let proteinTotalG: Double
    public let proteinTargetG: Double?

    public init(
        id: UUID,
        date: Date,
        createdAt: Date,
        entryCount: Int,
        proteinTotalG: Double,
        proteinTargetG: Double?
    ) {
        self.id = id
        self.date = date
        self.createdAt = createdAt
        self.entryCount = entryCount
        self.proteinTotalG = proteinTotalG
        self.proteinTargetG = proteinTargetG
    }
}

public struct ReportsDashboardSource: Equatable, Sendable {
    public let coverage: ReportCoverage
    public let bodyMetricRecords: [ReportBodyMetricRecord]
    public let exerciseSetRecords: [ReportExerciseSetRecord]
    public let nutritionDayRecords: [ReportNutritionDayRecord]

    public init(
        coverage: ReportCoverage = .empty,
        bodyMetricRecords: [ReportBodyMetricRecord] = [],
        exerciseSetRecords: [ReportExerciseSetRecord] = [],
        nutritionDayRecords: [ReportNutritionDayRecord] = []
    ) {
        self.coverage = coverage
        self.bodyMetricRecords = bodyMetricRecords
        self.exerciseSetRecords = exerciseSetRecords
        self.nutritionDayRecords = nutritionDayRecords
    }
}
