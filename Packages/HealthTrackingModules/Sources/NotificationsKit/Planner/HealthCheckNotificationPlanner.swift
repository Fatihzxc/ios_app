import Foundation

public struct HealthCheckNotificationPlanner: Sendable {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    public static func requestIdentifier(for reminderID: UUID) -> String {
        "health-check-detail.v1.\(reminderID.uuidString.lowercased())"
    }

    public func request(
        for descriptor: HealthCheckNotificationDescriptor
    ) -> NotificationRequestValue? {
        guard descriptor.isEligible else { return nil }
        let normalizedDeliveryDate = Date(
            timeIntervalSince1970:
                descriptor.dueDate.timeIntervalSince1970.rounded(.up)
        )
        return NotificationRequestValue(
            identifier: Self.requestIdentifier(for: descriptor.reminderID),
            title: localized("notifications.health-check.title"),
            body: localized("notifications.health-check.body"),
            deliveryDate: normalizedDeliveryDate,
            userInfo: HealthCheckNotificationRouteCodec.encode(
                .healthCheckDetail(reminderID: descriptor.reminderID)
            )
        )
    }

    public func requests(
        for descriptors: [HealthCheckNotificationDescriptor]
    ) -> [NotificationRequestValue] {
        var latestEligibleByID: [UUID: HealthCheckNotificationDescriptor] = [:]
        for descriptor in descriptors where descriptor.isEligible {
            if let current = latestEligibleByID[descriptor.reminderID],
               current.dueDate > descriptor.dueDate {
                continue
            }
            latestEligibleByID[descriptor.reminderID] = descriptor
        }
        return latestEligibleByID.values
            .compactMap { request(for: $0) }
            .sorted { $0.identifier < $1.identifier }
    }

    private func localized(_ key: String) -> String {
        let languageCode = locale.language.languageCode?.identifier
        if let languageCode,
           let path = Bundle.module.path(
               forResource: languageCode,
               ofType: "lproj"
           ),
           let localizedBundle = Bundle(path: path) {
            return localizedBundle.localizedString(
                forKey: key,
                value: key,
                table: nil
            )
        }
        return Bundle.module.localizedString(
            forKey: key,
            value: key,
            table: nil
        )
    }
}
