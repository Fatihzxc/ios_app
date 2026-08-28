import CoreModels
import Foundation
@testable import MetricsKit
import XCTest

@MainActor
final class BodyMetricViewModelTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testFailedBatchSavePreservesBothInputsAndRetryUsesTheSameRequest() async throws {
        let saved = [
            snapshot(id: uuid("00000000-0000-4000-8000-000000000371"), type: .weight),
            snapshot(id: uuid("00000000-0000-4000-8000-000000000372"), type: .waist),
        ]
        let token = BodyMetricCreationUndoToken(ids: saved.map(\.id))
        let repository = MetricsRepositoryStub(
            createResults: [
                .failure(FixtureFailure.save),
                .success(BodyMetricCreationMutation(snapshots: saved, undoToken: token)),
            ]
        )
        let requestID = uuid("00000000-0000-4000-8000-000000000373")
        let viewModel = BodyMetricViewModel(
            repository: repository,
            makeRequestID: { requestID }
        )
        let entryDate = Date(timeIntervalSinceReferenceDate: 4_000)
        viewModel.weightKilograms = 82
        viewModel.waistCentimeters = 91

        await viewModel.save(date: entryDate)

        XCTAssertEqual(viewModel.weightKilograms, 82)
        XCTAssertEqual(viewModel.waistCentimeters, 91)
        XCTAssertEqual(viewModel.mutationPhase, .saveFailed(requestID: requestID))
        XCTAssertEqual(repository.createdInputs.count, 1)
        XCTAssertEqual(repository.createdInputs.first?.values.map(\.type), [.weight, .waist])

        await viewModel.retrySave()

        XCTAssertEqual(repository.createdInputs.count, 2)
        XCTAssertEqual(repository.createdInputs[0], repository.createdInputs[1])
        XCTAssertEqual(viewModel.weightKilograms, 82)
        XCTAssertEqual(viewModel.waistCentimeters, 91)
        XCTAssertEqual(viewModel.snapshots, saved)
        XCTAssertEqual(viewModel.mutationPhase, .saved(undoToken: token))
    }

    func testDuplicateSaveWhileInFlightCannotReplaceThePendingRetryBatch() async throws {
        let saved = [
            snapshot(id: uuid("00000000-0000-4000-8000-000000000374"), type: .weight)
        ]
        let token = BodyMetricCreationUndoToken(ids: saved.map(\.id))
        let repository = MetricsRepositoryStub(
            createResults: [
                .success(BodyMetricCreationMutation(snapshots: saved, undoToken: token))
            ],
            suspendsFirstCreate: true
        )
        let viewModel = BodyMetricViewModel(repository: repository)
        let originalDate = Date(timeIntervalSinceReferenceDate: 4_100)
        viewModel.weightKilograms = 82

        let originalSave = Task {
            await viewModel.save(date: originalDate)
        }
        for _ in 0..<20 {
            if repository.hasSuspendedCreate { break }
            await Task.yield()
        }
        XCTAssertTrue(repository.hasSuspendedCreate)
        XCTAssertEqual(repository.createdInputs.count, 1)

        viewModel.weightKilograms = 99
        viewModel.waistCentimeters = 105
        await viewModel.save(date: originalDate.addingTimeInterval(60))

        XCTAssertEqual(repository.createdInputs.count, 1)
        repository.completeSuspendedCreate(with: .failure(FixtureFailure.save))
        await originalSave.value

        await viewModel.retrySave()

        XCTAssertEqual(repository.createdInputs.count, 2)
        XCTAssertEqual(repository.createdInputs[0], repository.createdInputs[1])
        XCTAssertEqual(repository.createdInputs[1].date, originalDate)
        XCTAssertEqual(repository.createdInputs[1].values.map(\.value), [82])
    }

    func testUndoTargetsOnlySuccessfulBatch() async throws {
        let saved = [
            snapshot(id: uuid("00000000-0000-4000-8000-000000000381"), type: .weight)
        ]
        let token = BodyMetricCreationUndoToken(ids: saved.map(\.id))
        let repository = MetricsRepositoryStub(
            createResults: [
                .success(BodyMetricCreationMutation(snapshots: saved, undoToken: token))
            ]
        )
        var requestIDs = [
            uuid("00000000-0000-4000-8000-000000000382"),
            uuid("00000000-0000-4000-8000-000000000383"),
        ]
        let viewModel = BodyMetricViewModel(
            repository: repository,
            makeRequestID: { requestIDs.removeFirst() }
        )
        viewModel.weightKilograms = 82

        await viewModel.save(date: Date(timeIntervalSinceReferenceDate: 4_000))

        XCTAssertEqual(repository.createdInputs.count, 1)
        XCTAssertEqual(viewModel.mutationPhase, .saved(undoToken: token))

        await viewModel.undoLastSave()

        XCTAssertEqual(repository.undoneTokens, [token])
        XCTAssertEqual(viewModel.mutationPhase, .idle)
        XCTAssertTrue(viewModel.snapshots.isEmpty)
    }

    func testRetryFailedMutationRetriesUndoInsteadOfCreatingAnotherBatch() async throws {
        let saved = [
            snapshot(id: uuid("00000000-0000-4000-8000-000000000384"), type: .weight)
        ]
        let token = BodyMetricCreationUndoToken(ids: saved.map(\.id))
        let repository = MetricsRepositoryStub(
            createResults: [
                .success(BodyMetricCreationMutation(snapshots: saved, undoToken: token))
            ],
            undoResults: [
                .failure(FixtureFailure.save),
                .success(()),
            ]
        )
        let saveRequestID = uuid("00000000-0000-4000-8000-000000000385")
        let undoRequestID = uuid("00000000-0000-4000-8000-000000000386")
        var requestIDs = [saveRequestID, undoRequestID]
        let viewModel = BodyMetricViewModel(
            repository: repository,
            makeRequestID: { requestIDs.removeFirst() }
        )
        viewModel.weightKilograms = 82

        await viewModel.save(date: Date(timeIntervalSinceReferenceDate: 4_000))
        await viewModel.undoLastSave()

        XCTAssertEqual(
            viewModel.mutationPhase,
            .undoFailed(requestID: undoRequestID, undoToken: token)
        )
        XCTAssertEqual(repository.createdInputs.count, 1)
        XCTAssertEqual(repository.undoneTokens, [token])

        await viewModel.retryFailedMutation()

        XCTAssertEqual(repository.createdInputs.count, 1)
        XCTAssertEqual(repository.undoneTokens, [token, token])
        XCTAssertEqual(viewModel.mutationPhase, .idle)
        XCTAssertTrue(viewModel.snapshots.isEmpty)
    }

    func testPreparingAnotherCreationExpiresCompletedUndoAndClearsTheOldDraft() async throws {
        let saved = [
            snapshot(id: uuid("00000000-0000-4000-8000-000000000387"), type: .weight)
        ]
        let token = BodyMetricCreationUndoToken(ids: saved.map(\.id))
        let repository = MetricsRepositoryStub(
            createResults: [
                .success(BodyMetricCreationMutation(snapshots: saved, undoToken: token))
            ]
        )
        let viewModel = BodyMetricViewModel(repository: repository)
        viewModel.weightKilograms = 82
        viewModel.waistCentimeters = 91
        viewModel.setCustomMetric(try .custom(name: "Boyun", value: 39, unit: "cm"))

        await viewModel.save(date: Date(timeIntervalSinceReferenceDate: 4_000))
        XCTAssertEqual(viewModel.mutationPhase, .saved(undoToken: token))

        viewModel.prepareForCreation()

        XCTAssertEqual(viewModel.mutationPhase, .idle)
        XCTAssertNil(viewModel.weightKilograms)
        XCTAssertNil(viewModel.waistCentimeters)
        XCTAssertNil(viewModel.customMetric)
        XCTAssertEqual(viewModel.snapshots, saved)
    }

    func testLoadEditAndDeleteUseImmutableExpectedTimestamp() async throws {
        let original = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000391"),
            type: .weight,
            value: 80,
            updatedAt: Date(timeIntervalSinceReferenceDate: 3_000)
        )
        let updated = snapshot(
            id: original.id,
            type: .weight,
            value: 81,
            updatedAt: Date(timeIntervalSinceReferenceDate: 4_000)
        )
        let repository = MetricsRepositoryStub(
            fetched: [original],
            updated: updated
        )
        let viewModel = BodyMetricViewModel(repository: repository)

        await viewModel.load()
        XCTAssertEqual(viewModel.snapshots, [original])

        await viewModel.update(
            original,
            date: updated.date,
            value: try .weight(kilograms: 81)
        )
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
        type: BodyMetricType,
        value: Double = 80,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 3_000)
    ) -> BodyMetricSnapshot {
        BodyMetricSnapshot(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 2_000),
            updatedAt: updatedAt,
            date: Date(timeIntervalSinceReferenceDate: 1_000),
            type: type,
            customName: nil,
            value: value,
            unit: type == .weight ? "kg" : "cm"
        )
    }

    private func uuid(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID: \(value)")
        }
        return id
    }
}

@MainActor
private final class MetricsRepositoryStub: MetricsRepository {
    struct UpdateRequest: Equatable {
        let id: UUID
        let expectedUpdatedAt: Date
        let date: Date
        let value: BodyMetricValueInput
    }

    struct DeleteRequest: Equatable {
        let id: UUID
        let expectedUpdatedAt: Date
    }

    var fetched: [BodyMetricSnapshot]
    var createResults: [Result<BodyMetricCreationMutation, Error>]
    var undoResults: [Result<Void, Error>]
    var updated: BodyMetricSnapshot?
    private(set) var createdInputs: [BodyMetricBatchInput] = []
    private(set) var updatedRequests: [UpdateRequest] = []
    private(set) var deletedRequests: [DeleteRequest] = []
    private(set) var undoneTokens: [BodyMetricCreationUndoToken] = []
    private(set) var hasSuspendedCreate = false
    private var suspendsFirstCreate: Bool
    private var createContinuation:
        CheckedContinuation<BodyMetricCreationMutation, Error>?

    init(
        fetched: [BodyMetricSnapshot] = [],
        createResults: [Result<BodyMetricCreationMutation, Error>] = [],
        undoResults: [Result<Void, Error>] = [],
        updated: BodyMetricSnapshot? = nil,
        suspendsFirstCreate: Bool = false
    ) {
        self.fetched = fetched
        self.createResults = createResults
        self.undoResults = undoResults
        self.updated = updated
        self.suspendsFirstCreate = suspendsFirstCreate
    }

    func fetchPostureMetrics() async throws -> [PostureMetricSnapshot] { [] }

    func createPostureMetric(
        _ input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedPostureCall
    }

    func updatePostureMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedPostureCall
    }

    func deletePostureMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        throw StubFailure.unexpectedPostureCall
    }

    func upsertPostureMetric(
        id: UUID,
        input: PostureMetricInput
    ) async throws -> PostureMetricSnapshot {
        throw StubFailure.unexpectedPostureCall
    }

    func fetchBodyMetrics() async throws -> [BodyMetricSnapshot] {
        fetched
    }

    func createBodyMetrics(
        _ input: BodyMetricBatchInput
    ) async throws -> BodyMetricCreationMutation {
        createdInputs.append(input)
        if suspendsFirstCreate {
            suspendsFirstCreate = false
            return try await withCheckedThrowingContinuation { continuation in
                hasSuspendedCreate = true
                createContinuation = continuation
            }
        }
        guard !createResults.isEmpty else {
            throw StubFailure.missingCreateResult
        }
        return try createResults.removeFirst().get()
    }

    func completeSuspendedCreate(
        with result: Result<BodyMetricCreationMutation, Error>
    ) {
        guard let createContinuation else {
            preconditionFailure("No suspended create request to complete.")
        }
        self.createContinuation = nil
        createContinuation.resume(with: result)
    }

    func updateBodyMetric(
        id: UUID,
        expectedUpdatedAt: Date,
        date: Date,
        value: BodyMetricValueInput
    ) async throws -> BodyMetricSnapshot {
        updatedRequests.append(
            .init(
                id: id,
                expectedUpdatedAt: expectedUpdatedAt,
                date: date,
                value: value
            )
        )
        guard let updated else {
            throw StubFailure.missingUpdateResult
        }
        fetched = fetched.filter { $0.id != id } + [updated]
        return updated
    }

    func deleteBodyMetric(id: UUID, expectedUpdatedAt: Date) async throws {
        deletedRequests.append(.init(id: id, expectedUpdatedAt: expectedUpdatedAt))
        fetched.removeAll { $0.id == id }
    }

    func undoBodyMetricCreation(_ token: BodyMetricCreationUndoToken) async throws {
        undoneTokens.append(token)
        if !undoResults.isEmpty {
            try undoResults.removeFirst().get()
        }
        let ids = Set(token.ids)
        fetched.removeAll { ids.contains($0.id) }
    }

    private enum StubFailure: Error {
        case missingCreateResult
        case missingUpdateResult
        case unexpectedPostureCall
    }
}
