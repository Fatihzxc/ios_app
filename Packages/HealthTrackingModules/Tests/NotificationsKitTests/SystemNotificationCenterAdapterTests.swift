@testable import NotificationsKit
import Foundation
@preconcurrency import UserNotifications
import XCTest

final class SystemNotificationCenterAdapterTests: XCTestCase {
    func testAdapterAddPreservesTrueRepeatsIntoSystemBoundary() async throws {
        let backend = NotificationCenterSystemBackendFake(
            status: .authorized,
            pending: [],
            delivered: [],
            authorizationResult: true
        )
        let adapter = SystemNotificationCenterAdapter(backend: backend)
        let request = NotificationRequestValue(
            identifier: "health-check-detail.v1.00000000-0000-0000-0000-000000000359",
            title: "Hatırlatma",
            body: "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
            deliveryDate: Date(timeIntervalSince1970: 1_804_060_800),
            userInfo: [
                "version": "1",
                "route": "health-check-detail",
                "reminderID": "00000000-0000-0000-0000-000000000359",
            ],
            repeats: true
        )

        try await adapter.add(request)
        let snapshot = await backend.snapshot()

        XCTAssertEqual(snapshot.addedRequests.count, 1)
        XCTAssertTrue(try XCTUnwrap(snapshot.addedRequests.first).repeats)
    }

    func testAdapterDelegatesEveryNotificationCenterOperationWithoutLiveCenter() async throws {
        let dueDate = Date(timeIntervalSince1970: 1_804_060_800)
        let existing = NotificationSystemRequest(
            identifier: "health-check-detail.v1.00000000-0000-0000-0000-000000000360",
            title: "Hatırlatma",
            body: "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
            deliveryDate: dueDate,
            userInfo: [
                "version": "1",
                "route": "health-check-detail",
                "reminderID": "00000000-0000-0000-0000-000000000360",
            ],
            repeats: true
        )
        let backend = NotificationCenterSystemBackendFake(
            status: .denied,
            pending: [
                .init(identifier: existing.identifier, request: existing),
            ],
            delivered: [existing.identifier],
            authorizationResult: true
        )
        let adapter = SystemNotificationCenterAdapter(backend: backend)
        let request = NotificationRequestValue(
            identifier: "health-check-detail.v1.00000000-0000-0000-0000-000000000361",
            title: "Hatırlatma",
            body: "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
            deliveryDate: dueDate,
            userInfo: [
                "version": "1",
                "route": "health-check-detail",
                "reminderID": "00000000-0000-0000-0000-000000000361",
            ]
        )

        let status = try await adapter.authorizationStatus()
        let pending = try await adapter.pendingRequests()
        let delivered = try await adapter.deliveredRequestIdentifiers()
        try await adapter.removePendingRequests(withIdentifiers: [existing.identifier])
        try await adapter.removeDeliveredRequests(withIdentifiers: [existing.identifier])
        try await adapter.add(request)
        let granted = try await adapter.requestAuthorization()
        let snapshot = await backend.snapshot()

        XCTAssertEqual(status, .denied)
        XCTAssertEqual(pending, [
            PendingNotificationRequestValue(
                identifier: existing.identifier,
                request: NotificationRequestValue(
                    identifier: existing.identifier,
                    title: existing.title,
                    body: existing.body,
                    deliveryDate: existing.deliveryDate,
                    userInfo: existing.userInfo,
                    repeats: true
                )
            ),
        ])
        XCTAssertEqual(delivered, [existing.identifier])
        XCTAssertTrue(granted)
        XCTAssertEqual(snapshot.removedPending, [[existing.identifier]])
        XCTAssertEqual(snapshot.removedDelivered, [[existing.identifier]])
        XCTAssertEqual(snapshot.authorizationRequestCount, 1)
        XCTAssertEqual(snapshot.addedRequests, [
            .init(
                identifier: request.identifier,
                title: request.title,
                body: request.body,
                deliveryDate: dueDate,
                userInfo: request.userInfo,
                repeats: false
            ),
        ])
    }

    func testPureSystemProjectionPreservesExactCalendarInstantContentAndNonRepeatingPolicy() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let dueDate = Date(timeIntervalSince1970: 1_804_060_800)
        let request = NotificationSystemRequest(
            identifier: "health-check-detail.v1.00000000-0000-0000-0000-000000000361",
            title: "Hatırlatma",
            body: "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
            deliveryDate: dueDate,
            userInfo: [
                "version": "1",
                "route": "health-check-detail",
                "reminderID": "00000000-0000-0000-0000-000000000361",
            ],
            repeats: false
        )

        let projection = request.userNotificationProjection(calendar: calendar)

        XCTAssertEqual(projection.identifier, request.identifier)
        XCTAssertEqual(projection.title, request.title)
        XCTAssertEqual(projection.body, request.body)
        XCTAssertEqual(projection.userInfo, request.userInfo)
        XCTAssertEqual(
            projection.dateComponents,
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second, .timeZone],
                from: dueDate
            )
        )
        XCTAssertFalse(projection.repeats)
    }

    func testDefaultBackendBuilderCopiesProjectionIntoActualSystemRequestWithoutLiveCenter() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let request = NotificationSystemRequest(
            identifier: "health-check-detail.v1.00000000-0000-0000-0000-000000000362",
            title: "Hatırlatma",
            body: "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
            deliveryDate: Date(timeIntervalSince1970: 1_804_060_800),
            userInfo: [
                "version": "1",
                "route": "health-check-detail",
                "reminderID": "00000000-0000-0000-0000-000000000362",
            ],
            repeats: false
        )

        let systemRequest = DefaultNotificationCenterSystemBackend
            .makeUserNotificationRequest(from: request, calendar: calendar)

        XCTAssertEqual(systemRequest.identifier, request.identifier)
        XCTAssertEqual(systemRequest.content.title, request.title)
        XCTAssertEqual(systemRequest.content.body, request.body)
        XCTAssertEqual(
            systemRequest.content.userInfo as? [String: String],
            request.userInfo
        )
        XCTAssertNotNil(systemRequest.trigger)
        XCTAssertEqual(systemRequest.trigger?.repeats, false)
    }

    func testDefaultBackendMapsAuthorizationAndRoundTripsPendingRequestWithoutLiveCenter() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let request = NotificationSystemRequest(
            identifier: "health-check-detail.v1.00000000-0000-0000-0000-000000000363",
            title: "Hatırlatma",
            body: "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
            deliveryDate: Date(timeIntervalSince1970: 1_804_060_800),
            userInfo: [
                "version": "1",
                "route": "health-check-detail",
                "reminderID": "00000000-0000-0000-0000-000000000363",
            ],
            repeats: true
        )
        let systemRequest = DefaultNotificationCenterSystemBackend
            .makeUserNotificationRequest(from: request, calendar: calendar)

        let pendingRoundTrip = DefaultNotificationCenterSystemBackend.pendingSystemRequest(
            from: systemRequest,
            calendar: calendar
        )

        XCTAssertEqual(pendingRoundTrip.identifier, request.identifier)
        XCTAssertEqual(pendingRoundTrip.request, request)
        XCTAssertEqual(
            DefaultNotificationCenterSystemBackend.notificationAuthorizationStatus(
                from: .authorized
            ),
            .authorized
        )
        XCTAssertEqual(
            DefaultNotificationCenterSystemBackend.notificationAuthorizationStatus(
                from: .provisional
            ),
            .authorized
        )
        XCTAssertEqual(
            DefaultNotificationCenterSystemBackend.notificationAuthorizationStatus(
                from: .denied
            ),
            .denied
        )
        XCTAssertEqual(
            DefaultNotificationCenterSystemBackend.notificationAuthorizationStatus(
                from: .notDetermined
            ),
            .notDetermined
        )
    }

    func testPendingSystemProjectionPreservesIdentifierWhenRawRequestIsUnprojectable() {
        let raw = UNNotificationRequest(
            identifier: "health-check-detail.v1.legacy-unprojectable",
            content: UNMutableNotificationContent(),
            trigger: nil
        )

        let pending = DefaultNotificationCenterSystemBackend.pendingSystemRequest(
            from: raw,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(pending.identifier, raw.identifier)
        XCTAssertNil(pending.request)
    }

    func testDefaultAdapterExecutesLiveDriverOperationsAcrossAllOperationsWithoutLiveCenter() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let pending = NotificationRequestValue(
            identifier: "health-check-detail.v1.00000000-0000-0000-0000-000000000364",
            title: "Hatırlatma",
            body: "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
            deliveryDate: Date(timeIntervalSince1970: 1_804_060_800),
            userInfo: [
                "version": "1",
                "route": "health-check-detail",
                "reminderID": "00000000-0000-0000-0000-000000000364",
            ]
        )
        let added = NotificationRequestValue(
            identifier: "health-check-detail.v1.00000000-0000-0000-0000-000000000365",
            title: "Reminder",
            body: "View your scheduled reminder in the app.",
            deliveryDate: pending.deliveryDate.addingTimeInterval(3_600),
            userInfo: [
                "version": "1",
                "route": "health-check-detail",
                "reminderID": "00000000-0000-0000-0000-000000000365",
            ]
        )
        let systemPending = DefaultNotificationCenterSystemBackend
            .makeUserNotificationRequest(
                from: NotificationSystemRequest(pending),
                calendar: calendar
            )
        let unprojectableSystemPending = UNNotificationRequest(
            identifier: "health-check-detail.v1.legacy-live-unprojectable",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let recorder = DefaultSystemNotificationCenterDriverRecorder()
        let operations = DefaultNotificationCenterSystemBackend.LiveOperations(
            authorizationStatus: {
                await recorder.recordAuthorizationStatus()
                return .denied
            },
            pendingRequests: {
                await recorder.recordPendingRequests()
                return [systemPending, unprojectableSystemPending]
            },
            deliveredRequestIdentifiers: {
                await recorder.recordDeliveredRequests()
                return [pending.identifier]
            },
            removePendingRequests: { identifiers in
                await recorder.recordRemovedPending(identifiers)
            },
            removeDeliveredRequests: { identifiers in
                await recorder.recordRemovedDelivered(identifiers)
            },
            add: { request in
                await recorder.recordAdded(
                    identifier: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    userInfo: request.content.userInfo as? [String: String],
                    repeats: request.trigger?.repeats
                )
            },
            requestAuthorization: {
                await recorder.recordAuthorizationRequest()
                return false
            }
        )
        let adapter = SystemNotificationCenterAdapter(
            calendar: calendar,
            systemDriver: .live(operations: operations)
        )

        let status = try await adapter.authorizationStatus()
        let pendingRequests = try await adapter.pendingRequests()
        let delivered = try await adapter.deliveredRequestIdentifiers()
        try await adapter.removePendingRequests(withIdentifiers: [pending.identifier])
        try await adapter.removeDeliveredRequests(withIdentifiers: [pending.identifier])
        try await adapter.add(added)
        let granted = try await adapter.requestAuthorization()
        let snapshot = await recorder.snapshot()

        XCTAssertEqual(status, .denied)
        XCTAssertEqual(pendingRequests, [
            PendingNotificationRequestValue(
                identifier: pending.identifier,
                request: pending
            ),
            PendingNotificationRequestValue(
                identifier: unprojectableSystemPending.identifier,
                request: nil
            ),
        ])
        XCTAssertEqual(delivered, [pending.identifier])
        XCTAssertFalse(granted)
        XCTAssertEqual(snapshot.authorizationStatusCount, 1)
        XCTAssertEqual(snapshot.pendingRequestsCount, 1)
        XCTAssertEqual(snapshot.deliveredRequestsCount, 1)
        XCTAssertEqual(snapshot.removedPending, [[pending.identifier]])
        XCTAssertEqual(snapshot.removedDelivered, [[pending.identifier]])
        XCTAssertEqual(snapshot.authorizationRequestCount, 1)
        XCTAssertEqual(snapshot.addedRequests, [
            .init(
                identifier: added.identifier,
                title: added.title,
                body: added.body,
                userInfo: added.userInfo,
                repeats: false
            ),
        ])
    }

    func testPublicDefaultAdapterConstructsWithoutTouchingLiveCenter() {
        let adapter = SystemNotificationCenterAdapter()
        withExtendedLifetime(adapter) {}
    }

    func testInjectedCenterProviderRemainsDeferredAcrossLiveDriverAndAdapterConstruction() {
        let probe = DeferredNotificationCenterProviderProbe()
        let operations = DefaultNotificationCenterSystemBackend.LiveOperations.system(
            centerProvider: { probe.resolve() }
        )
        let driver = DefaultNotificationCenterSystemBackend.Driver.live(
            operations: operations
        )
        let adapter = SystemNotificationCenterAdapter(
            calendar: Calendar(identifier: .gregorian),
            systemDriver: driver
        )

        withExtendedLifetime(adapter) {}
        XCTAssertEqual(probe.callCount, 0)
    }

    func testLiveDriverAndDefaultAdapterPropagateEverySystemOperationError() async {
        let request = NotificationRequestValue(
            identifier: "health-check-detail.v1.00000000-0000-0000-0000-000000000366",
            title: "Hatırlatma",
            body: "Planladığınız hatırlatmayı uygulamada görüntüleyin.",
            deliveryDate: Date(timeIntervalSince1970: 1_804_060_800),
            userInfo: [
                "version": "1",
                "route": "health-check-detail",
                "reminderID": "00000000-0000-0000-0000-000000000366",
            ]
        )

        for failingOrdinal in 1...7 {
            let expectedFailure = DefaultSystemDriverFailure.injected(failingOrdinal)
            let operations = DefaultNotificationCenterSystemBackend.LiveOperations(
                authorizationStatus: {
                    if failingOrdinal == 1 { throw expectedFailure }
                    return .authorized
                },
                pendingRequests: {
                    if failingOrdinal == 2 { throw expectedFailure }
                    return []
                },
                deliveredRequestIdentifiers: {
                    if failingOrdinal == 3 { throw expectedFailure }
                    return []
                },
                removePendingRequests: { _ in
                    if failingOrdinal == 4 { throw expectedFailure }
                },
                removeDeliveredRequests: { _ in
                    if failingOrdinal == 5 { throw expectedFailure }
                },
                add: { _ in
                    if failingOrdinal == 6 { throw expectedFailure }
                },
                requestAuthorization: {
                    if failingOrdinal == 7 { throw expectedFailure }
                    return true
                }
            )
            let adapter = SystemNotificationCenterAdapter(
                calendar: Calendar(identifier: .gregorian),
                systemDriver: .live(operations: operations)
            )

            do {
                switch failingOrdinal {
                case 1:
                    _ = try await adapter.authorizationStatus()
                case 2:
                    _ = try await adapter.pendingRequests()
                case 3:
                    _ = try await adapter.deliveredRequestIdentifiers()
                case 4:
                    try await adapter.removePendingRequests(withIdentifiers: [request.identifier])
                case 5:
                    try await adapter.removeDeliveredRequests(withIdentifiers: [request.identifier])
                case 6:
                    try await adapter.add(request)
                case 7:
                    _ = try await adapter.requestAuthorization()
                default:
                    XCTFail("Unexpected system operation ordinal.")
                }
                XCTFail("System operation \(failingOrdinal) must propagate its exact error.")
            } catch let failure as DefaultSystemDriverFailure {
                XCTAssertEqual(failure, expectedFailure)
            } catch {
                XCTFail("Unexpected error for operation \(failingOrdinal): \(error)")
            }
        }
    }
}

private enum DefaultSystemDriverFailure: Error, Equatable, Sendable {
    case injected(Int)
}

private final class DeferredNotificationCenterProviderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func resolve() -> UNUserNotificationCenter {
        lock.lock()
        count += 1
        lock.unlock()
        return .current()
    }
}

private actor DefaultSystemNotificationCenterDriverRecorder {
    struct AddedRequest: Equatable, Sendable {
        let identifier: String
        let title: String
        let body: String
        let userInfo: [String: String]?
        let repeats: Bool?
    }

    struct Snapshot: Sendable {
        let authorizationStatusCount: Int
        let pendingRequestsCount: Int
        let deliveredRequestsCount: Int
        let removedPending: [[String]]
        let removedDelivered: [[String]]
        let addedRequests: [AddedRequest]
        let authorizationRequestCount: Int
    }

    private var authorizationStatusCount = 0
    private var pendingRequestsCount = 0
    private var deliveredRequestsCount = 0
    private var removedPending: [[String]] = []
    private var removedDelivered: [[String]] = []
    private var addedRequests: [AddedRequest] = []
    private var authorizationRequestCount = 0

    func recordAuthorizationStatus() { authorizationStatusCount += 1 }

    func recordPendingRequests() { pendingRequestsCount += 1 }

    func recordDeliveredRequests() { deliveredRequestsCount += 1 }

    func recordRemovedPending(_ identifiers: [String]) {
        removedPending.append(identifiers)
    }

    func recordRemovedDelivered(_ identifiers: [String]) {
        removedDelivered.append(identifiers)
    }

    func recordAdded(
        identifier: String,
        title: String,
        body: String,
        userInfo: [String: String]?,
        repeats: Bool?
    ) {
        addedRequests.append(
            .init(
                identifier: identifier,
                title: title,
                body: body,
                userInfo: userInfo,
                repeats: repeats
            )
        )
    }

    func recordAuthorizationRequest() { authorizationRequestCount += 1 }

    func snapshot() -> Snapshot {
        Snapshot(
            authorizationStatusCount: authorizationStatusCount,
            pendingRequestsCount: pendingRequestsCount,
            deliveredRequestsCount: deliveredRequestsCount,
            removedPending: removedPending,
            removedDelivered: removedDelivered,
            addedRequests: addedRequests,
            authorizationRequestCount: authorizationRequestCount
        )
    }
}

private actor NotificationCenterSystemBackendFake: NotificationCenterSystemBackend {
    struct Snapshot: Sendable {
        let addedRequests: [NotificationSystemRequest]
        let removedPending: [[String]]
        let removedDelivered: [[String]]
        let authorizationRequestCount: Int
    }

    private let status: NotificationAuthorizationStatus
    private var pending: [PendingNotificationSystemRequest]
    private var delivered: Set<String>
    private let authorizationResult: Bool
    private var addedRequests: [NotificationSystemRequest] = []
    private var removedPending: [[String]] = []
    private var removedDelivered: [[String]] = []
    private var authorizationRequestCount = 0

    init(
        status: NotificationAuthorizationStatus,
        pending: [PendingNotificationSystemRequest],
        delivered: Set<String>,
        authorizationResult: Bool
    ) {
        self.status = status
        self.pending = pending
        self.delivered = delivered
        self.authorizationResult = authorizationResult
    }

    func authorizationStatus() async throws -> NotificationAuthorizationStatus {
        status
    }

    func pendingRequests() async throws -> [PendingNotificationSystemRequest] { pending }

    func deliveredRequestIdentifiers() async throws -> Set<String> { delivered }

    func removePendingRequests(withIdentifiers identifiers: [String]) async throws {
        removedPending.append(identifiers)
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws {
        removedDelivered.append(identifiers)
        delivered.subtract(identifiers)
    }

    func add(_ request: NotificationSystemRequest) async throws {
        addedRequests.append(request)
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(.init(identifier: request.identifier, request: request))
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return authorizationResult
    }

    func snapshot() -> Snapshot {
        Snapshot(
            addedRequests: addedRequests,
            removedPending: removedPending,
            removedDelivered: removedDelivered,
            authorizationRequestCount: authorizationRequestCount
        )
    }
}
