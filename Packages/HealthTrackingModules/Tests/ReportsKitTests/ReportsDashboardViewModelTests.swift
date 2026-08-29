import Foundation
@testable import ReportsKit
import XCTest

@MainActor
final class ReportsDashboardViewModelTests: XCTestCase {
    func testInitialStateUsesSelectedPresetWithoutInventingSourceOrInterval() throws {
        let repository = ReportsRepositoryStub(responses: [])
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: try calendar(timeZoneIdentifier: "Europe/Istanbul"),
            selectedPreset: .threeMonths
        )

        XCTAssertEqual(viewModel.selectedPreset, .threeMonths)
        XCTAssertEqual(viewModel.loadState, .idle)
        XCTAssertNil(viewModel.interval)
        XCTAssertNil(viewModel.source)
        XCTAssertNil(viewModel.failure)
    }

    func testLoadResolvesWithInjectedCalendarAndForwardsExactIntervalToRepository() async throws {
        let observedAt = try date("2024-03-10T19:00:00Z")
        let source = ReportsDashboardSource(
            coverage: ReportCoverage(
                observations: [(date: observedAt, value: Optional(0.0))]
            )
        )
        let repository = ReportsRepositoryStub(responses: [.success(source)])
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: try calendar(timeZoneIdentifier: "America/Los_Angeles"),
            selectedPreset: .oneMonth
        )

        await viewModel.load(referenceDate: observedAt)

        let expectedInterval = ReportDateInterval(
            start: try date("2024-02-11T08:00:00Z"),
            endExclusive: try date("2024-03-11T07:00:00Z")
        )
        let requestedIntervals = await repository.requestedIntervals()
        XCTAssertEqual(requestedIntervals, [expectedInterval])
        XCTAssertEqual(viewModel.interval, expectedInterval)
        XCTAssertEqual(viewModel.source, source)
        XCTAssertEqual(viewModel.source?.coverage.observedCount, 1, "An explicit zero is observed data.")
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertNil(viewModel.failure)
    }

    func testSelectingPresetUpdatesSelectionBeforeFetchingTheNewRange() async throws {
        let empty = ReportsDashboardSource()
        let repository = ReportsRepositoryStub(responses: [.success(empty)])
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: try calendar(timeZoneIdentifier: "Europe/Istanbul")
        )
        let referenceDate = try date("2024-03-31T09:00:00Z")

        await viewModel.selectPreset(.oneYear, referenceDate: referenceDate)

        let expectedInterval = ReportDateInterval(
            start: try date("2023-03-31T21:00:00Z"),
            endExclusive: try date("2024-03-31T21:00:00Z")
        )
        let requestedIntervals = await repository.requestedIntervals()
        XCTAssertEqual(viewModel.selectedPreset, .oneYear)
        XCTAssertEqual(requestedIntervals, [expectedInterval])
        XCTAssertEqual(viewModel.interval, expectedInterval)
        XCTAssertEqual(viewModel.source, empty)
        XCTAssertEqual(viewModel.loadState, .loaded)
    }

    func testFailedReloadClearsStaleSourceAndPreservesTheAttemptedInterval() async throws {
        let firstSource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observations: [(date: try date("2024-03-10T19:00:00Z"), value: Optional(5.0))]
            )
        )
        let repository = ReportsRepositoryStub(
            responses: [.success(firstSource), .failure(.fetch)]
        )
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: try calendar(timeZoneIdentifier: "America/Los_Angeles")
        )
        let referenceDate = try date("2024-03-10T19:00:00Z")
        await viewModel.load(referenceDate: referenceDate)

        await viewModel.selectPreset(.sixMonths, referenceDate: referenceDate)

        let expectedAttempt = ReportDateInterval(
            start: try date("2023-09-11T07:00:00Z"),
            endExclusive: try date("2024-03-11T07:00:00Z")
        )
        XCTAssertEqual(viewModel.selectedPreset, .sixMonths)
        XCTAssertEqual(viewModel.interval, expectedAttempt)
        XCTAssertNil(viewModel.source, "Data from the previous range must not masquerade as the failed range.")
        XCTAssertEqual(viewModel.loadState, .failed)
        XCTAssertEqual(viewModel.failure as? FixtureFailure, .fetch)
    }

    func testCancellationReturnsToIdleWithoutPresentingAnError() async throws {
        let repository = ReportsRepositoryStub(responses: [.cancelled])
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: try calendar(timeZoneIdentifier: "Europe/Istanbul")
        )

        await viewModel.load(referenceDate: try date("2024-03-31T09:00:00Z"))

        XCTAssertEqual(viewModel.loadState, .idle)
        XCTAssertNil(viewModel.source)
        XCTAssertNil(viewModel.failure)
        XCTAssertNotNil(viewModel.interval, "The selected range remains available for an explicit retry.")
    }

    func testCancelledActiveLoadIgnoresOrdinaryRepositoryFailureAfterSuspension() async throws {
        let repository = ControllableReportsRepository()
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: try calendar(timeZoneIdentifier: "Europe/Istanbul"),
            selectedPreset: .oneMonth
        )
        let referenceDate = try date("2024-03-31T09:00:00Z")

        let load = Task { await viewModel.load(referenceDate: referenceDate) }
        await repository.waitForRequestCount(1)
        load.cancel()
        await repository.failRequest(at: 0, with: .fetch)
        await load.value

        let expectedInterval = ReportDateInterval(
            start: try date("2024-02-29T21:00:00Z"),
            endExclusive: try date("2024-03-31T21:00:00Z")
        )
        let requestedIntervals = await repository.requestedIntervals()
        XCTAssertEqual(requestedIntervals, [expectedInterval])
        XCTAssertEqual(viewModel.selectedPreset, .oneMonth)
        XCTAssertEqual(viewModel.interval, expectedInterval)
        XCTAssertEqual(viewModel.loadState, .idle)
        XCTAssertNil(viewModel.source)
        XCTAssertNil(viewModel.failure, "Cancellation must win over an ordinary repository error.")
    }

    func testOlderSuccessCannotPopulateSourceWhileNewerRangeIsPendingOrAfterItFails() async throws {
        let olderSource = ReportsDashboardSource(
            coverage: ReportCoverage(observationDates: [try date("2024-03-01T09:00:00Z")])
        )
        let repository = ControllableReportsRepository()
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: try calendar(timeZoneIdentifier: "Europe/Istanbul"),
            selectedPreset: .oneMonth
        )
        let referenceDate = try date("2024-03-31T09:00:00Z")

        let olderLoad = Task { await viewModel.load(referenceDate: referenceDate) }
        await repository.waitForRequestCount(1)
        let newerLoad = Task {
            await viewModel.selectPreset(.sixMonths, referenceDate: referenceDate)
        }
        await repository.waitForRequestCount(2)

        await repository.succeedRequest(at: 0, with: olderSource)
        await olderLoad.value

        let olderInterval = ReportDateInterval(
            start: try date("2024-02-29T21:00:00Z"),
            endExclusive: try date("2024-03-31T21:00:00Z")
        )
        let newerInterval = ReportDateInterval(
            start: try date("2023-09-30T21:00:00Z"),
            endExclusive: try date("2024-03-31T21:00:00Z")
        )
        let requestedIntervals = await repository.requestedIntervals()
        XCTAssertEqual(requestedIntervals, [olderInterval, newerInterval])
        XCTAssertEqual(viewModel.selectedPreset, .sixMonths)
        XCTAssertEqual(viewModel.interval, newerInterval)
        XCTAssertEqual(viewModel.loadState, .loading)
        XCTAssertNil(viewModel.source, "An obsolete success must not appear for the selected range.")
        XCTAssertNil(viewModel.failure)

        await repository.failRequest(at: 1, with: .fetch)
        await newerLoad.value

        XCTAssertEqual(viewModel.selectedPreset, .sixMonths)
        XCTAssertEqual(viewModel.interval, newerInterval)
        XCTAssertEqual(viewModel.loadState, .failed)
        XCTAssertNil(viewModel.source, "The older source must not survive the newer range failure.")
        XCTAssertEqual(viewModel.failure as? FixtureFailure, .fetch)
    }

    func testOlderFailureCannotOverwriteNewerSuccess() async throws {
        let newerSource = ReportsDashboardSource(
            coverage: ReportCoverage(observationDates: [try date("2024-03-20T09:00:00Z")])
        )
        let repository = ControllableReportsRepository()
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: try calendar(timeZoneIdentifier: "Europe/Istanbul"),
            selectedPreset: .oneMonth
        )
        let referenceDate = try date("2024-03-31T09:00:00Z")

        let olderLoad = Task { await viewModel.load(referenceDate: referenceDate) }
        await repository.waitForRequestCount(1)
        let newerLoad = Task {
            await viewModel.selectPreset(.sixMonths, referenceDate: referenceDate)
        }
        await repository.waitForRequestCount(2)

        await repository.succeedRequest(at: 1, with: newerSource)
        await newerLoad.value
        await repository.failRequest(at: 0, with: .fetch)
        await olderLoad.value

        let olderInterval = ReportDateInterval(
            start: try date("2024-02-29T21:00:00Z"),
            endExclusive: try date("2024-03-31T21:00:00Z")
        )
        let newerInterval = ReportDateInterval(
            start: try date("2023-09-30T21:00:00Z"),
            endExclusive: try date("2024-03-31T21:00:00Z")
        )
        let requestedIntervals = await repository.requestedIntervals()
        XCTAssertEqual(requestedIntervals, [olderInterval, newerInterval])
        XCTAssertEqual(viewModel.selectedPreset, .sixMonths)
        XCTAssertEqual(viewModel.interval, newerInterval)
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.source, newerSource)
        XCTAssertNil(viewModel.failure, "An obsolete failure must not replace the latest success.")
    }

    func testPublicDomainValuesAreEquatableAndSendable() {
        assertEquatableSendable(ReportDateRangePreset.self)
        assertEquatableSendable(ReportDateInterval.self)
        assertEquatableSendable(ReportDateRangeError.self)
        assertEquatableSendable(ReportCoverage.self)
        assertEquatableSendable(ReportsDashboardSource.self)
        assertEquatableSendable(ReportsDashboardLoadState.self)
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}

    private func calendar(timeZoneIdentifier: String) throws -> Calendar {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw FixtureFailure.invalidTimeZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw FixtureFailure.invalidDate
        }
        return date
    }
}

private enum FixtureFailure: Error, Equatable, Sendable {
    case cancelled
    case fetch
    case invalidDate
    case invalidTimeZone
}

private actor ReportsRepositoryStub: ReportsRepository {
    enum Response: Sendable {
        case cancelled
        case failure(FixtureFailure)
        case success(ReportsDashboardSource)
    }

    private var responses: [Response]
    private var intervals: [ReportDateInterval] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func fetchDashboardSource(in interval: ReportDateInterval) async throws -> ReportsDashboardSource {
        intervals.append(interval)
        guard !responses.isEmpty else {
            throw FixtureFailure.fetch
        }
        switch responses.removeFirst() {
        case .cancelled:
            throw CancellationError()
        case let .failure(error):
            throw error
        case let .success(source):
            return source
        }
    }

    func requestedIntervals() -> [ReportDateInterval] {
        intervals
    }
}

private actor ControllableReportsRepository: ReportsRepository {
    private struct RequestCountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var intervals: [ReportDateInterval] = []
    private var continuations: [Int: CheckedContinuation<ReportsDashboardSource, Error>] = [:]
    private var requestCountWaiters: [RequestCountWaiter] = []

    func fetchDashboardSource(in interval: ReportDateInterval) async throws -> ReportsDashboardSource {
        let requestIndex = intervals.count
        intervals.append(interval)
        resumeSatisfiedRequestCountWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            continuations[requestIndex] = continuation
        }
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        guard intervals.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            requestCountWaiters.append(
                RequestCountWaiter(
                    expectedCount: expectedCount,
                    continuation: continuation
                )
            )
        }
    }

    func succeedRequest(at index: Int, with source: ReportsDashboardSource) {
        guard let continuation = continuations.removeValue(forKey: index) else {
            XCTFail("Missing controllable report request at index \(index).")
            return
        }
        continuation.resume(returning: source)
    }

    func failRequest(at index: Int, with error: FixtureFailure) {
        guard let continuation = continuations.removeValue(forKey: index) else {
            XCTFail("Missing controllable report request at index \(index).")
            return
        }
        continuation.resume(throwing: error)
    }

    func requestedIntervals() -> [ReportDateInterval] {
        intervals
    }

    private func resumeSatisfiedRequestCountWaiters() {
        let satisfied = requestCountWaiters.filter { intervals.count >= $0.expectedCount }
        requestCountWaiters.removeAll { intervals.count >= $0.expectedCount }
        for waiter in satisfied {
            waiter.continuation.resume()
        }
    }
}
