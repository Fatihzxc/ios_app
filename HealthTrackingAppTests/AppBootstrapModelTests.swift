@testable import HealthTrackingApp
import XCTest

@MainActor
final class AppBootstrapModelTests: XCTestCase {
    // Mutation caught: an initializer that exposes content or error before a load
    // attempt would let the root view render an uninitialized composition.
    func testInitialStateIsLoading() {
        let model = AppBootstrapModel(load: {})

        XCTAssertEqual(model.state, .loading)
    }

    // Mutation caught: starting a load for every implicit request would seed or build
    // dependencies more than once during a single composition lifecycle.
    func testConcurrentImplicitLoadsInvokeBoundaryExactlyOnce() async {
        let harness = LoadHarness()
        let model = AppBootstrapModel(load: { try await harness.load() })

        async let first: Void = model.loadIfNeeded()
        async let second: Void = model.loadIfNeeded()
        await harness.waitForAttempt()
        let attemptsWhileSuspended = await harness.attemptCount()
        XCTAssertEqual(attemptsWhileSuspended, 1)

        await harness.release()
        await first
        await second

        XCTAssertEqual(model.state, .content)
        let attemptsAfterSuccess = await harness.attemptCount()
        XCTAssertEqual(attemptsAfterSuccess, 1)
    }

    // Mutation caught: allowing a completed composition to run another implicit load
    // would create or seed its dependencies again on a later view update.
    func testSequentialImplicitLoadAfterSuccessDoesNotInvokeBoundaryAgain() async {
        let harness = LoadHarness()
        let model = AppBootstrapModel(load: { try await harness.load() })

        let firstLoad = Task { await model.loadIfNeeded() }
        await harness.waitForAttempt()
        await harness.release()
        await firstLoad.value

        await model.loadIfNeeded()

        let attemptsAfterSequentialLoad = await harness.attemptCount()
        XCTAssertEqual(attemptsAfterSequentialLoad, 1)
        XCTAssertEqual(model.state, .content)
    }

    // Mutation caught: completing the injected construction/seed boundary without
    // publishing content would leave the root permanently on its loading screen.
    func testSuccessfulImplicitLoadBecomesContent() async {
        let harness = LoadHarness()
        let model = AppBootstrapModel(load: { try await harness.load() })

        let load = Task { await model.loadIfNeeded() }
        await harness.waitForAttempt()
        await harness.release()
        await load.value

        XCTAssertEqual(model.state, .content)
    }

    // Mutation caught: surfacing a dependency error payload would leak technical
    // details into app state rather than exposing one stable recoverable error state.
    func testFailedImplicitLoadBecomesStableErrorWithoutTechnicalPayload() async {
        let model = AppBootstrapModel(load: { throw LoadFailure() })

        await model.loadIfNeeded()

        XCTAssertEqual(model.state, .error)
    }

    // Mutation caught: treating a failed composition as eligible for another implicit
    // load would repeatedly create/seed dependencies from ordinary view updates.
    func testImplicitLoadAfterFailureDoesNotInvokeBoundaryAgain() async {
        let harness = LoadHarness(failure: LoadFailure())
        let model = AppBootstrapModel(load: { try await harness.load() })

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        let attemptsAfterFailure = await harness.attemptCount()
        XCTAssertEqual(attemptsAfterFailure, 1)
        XCTAssertEqual(model.state, .error)
    }

    // Mutation caught: retrying without resetting lifecycle state would either skip
    // the second attempt or conceal that the UI re-entered loading while it was held.
    func testExplicitRetryMakesSecondAttemptAndReentersLoadingBeforeSuccess() async {
        let harness = LoadHarness()
        let model = AppBootstrapModel(load: { try await harness.load() })

        let firstLoad = Task { await model.loadIfNeeded() }
        await harness.waitForAttempt()
        await harness.failCurrentAttempt()
        await firstLoad.value
        XCTAssertEqual(model.state, .error)

        let retry = Task { await model.retry() }
        await harness.waitForAttempt(count: 2)
        XCTAssertEqual(model.state, .loading)
        let attemptsDuringRetry = await harness.attemptCount()
        XCTAssertEqual(attemptsDuringRetry, 2)

        await harness.release()
        await retry.value
        XCTAssertEqual(model.state, .content)
    }

    private struct LoadFailure: Error {}

    private actor LoadHarness {
        private var attempts = 0
        private var failure: Error?
        private var continuations: [CheckedContinuation<Void, Error>] = []
        private var waitingForAttempt: [Int: CheckedContinuation<Void, Never>] = [:]

        init(failure: Error? = nil) {
            self.failure = failure
        }

        func load() async throws {
            attempts += 1
            waitingForAttempt.removeValue(forKey: attempts)?.resume()
            if let failure {
                throw failure
            }
            try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }

        func attemptCount() -> Int { attempts }

        func waitForAttempt(count: Int = 1) async {
            guard attempts < count else { return }
            await withCheckedContinuation { continuation in
                waitingForAttempt[count] = continuation
            }
        }

        func release() {
            continuations.removeFirst().resume()
        }

        func failCurrentAttempt() {
            continuations.removeFirst().resume(throwing: LoadFailure())
        }
    }
}
