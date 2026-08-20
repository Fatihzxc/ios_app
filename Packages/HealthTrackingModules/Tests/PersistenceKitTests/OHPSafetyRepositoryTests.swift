import CoreModels
import Foundation
@testable import PersistenceKit
import SwiftData
import TrainingKit
import XCTest

@MainActor
final class OHPSafetyRepositoryTests: XCTestCase {
    func testSymptomResponsesWriteThePriorAndCurrentSessionsWithTheirOwnTimestamps() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let dayID = uuid("00000000-0000-0000-0000-000000000810")
        let priorID = uuid("00000000-0000-0000-0000-000000000811")
        let currentID = uuid("00000000-0000-0000-0000-000000000812")
        let originalDate = Date(timeIntervalSinceReferenceDate: 50_000)
        context.insert(
            WorkoutSession(
                id: priorID,
                createdAt: originalDate,
                updatedAt: originalDate,
                date: originalDate,
                status: .completed,
                workoutDayTemplateId: dayID,
                perceivedRecovery: 7,
                note: "Korunmalı"
            )
        )
        context.insert(
            WorkoutSession(
                id: currentID,
                createdAt: originalDate,
                updatedAt: originalDate,
                date: originalDate,
                status: .inProgress,
                workoutDayTemplateId: dayID
            )
        )
        try context.save()
        let repository: any TrainingRepository = SwiftDataTrainingRepository(
            modelContext: ModelContext(container)
        )
        let priorCheckedAt = originalDate.addingTimeInterval(60)
        let currentCheckedAt = originalDate.addingTimeInterval(120)

        let prior = try await repository.updateWorkoutSessionOHPSymptomResponse(
            id: priorID,
            response: .symptomFree,
            at: priorCheckedAt
        )
        let current = try await repository.updateWorkoutSessionOHPSymptomResponse(
            id: currentID,
            response: .symptomsPresent,
            at: currentCheckedAt
        )

        XCTAssertEqual(prior.status, .completed)
        XCTAssertEqual(prior.perceivedRecovery, 7)
        XCTAssertEqual(prior.note, "Korunmalı")
        XCTAssertEqual(prior.ohpSymptomResponse, .symptomFree)
        XCTAssertEqual(prior.ohpSymptomCheckedAt, priorCheckedAt)
        XCTAssertEqual(prior.updatedAt, priorCheckedAt)
        XCTAssertEqual(current.status, .inProgress)
        XCTAssertEqual(current.ohpSymptomResponse, .symptomsPresent)
        XCTAssertEqual(current.ohpSymptomCheckedAt, currentCheckedAt)
        XCTAssertEqual(current.updatedAt, currentCheckedAt)

        let persisted = try ModelContext(container).fetch(FetchDescriptor<WorkoutSession>())
        let persistedPrior = try XCTUnwrap(persisted.first { $0.id == priorID })
        let persistedCurrent = try XCTUnwrap(persisted.first { $0.id == currentID })
        XCTAssertEqual(persistedPrior.ohpSymptomResponse, .symptomFree)
        XCTAssertEqual(persistedPrior.ohpSymptomCheckedAt, priorCheckedAt)
        XCTAssertEqual(persistedCurrent.ohpSymptomResponse, .symptomsPresent)
        XCTAssertEqual(persistedCurrent.ohpSymptomCheckedAt, currentCheckedAt)
    }

    func testSeededHalfKneelingTemplateIsTheOHPAlternative() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writeContext = ModelContext(container)
        try SwiftDataSeedLoader(modelContext: writeContext).seedIfNeeded(
            installedAt: Date(timeIntervalSinceReferenceDate: 51_000)
        )
        let repository: any TrainingRepository = SwiftDataTrainingRepository(
            modelContext: ModelContext(container)
        )

        let alternative = try await repository.fetchOHPSafeAlternative()

        XCTAssertEqual(alternative.id, SeedIdentifiers.halfKneelingDBPress)
        XCTAssertEqual(alternative.name, "Half-Kneeling DB Press")
        XCTAssertEqual(alternative.progressionRule, .doubleProgression)
        XCTAssertEqual(alternative.measurementKind, .weightReps)
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
