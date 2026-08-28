@preconcurrency import UserNotifications
import Foundation

public struct NotificationSystemRequest: Equatable, Sendable {
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
        repeats: Bool
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.deliveryDate = deliveryDate
        self.userInfo = userInfo
        self.repeats = repeats
    }

    init(_ request: NotificationRequestValue) {
        self.init(
            identifier: request.identifier,
            title: request.title,
            body: request.body,
            deliveryDate: request.deliveryDate,
            userInfo: request.userInfo,
            repeats: request.repeats
        )
    }

    var value: NotificationRequestValue {
        NotificationRequestValue(
            identifier: identifier,
            title: title,
            body: body,
            deliveryDate: deliveryDate,
            userInfo: userInfo,
            repeats: repeats
        )
    }
}

public struct PendingNotificationSystemRequest: Equatable, Sendable {
    public let identifier: String
    public let request: NotificationSystemRequest?

    public init(identifier: String, request: NotificationSystemRequest?) {
        self.identifier = identifier
        self.request = request
    }
}

public protocol NotificationCenterSystemBackend: Sendable {
    func authorizationStatus() async throws -> NotificationAuthorizationStatus
    func pendingRequests() async throws -> [PendingNotificationSystemRequest]
    func deliveredRequestIdentifiers() async throws -> Set<String>
    func removePendingRequests(withIdentifiers identifiers: [String]) async throws
    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws
    func add(_ request: NotificationSystemRequest) async throws
    func requestAuthorization() async throws -> Bool
}

public actor SystemNotificationCenterAdapter: NotificationCenterClient {
    private let backend: any NotificationCenterSystemBackend

    public init(calendar: Calendar = .current) {
        backend = DefaultNotificationCenterSystemBackend(calendar: calendar)
    }

    init(calendar: Calendar, systemDriver: DefaultNotificationCenterSystemBackend.Driver) {
        backend = DefaultNotificationCenterSystemBackend(
            calendar: calendar,
            driver: systemDriver
        )
    }

    public init(backend: any NotificationCenterSystemBackend) {
        self.backend = backend
    }

    public func authorizationStatus() async throws -> NotificationAuthorizationStatus {
        try await backend.authorizationStatus()
    }

    public func pendingRequests() async throws -> [PendingNotificationRequestValue] {
        try await backend.pendingRequests().map { pending in
            PendingNotificationRequestValue(
                identifier: pending.identifier,
                request: pending.request?.value
            )
        }
    }

    public func deliveredRequestIdentifiers() async throws -> Set<String> {
        try await backend.deliveredRequestIdentifiers()
    }

    public func removePendingRequests(
        withIdentifiers identifiers: [String]
    ) async throws {
        try await backend.removePendingRequests(withIdentifiers: identifiers)
    }

    public func removeDeliveredRequests(
        withIdentifiers identifiers: [String]
    ) async throws {
        try await backend.removeDeliveredRequests(withIdentifiers: identifiers)
    }

    public func add(_ request: NotificationRequestValue) async throws {
        try await backend.add(NotificationSystemRequest(request))
    }

    public func requestAuthorization() async throws -> Bool {
        try await backend.requestAuthorization()
    }
}

struct DefaultNotificationCenterSystemBackend: NotificationCenterSystemBackend,
    @unchecked Sendable {
    struct LiveOperations: @unchecked Sendable {
        let authorizationStatus: @Sendable () async throws -> UNAuthorizationStatus
        let pendingRequests: @Sendable () async throws -> [UNNotificationRequest]
        let deliveredRequestIdentifiers: @Sendable () async throws -> [String]
        let removePendingRequests: @Sendable ([String]) async throws -> Void
        let removeDeliveredRequests: @Sendable ([String]) async throws -> Void
        let add: @Sendable (UNNotificationRequest) async throws -> Void
        let requestAuthorization: @Sendable () async throws -> Bool

        static let currentCenter: @Sendable () -> UNUserNotificationCenter = {
            .current()
        }

        static func system(
            centerProvider: @escaping @Sendable () -> UNUserNotificationCenter =
                currentCenter
        ) -> LiveOperations {
            LiveOperations(
                authorizationStatus: {
                    let center = centerProvider()
                    let settings = await center.notificationSettings()
                    return settings.authorizationStatus
                },
                pendingRequests: {
                    let center = centerProvider()
                    let pending = await center.pendingNotificationRequests()
                    return pending
                },
                deliveredRequestIdentifiers: {
                    let center = centerProvider()
                    let delivered = await center.deliveredNotifications()
                    return delivered.map { $0.request.identifier }
                },
                removePendingRequests: { identifiers in
                    let center = centerProvider()
                    center.removePendingNotificationRequests(withIdentifiers: identifiers)
                },
                removeDeliveredRequests: { identifiers in
                    let center = centerProvider()
                    center.removeDeliveredNotifications(withIdentifiers: identifiers)
                },
                add: { systemRequest in
                    let center = centerProvider()
                    try await center.add(systemRequest)
                },
                requestAuthorization: {
                    let center = centerProvider()
                    let granted = try await center.requestAuthorization(options: [.alert, .sound])
                    return granted
                }
            )
        }
    }

    struct Driver: @unchecked Sendable {
        let authorizationStatus: @Sendable () async throws -> UNAuthorizationStatus
        let pendingRequests: @Sendable () async throws -> [UNNotificationRequest]
        let deliveredRequestIdentifiers: @Sendable () async throws -> [String]
        let removePendingRequests: @Sendable ([String]) async throws -> Void
        let removeDeliveredRequests: @Sendable ([String]) async throws -> Void
        let add: @Sendable (UNNotificationRequest) async throws -> Void
        let requestAuthorization: @Sendable () async throws -> Bool

        static func live(operations: LiveOperations = .system()) -> Driver {
            Driver(
                authorizationStatus: operations.authorizationStatus,
                pendingRequests: operations.pendingRequests,
                deliveredRequestIdentifiers: operations.deliveredRequestIdentifiers,
                removePendingRequests: operations.removePendingRequests,
                removeDeliveredRequests: operations.removeDeliveredRequests,
                add: operations.add,
                requestAuthorization: operations.requestAuthorization
            )
        }
    }

    struct UserNotificationProjection: Equatable, Sendable {
        let identifier: String
        let title: String
        let body: String
        let userInfo: [String: String]
        let dateComponents: DateComponents
        let repeats: Bool
    }

    private let calendar: Calendar
    private let driver: Driver

    init(calendar: Calendar = .current, driver: Driver = .live()) {
        self.calendar = calendar
        self.driver = driver
    }

    func authorizationStatus() async throws -> NotificationAuthorizationStatus {
        let rawStatus = try await driver.authorizationStatus()
        return Self.notificationAuthorizationStatus(from: rawStatus)
    }

    func pendingRequests() async throws -> [PendingNotificationSystemRequest] {
        let pending = try await driver.pendingRequests()
        return pending.map {
            Self.pendingSystemRequest(from: $0, calendar: calendar)
        }
    }

    func deliveredRequestIdentifiers() async throws -> Set<String> {
        Set(try await driver.deliveredRequestIdentifiers())
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async throws {
        try await driver.removePendingRequests(identifiers)
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws {
        try await driver.removeDeliveredRequests(identifiers)
    }

    func add(_ request: NotificationSystemRequest) async throws {
        let systemRequest = Self.makeUserNotificationRequest(
            from: request,
            calendar: calendar
        )
        try await driver.add(systemRequest)
    }

    func requestAuthorization() async throws -> Bool {
        try await driver.requestAuthorization()
    }

    static func makeUserNotificationRequest(
        from request: NotificationSystemRequest,
        calendar: Calendar
    ) -> UNNotificationRequest {
        let projection = request.userNotificationProjection(calendar: calendar)
        let content = UNMutableNotificationContent()
        content.title = projection.title
        content.body = projection.body
        content.userInfo = projection.userInfo
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: projection.dateComponents,
            repeats: projection.repeats
        )
        return UNNotificationRequest(
            identifier: projection.identifier,
            content: content,
            trigger: trigger
        )
    }

    static func pendingSystemRequest(
        from request: UNNotificationRequest,
        calendar: Calendar
    ) -> PendingNotificationSystemRequest {
        guard let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger,
              let deliveryDate = calendar.date(from: calendarTrigger.dateComponents),
              let userInfo = request.content.userInfo as? [String: String] else {
            return PendingNotificationSystemRequest(
                identifier: request.identifier,
                request: nil
            )
        }
        return PendingNotificationSystemRequest(
            identifier: request.identifier,
            request: NotificationSystemRequest(
                identifier: request.identifier,
                title: request.content.title,
                body: request.content.body,
                deliveryDate: deliveryDate,
                userInfo: userInfo,
                repeats: calendarTrigger.repeats
            )
        )
    }

    static func notificationAuthorizationStatus(
        from status: UNAuthorizationStatus
    ) -> NotificationAuthorizationStatus {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}

extension NotificationSystemRequest {
    func userNotificationProjection(
        calendar: Calendar
    ) -> DefaultNotificationCenterSystemBackend.UserNotificationProjection {
        DefaultNotificationCenterSystemBackend.UserNotificationProjection(
            identifier: identifier,
            title: title,
            body: body,
            userInfo: userInfo,
            dateComponents: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second, .timeZone],
                from: deliveryDate
            ),
            repeats: repeats
        )
    }
}
