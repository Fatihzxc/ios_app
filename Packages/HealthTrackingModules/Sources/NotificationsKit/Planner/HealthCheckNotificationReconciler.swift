import Foundation

public actor HealthCheckNotificationReconciler: HealthCheckNotificationReconciling {
    private let center: any NotificationCenterClient
    private let planner: HealthCheckNotificationPlanner
    private let now: @Sendable () -> Date

    public init(
        center: any NotificationCenterClient,
        planner: HealthCheckNotificationPlanner = .init(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.center = center
        self.planner = planner
        self.now = now
    }

    public func reconcile(
        _ descriptors: [HealthCheckNotificationDescriptor]
    ) async throws -> NotificationReconciliationResult {
        let status = try await center.authorizationStatus()
        try Task.checkCancellation()
        let pending = try await center.pendingRequests()
        try Task.checkCancellation()
        let delivered = try await center.deliveredRequestIdentifiers()
        try Task.checkCancellation()

        let desiredRequests = planner.requests(for: descriptors).filter { request in
            guard !(request.deliveryDate <= now()) else { return false }
            return true
        }
        let desiredByIdentifier = Dictionary(
            uniqueKeysWithValues: desiredRequests.map { ($0.identifier, $0) }
        )
        let pendingByIdentifier = Dictionary(grouping: pending) { pending in
            pending.identifier
        }

        let removedPendingIDs: [String]
        switch status {
        case .authorized:
            removedPendingIDs = pendingByIdentifier.compactMap {
                identifier,
                pendingValues in
                guard Self.isOwned(identifier) else { return nil }
                guard pendingValues.count == 1 else { return identifier }
                let pending = pendingValues[0]
                guard let desired = desiredByIdentifier[identifier],
                      pending.request == desired else {
                    return identifier
                }
                return nil
            }.sorted()
        case .denied, .notDetermined:
            removedPendingIDs = pendingByIdentifier.keys
                .filter(Self.isOwned)
                .sorted()
        }

        let removedDeliveredIDs = delivered.filter(Self.isOwned).sorted()

        if !removedPendingIDs.isEmpty {
            try Task.checkCancellation()
            try await center.removePendingRequests(withIdentifiers: removedPendingIDs)
        }
        if !removedDeliveredIDs.isEmpty {
            try Task.checkCancellation()
            try await center.removeDeliveredRequests(withIdentifiers: removedDeliveredIDs)
        }

        var added = 0
        if status == .authorized {
            let removedPending = Set(removedPendingIDs)
            for request in desiredRequests where
                pendingByIdentifier[request.identifier]?.count != 1
                    || pendingByIdentifier[request.identifier]?[0].request != request
                    || removedPending.contains(request.identifier) {
                try Task.checkCancellation()
                try await center.add(request)
                added += 1
            }
        }

        return .converged(
            added: added,
            removedPending: removedPendingIDs.count,
            removedDelivered: removedDeliveredIDs.count
        )
    }

    private static func isOwned(_ identifier: String) -> Bool {
        identifier.hasPrefix("health-check-detail.v1.")
    }
}
