import Foundation
import HealthChecksKit
import XCTest

@MainActor
final class BloodworkViewModelTests: XCTestCase {
    func testLoadPublishesStableNewestFirstSnapshots() async throws {
        let older = try makeSnapshot(idSuffix: 2, date: 100)
        let newer = try makeSnapshot(idSuffix: 1, date: 200)
        let repository = BloodworkRepositoryFake(results: [older, newer])
        let viewModel = BloodworkViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.loadPhase, .loaded)
        XCTAssertEqual(viewModel.snapshots.map(\.id), [newer.id, older.id])
    }

    func testFailedCreateKeepsExactInputForRetryThenUndoRemovesCommittedSnapshot() async throws {
        let input = try makeInput(marker: "Ferritin", value: 19)
        let snapshot = try makeSnapshot(idSuffix: 1, date: input.date.timeIntervalSince1970)
        let token = BloodworkCreationUndoToken(
            id: snapshot.id,
            expectedUpdatedAt: snapshot.updatedAt
        )
        let repository = BloodworkRepositoryFake(
            createResults: [
                .failure(.saveFailed),
                .success(
                    BloodworkCreationMutation(snapshot: snapshot, undoToken: token)
                ),
            ]
        )
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let viewModel = BloodworkViewModel(
            repository: repository,
            makeRequestID: { requestID }
        )

        XCTAssertFalse(await viewModel.create(input))
        guard case .saveFailed = viewModel.mutationPhase else {
            return XCTFail("The failed input must remain retryable.")
        }
        XCTAssertEqual(repository.createRequests, [input])

        XCTAssertTrue(await viewModel.retryCreate())
        guard case let .saved(savedToken) = viewModel.mutationPhase else {
            return XCTFail("The exact retry must publish its undo token.")
        }
        XCTAssertEqual(savedToken, token)
        XCTAssertEqual(repository.createRequests, [input, input])
        XCTAssertEqual(viewModel.snapshots, [snapshot])

        XCTAssertTrue(await viewModel.undoLastCreate())
        XCTAssertEqual(repository.undoRequests, [token])
        XCTAssertTrue(viewModel.snapshots.isEmpty)
        XCTAssertEqual(viewModel.mutationPhase, .idle)
    }

    func testSecondCreateWhileSavingCannotReplacePendingRetryInput() async throws {
        let first = try makeInput(marker: "Ferritin", value: 21)
        let second = try makeInput(marker: "D vitamini", value: 22)
        let repository = SuspendingBloodworkRepository()
        let viewModel = BloodworkViewModel(repository: repository)

        let firstTask = Task { await viewModel.create(first) }
        await repository.waitForCreateRequestCount(1)
        XCTAssertFalse(await viewModel.create(second))
        repository.resumeCreate(with: .failure(.saveFailed))
        XCTAssertFalse(await firstTask.value)

        guard case .saveFailed = viewModel.mutationPhase else {
            return XCTFail("The first request must remain the failed retry payload.")
        }
        repository.resumeImmediately = true
        XCTAssertFalse(await viewModel.retryCreate())
        XCTAssertEqual(repository.createRequests, [first, first])
    }

    func testUpdateAndDeleteUseExactExpectedTimestampAndKeepSnapshotOnFailure() async throws {
        let original = try makeSnapshot(idSuffix: 1, date: 100)
        let editedInput = try makeInput(marker: "Ferritin", value: 31)
        let repository = BloodworkRepositoryFake(
            results: [original],
            updateResults: [.failure(.saveFailed)],
            deleteResults: [.failure(.saveFailed)]
        )
        let viewModel = BloodworkViewModel(repository: repository)
        await viewModel.load()

        XCTAssertFalse(await viewModel.update(original, input: editedInput))
        XCTAssertEqual(
            repository.updateRequests,
            [.init(id: original.id, expectedUpdatedAt: original.updatedAt, input: editedInput)]
        )
        XCTAssertEqual(viewModel.snapshots, [original])

        XCTAssertFalse(await viewModel.delete(original))
        XCTAssertEqual(
            repository.deleteRequests,
            [.init(id: original.id, expectedUpdatedAt: original.updatedAt)]
        )
        XCTAssertEqual(viewModel.snapshots, [original])
    }

    private func makeInput(
        marker: String,
        value: Double
    ) throws -> BloodworkResultInput {
        try BloodworkResultInput(
            date: Date(timeIntervalSince1970: 200),
            marker: marker,
            value: value,
            unit: "ng/mL",
            note: "Referans kaydı"
        )
    }

    private func makeSnapshot(
        idSuffix: Int,
        date: TimeInterval
    ) throws -> BloodworkResultSnapshot {
        let id = UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                idSuffix
            )
        )!
        let timestamp = Date(timeIntervalSince1970: date)
        return BloodworkResultSnapshot(
            id: id,
            createdAt: timestamp,
            updatedAt: timestamp,
            date: timestamp,
            marker: "Ferritin",
            value: 20,
            unit: "ng/mL",
            note: nil
        )
    }
}

@MainActor
private final class BloodworkRepositoryFake: BloodworkRepository {
    struct UpdateRequest: Equatable {
        let id: UUID
        let expectedUpdatedAt: Date
        let input: BloodworkResultInput
    }

    struct DeleteRequest: Equatable {
        let id: UUID
        let expectedUpdatedAt: Date
    }

    var results: [BloodworkResultSnapshot]
    var createResults: [Result<BloodworkCreationMutation, BloodworkRepositoryOperationError>]
    var updateResults: [Result<BloodworkResultSnapshot, BloodworkRepositoryOperationError>]
    var deleteResults: [Result<Void, BloodworkRepositoryOperationError>]
    private(set) var createRequests: [BloodworkResultInput] = []
    private(set) var updateRequests: [UpdateRequest] = []
    private(set) var deleteRequests: [DeleteRequest] = []
    private(set) var undoRequests: [BloodworkCreationUndoToken] = []

    init(
        results: [BloodworkResultSnapshot] = [],
        createResults: [Result<BloodworkCreationMutation, BloodworkRepositoryOperationError>] = [],
        updateResults: [Result<BloodworkResultSnapshot, BloodworkRepositoryOperationError>] = [],
        deleteResults: [Result<Void, BloodworkRepositoryOperationError>] = []
    ) {
        self.results = results
        self.createResults = createResults
        self.updateResults = updateResults
        self.deleteResults = deleteResults
    }

    func fetchResults() async throws -> [BloodworkResultSnapshot] {
        results
    }

    func createResult(
        _ input: BloodworkResultInput
    ) async throws -> BloodworkCreationMutation {
        createRequests.append(input)
        guard !createResults.isEmpty else {
            throw BloodworkRepositoryOperationError.saveFailed
        }
        return try createResults.removeFirst().get()
    }

    func updateResult(
        id: UUID,
        expectedUpdatedAt: Date,
        input: BloodworkResultInput
    ) async throws -> BloodworkResultSnapshot {
        updateRequests.append(
            .init(id: id, expectedUpdatedAt: expectedUpdatedAt, input: input)
        )
        guard !updateResults.isEmpty else {
            throw BloodworkRepositoryOperationError.saveFailed
        }
        return try updateResults.removeFirst().get()
    }

    func deleteResult(id: UUID, expectedUpdatedAt: Date) async throws {
        deleteRequests.append(.init(id: id, expectedUpdatedAt: expectedUpdatedAt))
        guard !deleteResults.isEmpty else {
            throw BloodworkRepositoryOperationError.saveFailed
        }
        try deleteResults.removeFirst().get()
    }

    func undoResultCreation(_ token: BloodworkCreationUndoToken) async throws {
        undoRequests.append(token)
    }
}

@MainActor
private final class SuspendingBloodworkRepository: BloodworkRepository {
    var resumeImmediately = false
    private(set) var createRequests: [BloodworkResultInput] = []
    private var continuation:
        CheckedContinuation<BloodworkCreationMutation, Error>?

    func fetchResults() async throws -> [BloodworkResultSnapshot] { [] }

    func createResult(
        _ input: BloodworkResultInput
    ) async throws -> BloodworkCreationMutation {
        createRequests.append(input)
        if resumeImmediately {
            throw BloodworkRepositoryOperationError.saveFailed
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func updateResult(
        id: UUID,
        expectedUpdatedAt: Date,
        input: BloodworkResultInput
    ) async throws -> BloodworkResultSnapshot {
        throw BloodworkRepositoryOperationError.saveFailed
    }

    func deleteResult(id: UUID, expectedUpdatedAt: Date) async throws {
        throw BloodworkRepositoryOperationError.saveFailed
    }

    func undoResultCreation(_ token: BloodworkCreationUndoToken) async throws {
        throw BloodworkRepositoryOperationError.saveFailed
    }

    func waitForCreateRequestCount(_ count: Int) async {
        while createRequests.count < count {
            await Task.yield()
        }
    }

    func resumeCreate(
        with result: Result<BloodworkCreationMutation, BloodworkRepositoryOperationError>
    ) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result.mapError { $0 as Error })
    }
}
