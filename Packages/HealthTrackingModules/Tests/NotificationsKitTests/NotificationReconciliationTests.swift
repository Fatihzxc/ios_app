import Foundation
import NotificationsKit
import XCTest

final class NotificationReconciliationTests: XCTestCase {
    func testReconciliationUsesDeterministicCleanupBeforeReplacementAndConverges() async throws {
        let fixture = try makeReconciliationFixture()
        let center = NotificationCenterFake(
            status: .authorized,
            pending: fixture.initialPending,
            delivered: fixture.initialDelivered,
            unprojectablePendingIdentifiers:
                fixture.initialUnprojectablePendingIdentifiers
        )
        let reconciler = HealthCheckNotificationReconciler(
            center: center,
            now: { fixture.now }
        )

        let result = try await reconciler.reconcile(fixture.descriptors)
        let firstSnapshot = await center.snapshot()

        XCTAssertEqual(
            firstSnapshot.operations,
            [
                .authorizationStatus,
                .pendingRequests,
                .deliveredRequestIdentifiers,
                .removePending(fixture.removedPendingIDs),
                .removeDelivered(fixture.removedDeliveredIDs),
                .add(fixture.replacementRequest),
                .add(fixture.newRequest),
            ]
        )
        XCTAssertEqual(
            result,
            .converged(
                added: 2,
                removedPending: fixture.removedPendingIDs.count,
                removedDelivered: 4
            )
        )
        XCTAssertEqual(
            firstSnapshot.pending,
            [
                fixture.foreignRequest.identifier: fixture.foreignRequest,
                fixture.replacementRequest.identifier: fixture.replacementRequest,
                fixture.newRequest.identifier: fixture.newRequest,
            ]
        )
        XCTAssertEqual(firstSnapshot.delivered, [fixture.foreignRequest.identifier])
        XCTAssertEqual(
            firstSnapshot.unprojectablePendingIdentifiers,
            [fixture.foreignUnprojectablePendingID]
        )
        XCTAssertEqual(firstSnapshot.authorizationRequestCount, 0)

        let secondResult = try await reconciler.reconcile(
            Array(fixture.descriptors.reversed())
        )
        let secondSnapshot = await center.snapshot()

        XCTAssertEqual(
            secondResult,
            .converged(added: 0, removedPending: 0, removedDelivered: 0)
        )
        XCTAssertEqual(
            Array(secondSnapshot.operations.suffix(3)),
            [.authorizationStatus, .pendingRequests, .deliveredRequestIdentifiers]
        )
        XCTAssertEqual(secondSnapshot.pending, firstSnapshot.pending)
        XCTAssertEqual(secondSnapshot.delivered, firstSnapshot.delivered)
        XCTAssertEqual(
            secondSnapshot.unprojectablePendingIdentifiers,
            firstSnapshot.unprojectablePendingIdentifiers
        )
    }

    func testFailureAtEverySystemOperationBoundaryThrowsAndRetryConvergesExactly() async throws {
        let operationBoundaryCount = 7

        for failingOrdinal in 1...operationBoundaryCount {
            let fixture = try makeReconciliationFixture()
            let center = NotificationCenterFake(
                status: .authorized,
                pending: fixture.initialPending,
                delivered: fixture.initialDelivered,
                failingOperationOrdinal: failingOrdinal,
                unprojectablePendingIdentifiers:
                    fixture.initialUnprojectablePendingIdentifiers
            )
            let reconciler = HealthCheckNotificationReconciler(
                center: center,
                now: { fixture.now }
            )

            do {
                _ = try await reconciler.reconcile(fixture.descriptors)
                XCTFail("Operation boundary \(failingOrdinal) must not report success.")
            } catch NotificationCenterFake.Failure.injected {
                // Expected: retry must recover from any partial cleanup/add boundary.
            }

            _ = try await reconciler.reconcile(fixture.descriptors)
            let snapshot = await center.snapshot()

            XCTAssertEqual(
                snapshot.pending.values.sorted { $0.identifier < $1.identifier },
                [
                    fixture.foreignRequest,
                    fixture.replacementRequest,
                    fixture.newRequest,
                ].sorted { $0.identifier < $1.identifier }
            )
            XCTAssertEqual(snapshot.delivered, [fixture.foreignRequest.identifier])
            XCTAssertEqual(
                snapshot.unprojectablePendingIdentifiers,
                [fixture.foreignUnprojectablePendingID]
            )
            XCTAssertEqual(snapshot.authorizationRequestCount, 0)
        }
    }

    func testDeniedAndNotDeterminedPerformCleanupWithoutAddingPromptingOrMutatingInput() async throws {
        let statuses: [NotificationAuthorizationStatus] = [.denied, .notDetermined]

        for status in statuses {
            let fixture = try makeReconciliationFixture()
            let descriptors = fixture.descriptors
            let center = NotificationCenterFake(
                status: status,
                pending: fixture.initialPending,
                delivered: fixture.initialDelivered,
                unprojectablePendingIdentifiers:
                    fixture.initialUnprojectablePendingIdentifiers
            )
            let reconciler = HealthCheckNotificationReconciler(
                center: center,
                now: { fixture.now }
            )

            let result = try await reconciler.reconcile(descriptors)
            let snapshot = await center.snapshot()

            XCTAssertEqual(descriptors, fixture.descriptors)
            XCTAssertEqual(result.added, 0)
            XCTAssertFalse(snapshot.operations.contains { operation in
                if case .add = operation { return true }
                return false
            })
            XCTAssertFalse(snapshot.operations.contains(.requestAuthorization))
            XCTAssertEqual(snapshot.authorizationRequestCount, 0)
            XCTAssertEqual(
                result,
                .converged(
                    added: 0,
                    removedPending: fixture.removedPendingIDs.count,
                    removedDelivered: fixture.removedDeliveredIDs.count
                )
            )
            XCTAssertEqual(snapshot.operations, [
                .authorizationStatus,
                .pendingRequests,
                .deliveredRequestIdentifiers,
                .removePending(fixture.removedPendingIDs),
                .removeDelivered(fixture.removedDeliveredIDs),
            ])
            XCTAssertEqual(snapshot.pending, [
                fixture.foreignRequest.identifier: fixture.foreignRequest,
            ])
            XCTAssertEqual(snapshot.delivered, [fixture.foreignRequest.identifier])
            XCTAssertEqual(
                snapshot.unprojectablePendingIdentifiers,
                [fixture.foreignUnprojectablePendingID]
            )
            XCTAssertFalse(
                snapshot.pending.keys.contains(fixture.replacementRequest.identifier)
            )
            XCTAssertFalse(
                snapshot.delivered.contains(fixture.replacementRequest.identifier)
            )
        }
    }

    func testRecurringOwnedRequestIsReplacedByCanonicalNonRepeatingRequest() async throws {
        let id = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000398")
        )
        let dueDate = Date(timeIntervalSince1970: 1_804_060_800)
        let descriptor = HealthCheckNotificationDescriptor(
            reminderID: id,
            dueDate: dueDate,
            isEligible: true
        )
        let desired = try XCTUnwrap(
            HealthCheckNotificationPlanner().request(for: descriptor)
        )
        let recurring = NotificationRequestValue(
            identifier: desired.identifier,
            title: desired.title,
            body: desired.body,
            deliveryDate: desired.deliveryDate,
            userInfo: desired.userInfo,
            repeats: true
        )
        let center = NotificationCenterFake(
            status: .authorized,
            pending: [recurring.identifier: recurring],
            delivered: []
        )
        let reconciler = HealthCheckNotificationReconciler(
            center: center,
            now: { dueDate.addingTimeInterval(-60) }
        )

        let result = try await reconciler.reconcile([descriptor])
        let snapshot = await center.snapshot()

        XCTAssertEqual(result, .converged(added: 1, removedPending: 1, removedDelivered: 0))
        XCTAssertEqual(snapshot.operations, [
            .authorizationStatus,
            .pendingRequests,
            .deliveredRequestIdentifiers,
            .removePending([desired.identifier]),
            .add(desired),
        ])
        XCTAssertEqual(snapshot.pending, [desired.identifier: desired])
        XCTAssertFalse(try XCTUnwrap(snapshot.pending[desired.identifier]).repeats)
    }

    func testDuplicateOwnedPendingIdentifiersFailClosedToOneCanonicalRequest() async throws {
        let reminderID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000397")
        )
        let dueDate = Date(timeIntervalSince1970: 1_804_060_800)
        let descriptor = HealthCheckNotificationDescriptor(
            reminderID: reminderID,
            dueDate: dueDate,
            isEligible: true
        )
        let desired = try XCTUnwrap(
            HealthCheckNotificationPlanner().request(for: descriptor)
        )
        let staleDuplicate = NotificationRequestValue(
            identifier: desired.identifier,
            title: desired.title,
            body: desired.body,
            deliveryDate: desired.deliveryDate.addingTimeInterval(-60),
            userInfo: desired.userInfo,
            repeats: true
        )
        let center = DuplicatePendingNotificationCenterFake(pending: [
            PendingNotificationRequestValue(
                identifier: staleDuplicate.identifier,
                request: staleDuplicate
            ),
            PendingNotificationRequestValue(
                identifier: desired.identifier,
                request: desired
            ),
        ])
        let reconciler = HealthCheckNotificationReconciler(
            center: center,
            now: { dueDate.addingTimeInterval(-120) }
        )

        let result = try await reconciler.reconcile([descriptor])
        let snapshot = await center.snapshot()

        XCTAssertEqual(result, .converged(added: 1, removedPending: 1, removedDelivered: 0))
        XCTAssertEqual(snapshot.operations, [
            .authorizationStatus,
            .pendingRequests,
            .deliveredRequestIdentifiers,
            .removePending([desired.identifier]),
            .add(desired),
        ])
        XCTAssertEqual(snapshot.pending, [
            PendingNotificationRequestValue(
                identifier: desired.identifier,
                request: desired
            ),
        ])
    }

    func testCancellationAfterSuspendedSystemReadPreventsCleanupAndAdds() async throws {
        let fixture = try makeReconciliationFixture()
        let center = NotificationCenterFake(
            status: .authorized,
            pending: fixture.initialPending,
            delivered: fixture.initialDelivered,
            suspendingOperationOrdinal: 2,
            unprojectablePendingIdentifiers:
                fixture.initialUnprojectablePendingIdentifiers
        )
        let reconciler = HealthCheckNotificationReconciler(
            center: center,
            now: { fixture.now }
        )
        let reconciliation = Task {
            try await reconciler.reconcile(fixture.descriptors)
        }
        await center.waitUntilOperationIsSuspended(ordinal: 2)

        reconciliation.cancel()
        await center.resumeSuspendedOperation(ordinal: 2)

        do {
            _ = try await reconciliation.value
            XCTFail("A canceled stale reconciliation must not report convergence.")
        } catch is CancellationError {
            // Cancellation must be observed after the suspended read and before mutation.
        }
        let snapshot = await center.snapshot()
        XCTAssertEqual(snapshot.operations, [.authorizationStatus, .pendingRequests])
        XCTAssertEqual(snapshot.pending, fixture.initialPending)
        XCTAssertEqual(snapshot.delivered, fixture.initialDelivered)
        XCTAssertEqual(
            snapshot.unprojectablePendingIdentifiers,
            fixture.initialUnprojectablePendingIdentifiers
        )
    }

    private func makeReconciliationFixture() throws -> ReconciliationFixture {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let planner = HealthCheckNotificationPlanner()
        func descriptor(
            _ suffix: Int,
            dueDate: Date,
            isEligible: Bool
        ) throws -> HealthCheckNotificationDescriptor {
            let id = try XCTUnwrap(
                UUID(uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    suffix
                ))
            )
            return .init(reminderID: id, dueDate: dueDate, isEligible: isEligible)
        }

        let replacement = try descriptor(
            341,
            dueDate: now.addingTimeInterval(10_000),
            isEligible: true
        )
        let new = try descriptor(
            342,
            dueDate: now.addingTimeInterval(20_000),
            isEligible: true
        )
        let completed = try descriptor(
            343,
            dueDate: now.addingTimeInterval(30_000),
            isEligible: false
        )
        let overdue = try descriptor(
            344,
            dueDate: now.addingTimeInterval(-1),
            isEligible: true
        )
        let deleted = try descriptor(
            345,
            dueDate: now.addingTimeInterval(40_000),
            isEligible: true
        )
        let foreign = NotificationRequestValue(
            identifier: "another-feature.v1.opaque",
            title: "Other",
            body: "Other",
            deliveryDate: now.addingTimeInterval(50_000),
            userInfo: ["route": "other"]
        )
        let replacementRequest = try XCTUnwrap(planner.request(for: replacement))
        let newRequest = try XCTUnwrap(planner.request(for: new))
        let completedRequest = NotificationRequestValue(
            identifier: HealthCheckNotificationPlanner.requestIdentifier(
                for: completed.reminderID
            ),
            title: "Hatırlatma",
            body: "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
            deliveryDate: completed.dueDate,
            userInfo: HealthCheckNotificationRouteCodec.encode(
                .healthCheckDetail(reminderID: completed.reminderID)
            )
        )
        let overdueRequest = try XCTUnwrap(planner.request(for: overdue))
        let deletedRequest = try XCTUnwrap(planner.request(for: deleted))
        let outdatedReplacement = NotificationRequestValue(
            identifier: replacementRequest.identifier,
            title: replacementRequest.title,
            body: replacementRequest.body,
            deliveryDate: replacement.dueDate.addingTimeInterval(-3_600),
            userInfo: replacementRequest.userInfo
        )
        let initialPending = [
            outdatedReplacement.identifier: outdatedReplacement,
            completedRequest.identifier: completedRequest,
            overdueRequest.identifier: overdueRequest,
            deletedRequest.identifier: deletedRequest,
            foreign.identifier: foreign,
        ]
        let initialDelivered: Set<String> = [
            replacementRequest.identifier,
            completedRequest.identifier,
            overdueRequest.identifier,
            deletedRequest.identifier,
            foreign.identifier,
        ]
        let ownedUnprojectablePendingID =
            "health-check-detail.v1.00000000-0000-0000-0000-000000000399"
        let foreignUnprojectablePendingID = "another-feature.v1.unprojectable"
        let initialUnprojectablePendingIdentifiers: Set<String> = [
            ownedUnprojectablePendingID,
            foreignUnprojectablePendingID,
        ]
        let removedPendingIDs = [
            replacementRequest.identifier,
            completedRequest.identifier,
            overdueRequest.identifier,
            deletedRequest.identifier,
            ownedUnprojectablePendingID,
        ].sorted()
        let removedDeliveredIDs = [
            replacementRequest.identifier,
            completedRequest.identifier,
            overdueRequest.identifier,
            deletedRequest.identifier,
        ].sorted()

        return ReconciliationFixture(
            now: now,
            descriptors: [new, completed, replacement, overdue, new],
            initialPending: initialPending,
            initialUnprojectablePendingIdentifiers:
                initialUnprojectablePendingIdentifiers,
            initialDelivered: initialDelivered,
            replacementRequest: replacementRequest,
            newRequest: newRequest,
            completedRequest: completedRequest,
            overdueRequest: overdueRequest,
            deletedRequest: deletedRequest,
            foreignRequest: foreign,
            foreignUnprojectablePendingID: foreignUnprojectablePendingID,
            removedPendingIDs: removedPendingIDs,
            removedDeliveredIDs: removedDeliveredIDs
        )
    }
}

private actor DuplicatePendingNotificationCenterFake: NotificationCenterClient {
    enum Operation: Equatable, Sendable {
        case authorizationStatus
        case pendingRequests
        case deliveredRequestIdentifiers
        case removePending([String])
        case removeDelivered([String])
        case add(NotificationRequestValue)
        case requestAuthorization
    }

    struct Snapshot: Sendable {
        let pending: [PendingNotificationRequestValue]
        let operations: [Operation]
    }

    private var pending: [PendingNotificationRequestValue]
    private var operations: [Operation] = []

    init(pending: [PendingNotificationRequestValue]) {
        self.pending = pending
    }

    func authorizationStatus() async throws -> NotificationAuthorizationStatus {
        operations.append(.authorizationStatus)
        return .authorized
    }

    func pendingRequests() async throws -> [PendingNotificationRequestValue] {
        operations.append(.pendingRequests)
        return pending
    }

    func deliveredRequestIdentifiers() async throws -> Set<String> {
        operations.append(.deliveredRequestIdentifiers)
        return []
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async throws {
        operations.append(.removePending(identifiers))
        let identifiers = Set(identifiers)
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws {
        operations.append(.removeDelivered(identifiers))
    }

    func add(_ request: NotificationRequestValue) async throws {
        operations.append(.add(request))
        pending.append(
            PendingNotificationRequestValue(
                identifier: request.identifier,
                request: request
            )
        )
    }

    func requestAuthorization() async throws -> Bool {
        operations.append(.requestAuthorization)
        return false
    }

    func snapshot() -> Snapshot {
        Snapshot(pending: pending, operations: operations)
    }
}

private struct ReconciliationFixture {
    let now: Date
    let descriptors: [HealthCheckNotificationDescriptor]
    let initialPending: [String: NotificationRequestValue]
    let initialUnprojectablePendingIdentifiers: Set<String>
    let initialDelivered: Set<String>
    let replacementRequest: NotificationRequestValue
    let newRequest: NotificationRequestValue
    let completedRequest: NotificationRequestValue
    let overdueRequest: NotificationRequestValue
    let deletedRequest: NotificationRequestValue
    let foreignRequest: NotificationRequestValue
    let foreignUnprojectablePendingID: String
    let removedPendingIDs: [String]
    let removedDeliveredIDs: [String]
}

private actor NotificationCenterFake: NotificationCenterClient {
    enum Failure: Error {
        case injected
        case unexpectedAuthorizationRequest
    }

    enum Operation: Equatable, Sendable {
        case authorizationStatus
        case pendingRequests
        case deliveredRequestIdentifiers
        case removePending([String])
        case removeDelivered([String])
        case add(NotificationRequestValue)
        case requestAuthorization
    }

    struct Snapshot: Sendable {
        let pending: [String: NotificationRequestValue]
        let unprojectablePendingIdentifiers: Set<String>
        let delivered: Set<String>
        let operations: [Operation]
        let authorizationRequestCount: Int
    }

    private let status: NotificationAuthorizationStatus
    private var pending: [String: NotificationRequestValue]
    private var unprojectablePendingIdentifiers: Set<String>
    private var delivered: Set<String>
    private var operations: [Operation] = []
    private var operationOrdinal = 0
    private let failingOperationOrdinal: Int?
    private let suspendingOperationOrdinal: Int?
    private var authorizationRequestCount = 0
    private var suspendedOperationContinuation: CheckedContinuation<Void, Never>?
    private var suspendedOperationWasReached = false
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        status: NotificationAuthorizationStatus,
        pending: [String: NotificationRequestValue],
        delivered: Set<String>,
        failingOperationOrdinal: Int? = nil,
        suspendingOperationOrdinal: Int? = nil,
        unprojectablePendingIdentifiers: Set<String> = []
    ) {
        self.status = status
        self.pending = pending
        self.unprojectablePendingIdentifiers = unprojectablePendingIdentifiers
        self.delivered = delivered
        self.failingOperationOrdinal = failingOperationOrdinal
        self.suspendingOperationOrdinal = suspendingOperationOrdinal
    }

    func authorizationStatus() async throws -> NotificationAuthorizationStatus {
        try await record(.authorizationStatus)
        return status
    }

    func pendingRequests() async throws -> [PendingNotificationRequestValue] {
        try await record(.pendingRequests)
        let projected = pending.values.map {
            PendingNotificationRequestValue(identifier: $0.identifier, request: $0)
        }
        let unprojectable = unprojectablePendingIdentifiers.map {
            PendingNotificationRequestValue(identifier: $0, request: nil)
        }
        return (projected + unprojectable).sorted { $0.identifier < $1.identifier }
    }

    func deliveredRequestIdentifiers() async throws -> Set<String> {
        try await record(.deliveredRequestIdentifiers)
        return delivered
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async throws {
        try await record(.removePending(identifiers))
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
            unprojectablePendingIdentifiers.remove(identifier)
        }
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws {
        try await record(.removeDelivered(identifiers))
        delivered.subtract(identifiers)
    }

    func add(_ request: NotificationRequestValue) async throws {
        try await record(.add(request))
        unprojectablePendingIdentifiers.remove(request.identifier)
        pending[request.identifier] = request
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        try await record(.requestAuthorization)
        throw Failure.unexpectedAuthorizationRequest
    }

    func waitUntilOperationIsSuspended(ordinal: Int) async {
        guard ordinal == suspendingOperationOrdinal else { return }
        if suspendedOperationWasReached { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resumeSuspendedOperation(ordinal: Int) {
        guard ordinal == suspendingOperationOrdinal else { return }
        suspendedOperationContinuation?.resume()
        suspendedOperationContinuation = nil
    }

    func snapshot() -> Snapshot {
        Snapshot(
            pending: pending,
            unprojectablePendingIdentifiers: unprojectablePendingIdentifiers,
            delivered: delivered,
            operations: operations,
            authorizationRequestCount: authorizationRequestCount
        )
    }

    private func record(_ operation: Operation) async throws {
        operationOrdinal += 1
        operations.append(operation)
        if operationOrdinal == suspendingOperationOrdinal {
            suspendedOperationWasReached = true
            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                suspendedOperationContinuation = continuation
            }
        }
        if operationOrdinal == failingOperationOrdinal {
            throw Failure.injected
        }
    }
}
