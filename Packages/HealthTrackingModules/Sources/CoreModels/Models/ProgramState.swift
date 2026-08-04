import Foundation
import SwiftData

@Model
public final class ProgramState {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var programId: UUID = UUID()
    public var currentPhaseId: UUID = UUID()
    public var phaseStartedAt: Date = Foundation.Date.now
    public var trainingWeekIndex: Int = 1
    public var deloadStatus: DeloadStatus = DeloadStatus.none
    public var deloadReason: DeloadReason?
    public var deloadUpdatedAt: Date?
    public var lastDeloadSkippedAt: Date?
    public var lastDeloadAction: DeloadAction?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        programId: UUID = UUID(), currentPhaseId: UUID = UUID(), phaseStartedAt: Date = .now,
        trainingWeekIndex: Int = 1, deloadStatus: DeloadStatus = .none,
        deloadReason: DeloadReason? = nil, deloadUpdatedAt: Date? = nil,
        lastDeloadSkippedAt: Date? = nil, lastDeloadAction: DeloadAction? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.programId = programId
        self.currentPhaseId = currentPhaseId
        self.phaseStartedAt = phaseStartedAt
        self.trainingWeekIndex = trainingWeekIndex
        self.deloadStatus = deloadStatus
        self.deloadReason = deloadReason
        self.deloadUpdatedAt = deloadUpdatedAt
        self.lastDeloadSkippedAt = lastDeloadSkippedAt
        self.lastDeloadAction = lastDeloadAction
    }
}
