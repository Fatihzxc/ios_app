@testable import HealthTrackingApp
import CoreModels
import Foundation
import MetricsKit
import TrainingKit
import XCTest

@MainActor
final class SymptomJournalAdapterTests: XCTestCase {
    private let expectedGeneralMessage =
        "Hareketi durdur. Kalıcı veya kötüleşen belirtiler bir sağlık profesyoneli "
        + "tarafından değerlendirilmelidir. Yeni veya belirgin şekilde kötüleşen kol veya "
        + "bacakta güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede "
        + "değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi "
        + "değerlendirme gerektirir."

    func testTrainingSafetyMapperUsesTheCentralPermanentAndLevelTwoCopy() throws {
        let presentation = try XCTUnwrap(
            TrainingSymptomSafetyMapper.overheadPressSymptom()
        )

        XCTAssertEqual(
            presentation.disclaimer,
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
        )
        XCTAssertEqual(presentation.levelTwoMessage, expectedGeneralMessage)
        XCTAssertFalse(presentation.requiresUrgentAssessment)
    }

    // Mutation caught: adding a pure missing-answer trigger without mapping the
    // shipped session contexts would leave real .notAsked/.uncertain OHP history silent.
    func testStructuredMissingOHPSessionResponsesMapToCentralFailClosedPresentation() throws {
        for response in [OHPSymptomResponse.notAsked, .uncertain] {
            let presentation = try XCTUnwrap(
                TrainingSymptomSafetyMapper.presentation(
                    for: .priorOverheadPressResponse(response)
                )
            )

            XCTAssertEqual(
                presentation.disclaimer,
                "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
            )
            XCTAssertEqual(presentation.levelTwoMessage, expectedGeneralMessage)
            XCTAssertFalse(presentation.requiresUrgentAssessment)
        }

        XCTAssertNil(
            TrainingSymptomSafetyMapper.presentation(
                for: .priorOverheadPressResponse(.symptomFree)
            ),
            "A recorded symptom-free answer must not be reclassified as missing."
        )
    }

    // Mutation caught: leaving the AppDependencies factory on SessionViewModel's
    // nil default would make the real app composition discard the tested mapper.
    func testAppDependenciesComposesStructuredSafetyProviderIntoSessionViewModel() throws {
        let dependencies = try AppDependencies(environment: .uiTesting)
        let session = dependencies.makeSessionViewModel()

        for context in [
            TrainingSymptomSafetyContext.priorOverheadPressResponse(.notAsked),
            .priorOverheadPressResponse(.uncertain),
            .currentOverheadPressResponse(.symptomsPresent),
        ] {
            let presentation = try XCTUnwrap(
                session.resolveSymptomSafetyPresentation(for: context)
            )
            XCTAssertEqual(presentation.levelTwoMessage, expectedGeneralMessage)
            XCTAssertFalse(presentation.requiresUrgentAssessment)
        }

        XCTAssertNil(
            session.resolveSymptomSafetyPresentation(
                for: .priorOverheadPressResponse(.symptomFree)
            )
        )
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
