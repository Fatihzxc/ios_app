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
        XCTAssertNil(viewModel.report)
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
        XCTAssertEqual(
            viewModel.report,
            try ReportsDashboardBuilder.build(
                source: source,
                interval: expectedInterval,
                calendar: try calendar(timeZoneIdentifier: "America/Los_Angeles")
            )
        )
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
        XCTAssertNil(viewModel.report)
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
        XCTAssertNil(viewModel.report)
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
        XCTAssertNil(viewModel.report)
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
        XCTAssertNil(viewModel.report)
        XCTAssertNil(viewModel.failure)

        await repository.failRequest(at: 1, with: .fetch)
        await newerLoad.value

        XCTAssertEqual(viewModel.selectedPreset, .sixMonths)
        XCTAssertEqual(viewModel.interval, newerInterval)
        XCTAssertEqual(viewModel.loadState, .failed)
        XCTAssertNil(viewModel.source, "The older source must not survive the newer range failure.")
        XCTAssertNil(viewModel.report)
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
        XCTAssertEqual(viewModel.report?.interval, newerInterval)
        XCTAssertNil(viewModel.failure, "An obsolete failure must not replace the latest success.")
    }

    func testRepositoryFetchRemainsOnMainActorAndImmutableBuildRunsOffMain() async throws {
        let source = ReportsDashboardSource(
            coverage: ReportCoverage(observationDates: [try date("2024-03-20T09:00:00Z")])
        )
        let repository = MainActorReportsRepositoryStub(source: source)
        let buildRecorder = DashboardBuildThreadRecorder()
        let injectedCalendar = try calendar(timeZoneIdentifier: "Europe/Istanbul")
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: injectedCalendar,
            build: { source, interval, calendar in
                buildRecorder.recordCurrentThread()
                return try ReportsDashboardBuilder.build(
                    source: source,
                    interval: interval,
                    calendar: calendar
                )
            }
        )

        await viewModel.load(referenceDate: try date("2024-03-31T09:00:00Z"))

        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertEqual(repository.fetchWasOnMainThread, true)
        XCTAssertEqual(buildRecorder.wasOnMainThread, false)
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.report?.sourceCoverage, source.coverage)
    }

    func testSupersededDetachedBuildFailureCannotReplaceNewerRangeSuccess() async throws {
        let repository = ReportsRepositoryStub(
            responses: [.success(ReportsDashboardSource()), .success(ReportsDashboardSource())]
        )
        let buildGate = DashboardBuildGate(firstOutcome: .failure(.fetch))
        let injectedCalendar = try calendar(timeZoneIdentifier: "Europe/Istanbul")
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: injectedCalendar,
            selectedPreset: .oneMonth,
            build: buildGate.build
        )
        let referenceDate = try date("2024-03-31T09:00:00Z")

        let olderLoad = Task { await viewModel.load(referenceDate: referenceDate) }
        try await buildGate.waitUntilFirstBuildStarts()

        let newerLoad = Task {
            await viewModel.selectPreset(.sixMonths, referenceDate: referenceDate)
        }
        await newerLoad.value

        let newerInterval = ReportDateInterval(
            start: try date("2023-09-30T21:00:00Z"),
            endExclusive: try date("2024-03-31T21:00:00Z")
        )
        XCTAssertEqual(viewModel.selectedPreset, .sixMonths)
        XCTAssertEqual(viewModel.interval, newerInterval)
        XCTAssertEqual(viewModel.report?.interval, newerInterval)
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertNil(viewModel.failure)

        buildGate.releaseFirstBuild()
        await olderLoad.value

        XCTAssertEqual(viewModel.selectedPreset, .sixMonths)
        XCTAssertEqual(viewModel.interval, newerInterval)
        XCTAssertEqual(viewModel.report?.interval, newerInterval)
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertNil(viewModel.failure, "An obsolete builder failure must not overwrite the selected range.")
    }

    func testCancelledBlockingBuildIsCancelledWhileReentryPublishesBeforeOldRelease() async throws {
        let olderSource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: [try date("2024-03-01T09:00:00Z")]
            )
        )
        let reentrySource = ReportsDashboardSource(
            coverage: ReportCoverage(
                observationDates: [try date("2024-03-20T09:00:00Z")]
            )
        )
        let repository = ReportsRepositoryStub(
            responses: [.success(olderSource), .success(reentrySource)]
        )
        let buildGate = DashboardBuildGate(firstOutcome: .success)
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: try calendar(timeZoneIdentifier: "Europe/Istanbul"),
            build: buildGate.build
        )
        let referenceDate = try date("2024-03-31T09:00:00Z")

        let cancelledLoad = Task { await viewModel.load(referenceDate: referenceDate) }
        try await buildGate.waitUntilFirstBuildStarts()
        cancelledLoad.cancel()

        let reentryLoad = Task { await viewModel.load(referenceDate: referenceDate) }
        await reentryLoad.value

        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.source, reentrySource)
        XCTAssertEqual(viewModel.report?.sourceCoverage, reentrySource.coverage)
        XCTAssertNil(viewModel.failure)
        XCTAssertNil(
            buildGate.firstBuildObservedCancellation,
            "The visible re-entry must finish without waiting for the obsolete synchronous builder to release."
        )

        buildGate.releaseFirstBuild()
        await cancelledLoad.value

        XCTAssertEqual(buildGate.firstBuildObservedCancellation, true)
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.source, reentrySource)
        XCTAssertEqual(viewModel.report?.sourceCoverage, reentrySource.coverage)
        XCTAssertNil(viewModel.failure, "The cancelled obsolete builder cannot overwrite the visible generation.")
    }

    func testLatestBuilderValidationFailurePreservesExactIntervalAndTypedError() async throws {
        let invalidID = UUID(uuidString: "00000000-0000-4000-8000-000000000831")!
        let invalidSource = ReportsDashboardSource(
            nutritionDayRecords: [
                .init(
                    id: invalidID,
                    date: try date("2024-03-10T09:00:00Z"),
                    createdAt: try date("2024-03-10T10:00:00Z"),
                    entryCount: 1,
                    proteinTotalG: -1,
                    proteinTargetG: 100
                ),
            ]
        )
        let repository = ReportsRepositoryStub(responses: [.success(invalidSource)])
        let viewModel = ReportsDashboardViewModel(
            repository: repository,
            calendar: try calendar(timeZoneIdentifier: "Europe/Istanbul")
        )

        await viewModel.load(referenceDate: try date("2024-03-31T09:00:00Z"))

        XCTAssertEqual(
            viewModel.interval,
            ReportDateInterval(
                start: try date("2024-02-29T21:00:00Z"),
                endExclusive: try date("2024-03-31T21:00:00Z")
            )
        )
        XCTAssertEqual(viewModel.loadState, .failed)
        XCTAssertNil(viewModel.source)
        XCTAssertNil(viewModel.report)
        XCTAssertEqual(
            viewModel.failure as? ProteinAdherenceBuilderError,
            .invalidObservedDay(id: invalidID)
        )
    }

    func testPublicDomainValuesAreEquatableAndSendable() {
        assertEquatableSendable(ReportDateRangePreset.self)
        assertEquatableSendable(ReportDateInterval.self)
        assertEquatableSendable(ReportDateRangeError.self)
        assertEquatableSendable(ReportCoverage.self)
        assertEquatableSendable(ReportsDashboardSource.self)
        assertEquatableSendable(ReportsDashboard.self)
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

@MainActor
private final class ReportsRepositoryStub: ReportsRepository {
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

@MainActor
private final class ControllableReportsRepository: ReportsRepository {
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

@MainActor
private final class MainActorReportsRepositoryStub: ReportsRepository {
    private let source: ReportsDashboardSource
    private(set) var fetchCount = 0
    private(set) var fetchWasOnMainThread: Bool?

    init(source: ReportsDashboardSource) {
        self.source = source
    }

    func fetchDashboardSource(in interval: ReportDateInterval) async throws -> ReportsDashboardSource {
        _ = interval
        fetchCount += 1
        fetchWasOnMainThread = Thread.isMainThread
        return source
    }
}

private final class DashboardBuildThreadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedWasOnMainThread: Bool?

    var wasOnMainThread: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return storedWasOnMainThread
    }

    func recordCurrentThread() {
        lock.lock()
        storedWasOnMainThread = Thread.isMainThread
        lock.unlock()
    }
}

private final class DashboardBuildGate: @unchecked Sendable {
    enum FirstOutcome: Sendable {
        case failure(FixtureFailure)
        case success
    }

    private let lock = NSLock()
    private let firstBuildRelease = DispatchSemaphore(value: 0)
    private let firstOutcome: FirstOutcome
    private var invocationCount = 0
    private var firstBuildStarted = false
    private var storedFirstBuildObservedCancellation: Bool?

    var firstBuildObservedCancellation: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return storedFirstBuildObservedCancellation
    }

    init(firstOutcome: FirstOutcome) {
        self.firstOutcome = firstOutcome
    }

    func build(
        source: ReportsDashboardSource,
        interval: ReportDateInterval,
        calendar: Calendar
    ) throws -> ReportsDashboard {
        lock.lock()
        invocationCount += 1
        let invocation = invocationCount
        if invocation == 1 { firstBuildStarted = true }
        lock.unlock()

        if invocation == 1 {
            firstBuildRelease.wait()
            lock.lock()
            storedFirstBuildObservedCancellation = Task.isCancelled
            lock.unlock()
            switch firstOutcome {
            case let .failure(error): throw error
            case .success: break
            }
        }
        return try ReportsDashboardBuilder.build(
            source: source,
            interval: interval,
            calendar: calendar
        )
    }

    func waitUntilFirstBuildStarts() async throws {
        for _ in 0..<500 {
            lock.lock()
            let started = firstBuildStarted
            lock.unlock()
            if started { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("The detached first dashboard build never started.")
        throw FixtureFailure.fetch
    }

    func releaseFirstBuild() {
        firstBuildRelease.signal()
    }
}
