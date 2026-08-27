import Foundation
import HealthSafetyKit
import MetricsKit
import PersistenceKit
import SwiftData
import TrainingKit

@MainActor
final class TrainingSymptomMetricsAdapter: SymptomEventClient {
    private let repository: any MetricsRepository

    init(repository: any MetricsRepository) {
        self.repository = repository
    }

    func record(_ event: SymptomJournalEvent) async throws {
        let region: String
        switch event.source {
        case .overheadPressCurrentSymptom:
            region = "OHP"
        }
        let input = try PostureMetricInput(
            date: event.occurredAt,
            wallTestPass: nil,
            symptomScore: nil,
            region: region,
            note: nil
        )
        _ = try await repository.upsertPostureMetric(id: event.id, input: input)
    }
}

enum TrainingSymptomSafetyMapper {
    static func overheadPressSymptom() -> TrainingSymptomSafetyPresentation? {
        presentation(for: .currentOverheadPressResponse(.symptomsPresent))
    }

    static func presentation(
        for context: TrainingSymptomSafetyContext
    ) -> TrainingSymptomSafetyPresentation? {
        let trigger: MedicalSafetyTrigger
        switch context {
        case .priorOverheadPressResponse(.notAsked),
             .priorOverheadPressResponse(.uncertain):
            trigger = .missingSymptomAnswer
        case .priorOverheadPressResponse(.symptomsPresent),
             .currentOverheadPressResponse(.symptomsPresent):
            trigger = .overheadPressSymptom
        case .priorOverheadPressResponse(.symptomFree),
             .currentOverheadPressResponse(.notAsked),
             .currentOverheadPressResponse(.symptomFree),
             .currentOverheadPressResponse(.uncertain):
            return nil
        }

        let central = MedicalSafetyPresentation.resolve(
            triggers: [trigger]
        )
        guard let levelTwo = central.levelTwo else { return nil }
        return TrainingSymptomSafetyPresentation(
            disclaimer: central.disclaimer.text,
            levelTwoMessage: levelTwo.message,
            requiresUrgentAssessment: levelTwo.requiresUrgentAssessment
        )
    }
}

@MainActor
enum DefaultTrainingSymptomEventFactory {
    static func make(modelContext: ModelContext) -> any SymptomEventClient {
        TrainingSymptomMetricsAdapter(
            repository: SwiftDataMetricsRepository(modelContext: modelContext)
        )
    }
}
