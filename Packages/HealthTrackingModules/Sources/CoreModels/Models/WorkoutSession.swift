import Foundation
import SwiftData

@Model
public final class WorkoutSession {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var date: Date = Foundation.Date.now
    public var status: WorkoutSessionStatus = WorkoutSessionStatus.planned
    public var workoutDayTemplateId: UUID = UUID()
    public var perceivedRecovery: Int?
    public var note: String?
    public var ohpSymptomResponse: OHPSymptomResponse = OHPSymptomResponse.notAsked
    public var ohpSymptomCheckedAt: Date?
    @Relationship(deleteRule: .nullify, inverse: \SetLog.workoutSession)
    public var setLogs: [SetLog]? = nil

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, date: Date = .now,
        status: WorkoutSessionStatus = .planned, workoutDayTemplateId: UUID = UUID(),
        perceivedRecovery: Int? = nil, note: String? = nil,
        ohpSymptomResponse: OHPSymptomResponse = .notAsked, ohpSymptomCheckedAt: Date? = nil,
        setLogs: [SetLog]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.status = status
        self.workoutDayTemplateId = workoutDayTemplateId
        self.perceivedRecovery = perceivedRecovery
        self.note = note
        self.ohpSymptomResponse = ohpSymptomResponse
        self.ohpSymptomCheckedAt = ohpSymptomCheckedAt
        self.setLogs = setLogs
    }
}
