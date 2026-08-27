import Foundation
import NotificationsKit
import XCTest

@MainActor
final class NotificationAuthorizationTests: XCTestCase {
    func testConstructionPresentationDismissAndRelaunchNeverPromptAutomatically() async {
        let center = AuthorizationNotificationCenterFake()
        var controller: HealthCheckNotificationAuthorizationController? =
            HealthCheckNotificationAuthorizationController(center: center)

        controller?.beginPresentation()
        controller?.dismiss()
        controller = HealthCheckNotificationAuthorizationController(center: center)
        controller?.beginPresentation()
        let requestCount = await center.authorizationRequestCount

        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(controller?.state, .idle)
    }

    func testRepeatedExplicitTapWhileRequestIsInFlightStartsOnlyOneRequest() async throws {
        let center = AuthorizationNotificationCenterFake()
        let controller = HealthCheckNotificationAuthorizationController(center: center)
        controller.beginPresentation()

        let firstTap = Task {
            await controller.requestFromExplicitUserAction()
        }
        await center.waitUntilAuthorizationRequest(call: 1)
        let secondTap = Task {
            await controller.requestFromExplicitUserAction()
        }
        await secondTap.value
        let inFlightCount = await center.authorizationRequestCount

        XCTAssertEqual(inFlightCount, 1)
        XCTAssertEqual(controller.state, .requesting)

        try await center.resumeAuthorizationRequest(call: 1, with: .success(true))
        await firstTap.value
        let finalCount = await center.authorizationRequestCount

        XCTAssertEqual(finalCount, 1)
        XCTAssertEqual(controller.state, .authorized)
    }

    func testDismissedOlderCallbackCannotOverwriteNewerPresentationGeneration() async throws {
        let center = AuthorizationNotificationCenterFake()
        let controller = HealthCheckNotificationAuthorizationController(center: center)
        controller.beginPresentation()

        let oldRequest = Task {
            await controller.requestFromExplicitUserAction()
        }
        await center.waitUntilAuthorizationRequest(call: 1)
        controller.dismiss()
        controller.beginPresentation()
        let newRequest = Task {
            await controller.requestFromExplicitUserAction()
        }
        await center.waitUntilAuthorizationRequest(call: 2)

        try await center.resumeAuthorizationRequest(call: 2, with: .success(true))
        await newRequest.value
        XCTAssertEqual(controller.state, .authorized)

        try await center.resumeAuthorizationRequest(call: 1, with: .success(false))
        await oldRequest.value
        let requestCount = await center.authorizationRequestCount

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(
            controller.state,
            .authorized,
            "The stale denied callback must not overwrite the newer authorization."
        )
    }

    func testExplicitRequestFailureIsRetryableAndUsesANewGeneration() async throws {
        let center = AuthorizationNotificationCenterFake()
        let controller = HealthCheckNotificationAuthorizationController(center: center)
        controller.beginPresentation()

        let first = Task {
            await controller.requestFromExplicitUserAction()
        }
        await center.waitUntilAuthorizationRequest(call: 1)
        try await center.resumeAuthorizationRequest(
            call: 1,
            with: .failure(.injected)
        )
        await first.value
        XCTAssertEqual(controller.state, .failed)

        let retry = Task {
            await controller.requestFromExplicitUserAction()
        }
        await center.waitUntilAuthorizationRequest(call: 2)
        try await center.resumeAuthorizationRequest(call: 2, with: .success(false))
        await retry.value
        let requestCount = await center.authorizationRequestCount

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(controller.state, .denied)
    }
}

private actor AuthorizationNotificationCenterFake: NotificationCenterClient {
    enum Failure: Error, Sendable {
        case injected
        case unexpectedReconciliationOperation
        case missingRequest
    }

    private var requestCount = 0
    private var requestContinuations: [
        Int: CheckedContinuation<Bool, Error>
    ] = [:]
    private var requestWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    var authorizationRequestCount: Int { requestCount }

    func authorizationStatus() async throws -> NotificationAuthorizationStatus {
        throw Failure.unexpectedReconciliationOperation
    }

    func pendingRequests() async throws -> [PendingNotificationRequestValue] {
        throw Failure.unexpectedReconciliationOperation
    }

    func deliveredRequestIdentifiers() async throws -> Set<String> {
        throw Failure.unexpectedReconciliationOperation
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async throws {
        _ = identifiers
        throw Failure.unexpectedReconciliationOperation
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws {
        _ = identifiers
        throw Failure.unexpectedReconciliationOperation
    }

    func add(_ request: NotificationRequestValue) async throws {
        _ = request
        throw Failure.unexpectedReconciliationOperation
    }

    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        let call = requestCount
        let waiters = requestWaiters.removeValue(forKey: call) ?? []
        for waiter in waiters {
            waiter.resume()
        }
        return try await withCheckedThrowingContinuation { continuation in
            requestContinuations[call] = continuation
        }
    }

    func waitUntilAuthorizationRequest(call: Int) async {
        if requestCount >= call { return }
        await withCheckedContinuation { continuation in
            requestWaiters[call, default: []].append(continuation)
        }
    }

    func resumeAuthorizationRequest(
        call: Int,
        with result: Result<Bool, Failure>
    ) throws {
        guard let continuation = requestContinuations.removeValue(forKey: call) else {
            throw Failure.missingRequest
        }
        switch result {
        case let .success(granted):
            continuation.resume(returning: granted)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
