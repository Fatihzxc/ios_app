import CoreModels
import Foundation
@testable import HealthChecksKit
import XCTest

@MainActor
final class HealthChecksViewModelTests: XCTestCase {
    func testFailedCompletionPreservesSnapshotAndRetryUsesExactRequestOnce() async {
        let original = snapshot(id: uuid(521), status: .pending, updatedAt: date(10_000))
        let completed = snapshot(id: original.id, status: .done, updatedAt: date(11_000))
        let successor = snapshot(
            id: uuid(522),
            status: .pending,
            updatedAt: date(11_000),
            dueDate: date(20_000)
        )
        let repository = HealthChecksRepositoryFake(
            reminders: [original],
            completionResults: [
                .failure(.saveFailed),
                .success(
                    HealthCheckCompletionMutation(
                        completed: completed,
                        successor: successor
                    )
                ),
            ]
        )
        let viewModel = HealthChecksViewModel(repository: repository)
        await viewModel.load()

        await viewModel.complete(original)

        XCTAssertEqual(viewModel.mutationPhase, .failed)
        XCTAssertEqual(viewModel.snapshots, [original])
        XCTAssertEqual(repository.completionRequests.count, 1)

        await viewModel.retryCompletion()

        XCTAssertEqual(viewModel.mutationPhase, .saved)
        XCTAssertEqual(
            repository.completionRequests,
            [
                .init(id: original.id, expectedUpdatedAt: original.updatedAt),
                .init(id: original.id, expectedUpdatedAt: original.updatedAt),
            ]
        )
        XCTAssertEqual(viewModel.snapshots.map(\.id), [completed.id, successor.id])
    }

    func testSecondCompletionTapWhileSavingCannotReplacePendingRetry() async {
        let first = snapshot(id: uuid(523), status: .pending, updatedAt: date(30_000))
        let second = snapshot(id: uuid(524), status: .pending, updatedAt: date(31_000))
        let repository = SuspendingHealthChecksRepository(reminders: [first, second])
        let viewModel = HealthChecksViewModel(repository: repository)
        await viewModel.load()

        let firstTask = Task { await viewModel.complete(first) }
        await repository.waitUntilCompletionStarts()
        await viewModel.complete(second)

        XCTAssertEqual(
            repository.completionRequests,
            [.init(id: first.id, expectedUpdatedAt: first.updatedAt)]
        )
        repository.finish(
            with: .failure(HealthChecksRepositoryOperationError.saveFailed)
        )
        await firstTask.value
        await viewModel.retryCompletion()

        XCTAssertEqual(
            repository.completionRequests,
            [
                .init(id: first.id, expectedUpdatedAt: first.updatedAt),
                .init(id: first.id, expectedUpdatedAt: first.updatedAt),
            ]
        )
    }

    private func snapshot(
        id: UUID,
        status: HealthCheckStatus,
        updatedAt: Date,
        dueDate: Date = Date(timeIntervalSinceReferenceDate: 15_000)
    ) -> HealthCheckReminderSnapshot {
        HealthCheckReminderSnapshot(
            id: id,
            createdAt: date(9_000),
            updatedAt: updatedAt,
            name: "Genel check-up",
            dueDate: dueDate,
            recurrence: .yearly,
            status: status
        )
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-4000-8000-%012d",
                suffix
            )
        )!
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: value)
    }
}

@MainActor
private final class HealthChecksRepositoryFake: HealthChecksRepository {
    struct CompletionRequest: Equatable {
        let id: UUID
        let expectedUpdatedAt: Date
    }

    var reminders: [HealthCheckReminderSnapshot]
    var completionResults: [
        Result<HealthCheckCompletionMutation, HealthChecksRepositoryOperationError>
    ]
    private(set) var completionRequests: [CompletionRequest] = []

    init(
        reminders: [HealthCheckReminderSnapshot],
        completionResults: [
            Result<HealthCheckCompletionMutation, HealthChecksRepositoryOperationError>
        ]
    ) {
        self.reminders = reminders
        self.completionResults = completionResults
    }

    func fetchReminders() async throws -> [HealthCheckReminderSnapshot] {
        reminders
    }

    func createReminder(
        _ input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        throw HealthChecksRepositoryOperationError.saveFailed
    }

    func updateReminder(
        id: UUID,
        expectedUpdatedAt: Date,
        input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        throw HealthChecksRepositoryOperationError.saveFailed
    }

    func deleteReminder(id: UUID, expectedUpdatedAt: Date) async throws {
        throw HealthChecksRepositoryOperationError.saveFailed
    }

    func completeReminder(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws -> HealthCheckCompletionMutation {
        completionRequests.append(
            .init(id: id, expectedUpdatedAt: expectedUpdatedAt)
        )
        return try completionResults.removeFirst().get()
    }
}

@MainActor
private final class SuspendingHealthChecksRepository: HealthChecksRepository {
    typealias CompletionRequest = HealthChecksRepositoryFake.CompletionRequest

    let reminders: [HealthCheckReminderSnapshot]
    private(set) var completionRequests: [CompletionRequest] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completionContinuation:
        CheckedContinuation<HealthCheckCompletionMutation, Error>?
    private var starts = 0

    init(reminders: [HealthCheckReminderSnapshot]) {
        self.reminders = reminders
    }

    func fetchReminders() async throws -> [HealthCheckReminderSnapshot] {
        reminders
    }

    func createReminder(
        _ input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        throw HealthChecksRepositoryOperationError.saveFailed
    }

    func updateReminder(
        id: UUID,
        expectedUpdatedAt: Date,
        input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        throw HealthChecksRepositoryOperationError.saveFailed
    }

    func deleteReminder(id: UUID, expectedUpdatedAt: Date) async throws {
        throw HealthChecksRepositoryOperationError.saveFailed
    }

    func completeReminder(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws -> HealthCheckCompletionMutation {
        completionRequests.append(
            .init(id: id, expectedUpdatedAt: expectedUpdatedAt)
        )
        starts += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if starts > 1 {
            throw HealthChecksRepositoryOperationError.saveFailed
        }
        return try await withCheckedThrowingContinuation { continuation in
            completionContinuation = continuation
        }
    }

    func waitUntilCompletionStarts() async {
        if starts > 0 { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish(with result: Result<HealthCheckCompletionMutation, Error>) {
        let continuation = completionContinuation
        completionContinuation = nil
        continuation?.resume(with: result)
    }
}
