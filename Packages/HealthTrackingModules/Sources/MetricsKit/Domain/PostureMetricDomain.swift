import Foundation
import HealthSafetyKit

public enum PostureMetricInputError: Error, Equatable, Sendable {
    case empty
    case invalidSymptomScore(Int)
}

public struct PostureMetricInput: Equatable, Sendable {
    public let date: Date
    public let wallTestPass: Bool?
    public let symptomScore: Int?
    public let region: String?
    public let note: String?

    public init(
        date: Date,
        wallTestPass: Bool?,
        symptomScore: Int?,
        region: String?,
        note: String?
    ) throws {
        if let symptomScore, !(0...10).contains(symptomScore) {
            throw PostureMetricInputError.invalidSymptomScore(symptomScore)
        }

        let normalizedRegion = Self.normalized(region)
        let normalizedNote = Self.normalized(note)
        guard wallTestPass != nil
            || symptomScore != nil
            || normalizedRegion != nil
            || normalizedNote != nil else {
            throw PostureMetricInputError.empty
        }

        self.date = date
        self.wallTestPass = wallTestPass
        self.symptomScore = symptomScore
        self.region = normalizedRegion
        self.note = normalizedNote
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct PostureMetricSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let date: Date
    public let wallTestPass: Bool?
    public let symptomScore: Int?
    public let region: String?
    public let note: String?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        date: Date,
        wallTestPass: Bool?,
        symptomScore: Int?,
        region: String?,
        note: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.wallTestPass = wallTestPass
        self.symptomScore = symptomScore
        self.region = region
        self.note = note
    }
}

public enum PostureMetricOrdering {
    public static func newestFirst(
        _ lhs: PostureMetricSnapshot,
        _ rhs: PostureMetricSnapshot
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public enum PostureSymptomTrend: Equatable, Sendable {
    case increased(by: Int)
    case unchanged
    case decreased(by: Int)

    public static func compare(
        current: Int?,
        previous: Int?
    ) -> PostureSymptomTrend? {
        guard let current, let previous else { return nil }
        if current > previous { return .increased(by: current - previous) }
        if current < previous { return .decreased(by: previous - current) }
        return .unchanged
    }

    public var safetyTrigger: MedicalSafetyTrigger? {
        guard case .increased = self else { return nil }
        return .increasingSymptom
    }
}
