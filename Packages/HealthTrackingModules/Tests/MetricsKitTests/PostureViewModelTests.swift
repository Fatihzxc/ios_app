import Foundation
import HealthSafetyKit
@testable import MetricsKit
import XCTest

@MainActor
final class PostureViewModelTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testFailedSavePreservesEveryFieldAndRetryUsesTheExactInput() async {
        let saved = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000421"),
            score: 6
        )
        let repository = PostureRepositoryStub(
            createResults: [.failure(FixtureFailure.save), .success(saved)]
        )
        let requestID = uuid("00000000-0000-4000-8000-000000000422")
        let viewModel = PostureViewModel(
            repository: repository,
            makeRequestID: { requestID }
        )
        let date = Date(timeIntervalSinceReferenceDate: 12_000)
        viewModel.wallTestPass = false
        viewModel.symptomScore = 6
        viewModel.region = "  Boyun  "
        viewModel.note = "  OHP sonrası  "

        await viewModel.save(date: date)

        XCTAssertEqual(viewModel.wallTestPass, false)
        XCTAssertEqual(viewModel.symptomScore, 6)
        XCTAssertEqual(viewModel.region, "  Boyun  ")
        XCTAssertEqual(viewModel.note, "  OHP sonrası  ")
        XCTAssertEqual(viewModel.savePhase, .failed(requestID: requestID))
        XCTAssertEqual(repository.createdInputs.count, 1)

        await viewModel.retrySave()

        XCTAssertEqual(repository.createdInputs.count, 2)
        XCTAssertEqual(repository.createdInputs[0], repository.createdInputs[1])
        XCTAssertEqual(repository.createdInputs[1].date, date)
        XCTAssertEqual(repository.createdInputs[1].region, "Boyun")
        XCTAssertEqual(repository.createdInputs[1].note, "OHP sonrası")
        XCTAssertEqual(viewModel.snapshots, [saved])
        XCTAssertEqual(viewModel.savePhase, .saved(id: saved.id))
    }

    func testEmptyDraftFailsValidationWithoutCallingRepositoryAndKeepsL1Visible() async {
        let repository = PostureRepositoryStub()
        let viewModel = PostureViewModel(repository: repository)
        viewModel.region = "  "
        viewModel.note = "\n"

        await viewModel.save(date: Date(timeIntervalSinceReferenceDate: 12_050))

        XCTAssertEqual(viewModel.validationIssue?.id, "posture.validation.empty")
        XCTAssertTrue(repository.createdInputs.isEmpty)
        XCTAssertEqual(
            viewModel.safetyPresentation.disclaimer.text,
            "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
        )
        XCTAssertTrue(
            viewModel.safetyPresentation.disclaimer.isAlwaysVisible
        )
    }

    func testSecondTapWhileSavingCannotReplaceTheRetryPayload() async {
        let repository = PostureRepositoryStub(suspendsFirstCreate: true)
        let viewModel = PostureViewModel(repository: repository)
        let originalDate = Date(timeIntervalSinceReferenceDate: 12_100)
        viewModel.symptomScore = 4
        viewModel.region = "Boyun"

        let firstSave = Task { await viewModel.save(date: originalDate) }
        for _ in 0..<20 {
            if repository.hasSuspendedCreate { break }
            await Task.yield()
        }
        XCTAssertTrue(repository.hasSuspendedCreate)

        viewModel.symptomScore = 9
        viewModel.region = "Sağ kol"
        await viewModel.save(date: originalDate.addingTimeInterval(60))

        XCTAssertEqual(repository.createdInputs.count, 1)
        repository.completeSuspendedCreate(with: .failure(FixtureFailure.save))
        await firstSave.value
        repository.createResults = [
            .success(
                snapshot(
                    id: uuid("00000000-0000-4000-8000-000000000423"),
                    score: 4
                )
            ),
        ]

        await viewModel.retrySave()

        XCTAssertEqual(repository.createdInputs.count, 2)
        XCTAssertEqual(repository.createdInputs[0], repository.createdInputs[1])
        XCTAssertEqual(repository.createdInputs[1].symptomScore, 4)
        XCTAssertEqual(repository.createdInputs[1].region, "Boyun")
        XCTAssertEqual(repository.createdInputs[1].date, originalDate)
    }

    // Mutation caught: treating an unanswered current symptom as benign would
    // suppress the required fail-closed stop notice after a prior explicit score.
    func testLoadOrdersHistoryAndMissingCurrentSymptomFailsClosed() async throws {
        let noScore = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000424"),
            score: nil,
            date: 13_000
        )
        let explicit = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000425"),
            score: 3,
            date: 12_000
        )
        let repository = PostureRepositoryStub(fetched: [explicit, noScore])
        let viewModel = PostureViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.snapshots.map(\.id), [noScore.id, explicit.id])
        XCTAssertEqual(viewModel.loadPhase, .loaded)
        let missingAnswerNotice = try XCTUnwrap(viewModel.safetyPresentation.levelTwo)
        XCTAssertEqual(missingAnswerNotice.kind, .stopAndProfessionalAssessment)
        XCTAssertTrue(missingAnswerNotice.message.hasPrefix("Hareketi durdur."))
        XCTAssertTrue(missingAnswerNotice.message.contains("kalıcı veya kötüleşen"))
        XCTAssertTrue(missingAnswerNotice.message.contains("sağlık profesyoneli"))
        XCTAssertTrue(
            missingAnswerNotice.message.contains("kol veya bacakta güçsüzlük ya da uyuşma")
        )
        XCTAssertFalse(missingAnswerNotice.requiresUrgentAssessment)

        viewModel.symptomScore = 5
        viewModel.refreshSafetyPresentation()

        XCTAssertEqual(
            viewModel.safetyPresentation.levelTwo?.kind,
            .stopAndProfessionalAssessment
        )
        XCTAssertEqual(viewModel.previousExplicitSymptomScore, 3)
    }

    func testUpdateAndDeleteUseTheImmutableExpectedTimestamp() async throws {
        let original = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000426"),
            score: 2,
            updatedAt: 10_000
        )
        let updated = snapshot(
            id: original.id,
            score: 1,
            updatedAt: 11_000
        )
        let repository = PostureRepositoryStub(
            fetched: [original],
            updateResult: .success(updated)
        )
        let viewModel = PostureViewModel(repository: repository)
        await viewModel.load()
        let input = try PostureMetricInput(
            date: updated.date,
            wallTestPass: true,
            symptomScore: 1,
            region: "Boyun",
            note: nil
        )

        await viewModel.update(original, with: input)

        XCTAssertEqual(repository.updatedRequests.first?.id, original.id)
        XCTAssertEqual(
            repository.updatedRequests.first?.expectedUpdatedAt,
            original.updatedAt
        )
        XCTAssertEqual(viewModel.snapshots, [updated])

        await viewModel.delete(updated)

        XCTAssertEqual(
            repository.deletedRequests,
            [.init(id: updated.id, expectedUpdatedAt: updated.updatedAt)]
        )
        XCTAssertTrue(viewModel.snapshots.isEmpty)
    }

    private func snapshot(
        id: UUID,
        score: Int?,
        date: TimeInterval = 12_000,
        updatedAt: TimeInterval = 12_500
    ) -> PostureMetricSnapshot {
        PostureMetricSnapshot(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 11_000),
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt),
            date: Date(timeIntervalSinceReferenceDate: date),
            wallTestPass: false,
            symptomScore: score,
            region: "Boyun",
            note: "Takip"
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

@MainActor
private final class PostureRepositoryStub: MetricsRepository {
    struct UpdateRequest: Equatable {
        let id: UUID
        let expectedUpdatedAt: Date
        let input: PostureMetricInput
    }

    struct DeleteRequest: Equatable {
        let id: UUID
        let expectedUpdatedAt: Date
    }

    var fetched: [PostureMetricSnapshot]
    var createResults: [Result<PostureMetricSnapshot, Error>]
    var updateResult: Result<PostureMetricSnapshot, Error>?
    private(set) var createdInputs: [PostureMetricInput] = []
    private(set) var updatedRequests: [UpdateRequest] = []
    private(set) var deletedRequests: [DeleteRequest] = []
    private(set) var hasSuspendedCreate = false
    private var suspendsFirstCreate: Bool
    private var createContinuation: CheckedContinuation<PostureMetricSnapshot, Error>?

    init(
        fetched: [PostureMetricSnapshot] = [],
        createResults: [Result<PostureMetricSnapshot, Error>] = [],
        updateResult: Result<PostureMetricSnapshot, Error>? = nil,
        suspendsFirstCreate: Bool = false
    ) {
        self.fetched = fetched
        self.createResults = createResults
        self.updateResult = updateResult
        self.suspendsFirstCreate = suspendsFirstCreate
    }

    func fetchPostureMetrics() async throws -> [PostureMetricSnapshot] {
        fetched
    }

    func createPostureMetric(
        _ input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        createdInputs.append(input)
        if suspendsFirstCreate {
            suspendsFirstCreate = false
            return try await withCheckedThrowingContinuation { continuation in
                hasSuspendedCreate = true
                createContinuation = continuation
            }
        }
        guard !createResults.isEmpty else { throw StubFailure.missingResult }
        return try createResults.removeFirst().get()
    }

    func completeSuspendedCreate(
        with result: Result<PostureMetricSnapshot, Error>
    ) {
        guard let createContinuation else {
            preconditionFailure("No suspended posture create request.")
        }
        self.createContinuation = nil
        createContinuation.resume(with: result)
    }

    func updatePostureMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        updatedRequests.append(
            .init(id: id, expectedUpdatedAt: expectedUpdatedAt, input: input)
        )
        guard let updateResult else { throw StubFailure.missingResult }
        return try updateResult.get()
    }

    func deletePostureMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        deletedRequests.append(.init(id: id, expectedUpdatedAt: expectedUpdatedAt))
    }

    func upsertPostureMetric(
        id: UUID,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
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
        case missingResult
        case unexpectedCall
    }
}
