import CoreModels
import Foundation

public enum SymptomJournalSource: Equatable, Sendable {
    case overheadPressCurrentSymptom
}

public struct SymptomJournalEvent: Equatable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let source: SymptomJournalSource

    public init(id: UUID, occurredAt: Date, source: SymptomJournalSource) {
        self.id = id
        self.occurredAt = occurredAt
        self.source = source
    }
}

@MainActor
public protocol SymptomEventClient: AnyObject {
    func record(_ event: SymptomJournalEvent) async throws
}

@MainActor
public final class NoOpSymptomEventClient: SymptomEventClient {
    public static let shared = NoOpSymptomEventClient()

    private init() {}

    public func record(_ event: SymptomJournalEvent) async throws {}
}

public enum SymptomJournalState: Equatable, Sendable {
    case idle
    case recording(event: SymptomJournalEvent)
    case recorded(event: SymptomJournalEvent)
    case failed(event: SymptomJournalEvent)
}

public struct TrainingSymptomSafetyPresentation: Equatable, Sendable {
    public let disclaimer: String
    public let levelTwoMessage: String
    public let requiresUrgentAssessment: Bool

    public init(
        disclaimer: String,
        levelTwoMessage: String,
        requiresUrgentAssessment: Bool
    ) {
        self.disclaimer = disclaimer
        self.levelTwoMessage = levelTwoMessage
        self.requiresUrgentAssessment = requiresUrgentAssessment
    }
}

public enum TrainingSymptomSafetyContext: Equatable, Sendable {
    case priorOverheadPressResponse(OHPSymptomResponse)
    case currentOverheadPressResponse(OHPSymptomResponse)
}
