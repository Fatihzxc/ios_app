@testable import HealthTrackingApp
import Foundation
import MetricsKit
import TrainingKit
import XCTest

@MainActor
final class SymptomJournalAdapterTests: XCTestCase {
    func testTrainingSafetyMapperUsesTheCentralPermanentAndLevelTwoCopy() throws {
        let presentation = try XCTUnwrap(
            TrainingSymptomSafetyMapper.overheadPressSymptom()
        )

        XCTAssertEqual(
            presentation.disclaimer,
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
        )
        XCTAssertTrue(presentation.levelTwoMessage.hasPrefix("Hareketi durdur."))
        XCTAssertTrue(presentation.levelTwoMessage.contains("sağlık profesyoneli"))
        XCTAssertFalse(presentation.requiresUrgentAssessment)
    }

    func testAdapterMapsStableTrainingEventIntoAnIdempotentMetricsUpsert() async throws {
        let repository = SymptomMetricsRepositorySpy()
        let adapter = TrainingSymptomMetricsAdapter(repository: repository)
        let event = SymptomJournalEvent(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000461")!,
            occurredAt: Date(timeIntervalSinceReferenceDate: 30_000),
            source: .overheadPressCurrentSymptom
        )

        try await adapter.record(event)
        try await adapter.record(event)

        XCTAssertEqual(repository.upserts.count, 2)
        XCTAssertEqual(repository.upserts[0], repository.upserts[1])
        XCTAssertEqual(repository.upserts[0].id, event.id)
        XCTAssertEqual(repository.upserts[0].input.date, event.occurredAt)
        XCTAssertNil(repository.upserts[0].input.wallTestPass)
        XCTAssertNil(repository.upserts[0].input.symptomScore)
        XCTAssertEqual(repository.upserts[0].input.region, "OHP")
        XCTAssertNil(repository.upserts[0].input.note)
    }
}

@MainActor
private final class SymptomMetricsRepositorySpy: MetricsRepository {
    struct Upsert: Equatable {
        let id: UUID
        let input: PostureMetricInput
    }

    private(set) var upserts: [Upsert] = []

    func upsertPostureMetric(
        id: UUID,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        upserts.append(.init(id: id, input: input))
        return PostureMetricSnapshot(
            id: id,
            createdAt: input.date,
            updatedAt: input.date,
            date: input.date,
            wallTestPass: input.wallTestPass,
            symptomScore: input.symptomScore,
            region: input.region,
            note: input.note
        )
    }

    func fetchPostureMetrics() async throws -> [PostureMetricSnapshot] { [] }

    func createPostureMetric(
        _ input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedCall
    }

    func updatePostureMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedCall
    }

    func deletePostureMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        throw StubFailure.unexpectedCall
    }

    func fetchBodyMetrics() async throws -> [BodyMetricSnapshot] { [] }

    func createBodyMetrics(
        _ input: BodyMetricBatchInput
    ) async throws -> BodyMetricCreationMutation {
        throw StubFailure.unexpectedCall
    }

    func updateBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        date: Date,
        value: BodyMetricValueInput
    ) async throws -> BodyMetricSnapshot {
        throw StubFailure.unexpectedCall
    }

    func deleteBodyMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        throw StubFailure.unexpectedCall
    }

    func undoBodyMetricCreation(_ token: BodyMetricCreationUndoToken) async throws {
        throw StubFailure.unexpectedCall
    }

    private enum StubFailure: Error {
        case unexpectedCall
    }
}
