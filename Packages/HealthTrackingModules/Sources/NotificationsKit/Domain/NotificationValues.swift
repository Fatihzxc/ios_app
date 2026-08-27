import Foundation

public struct HealthCheckNotificationDescriptor: Equatable, Sendable {
    public let reminderID: UUID
    public let dueDate: Date
    public let isEligible: Bool

    public init(reminderID: UUID, dueDate: Date, isEligible: Bool) {
        self.reminderID = reminderID
        self.dueDate = dueDate
        self.isEligible = isEligible
    }
}

public struct NotificationRequestValue: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let deliveryDate: Date
    public let userInfo: [String: String]
    public let repeats: Bool

    public init(
        identifier: String,
        title: String,
        body: String,
        deliveryDate: Date,
        userInfo: [String: String],
        repeats: Bool = false
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.deliveryDate = deliveryDate
        self.userInfo = userInfo
        self.repeats = repeats
    }
}

public struct PendingNotificationRequestValue: Equatable, Sendable {
    public let identifier: String
    public let request: NotificationRequestValue?

    public init(identifier: String, request: NotificationRequestValue?) {
        self.identifier = identifier
        self.request = request
    }
}

public enum NotificationAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
}

public struct NotificationReconciliationResult: Equatable, Sendable {
    public let added: Int
    public let removedPending: Int
    public let removedDelivered: Int

    public static func converged(
        added: Int,
        removedPending: Int,
        removedDelivered: Int
    ) -> Self {
        Self(
            added: added,
            removedPending: removedPending,
            removedDelivered: removedDelivered
        )
    }
}

public protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async throws -> NotificationAuthorizationStatus
    func pendingRequests() async throws -> [PendingNotificationRequestValue]
    func deliveredRequestIdentifiers() async throws -> Set<String>
    func removePendingRequests(withIdentifiers identifiers: [String]) async throws
    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws
    func add(_ request: NotificationRequestValue) async throws
    func requestAuthorization() async throws -> Bool
}

public protocol HealthCheckNotificationReconciling: Sendable {
    func reconcile(
        _ descriptors: [HealthCheckNotificationDescriptor]
    ) async throws -> NotificationReconciliationResult
}
