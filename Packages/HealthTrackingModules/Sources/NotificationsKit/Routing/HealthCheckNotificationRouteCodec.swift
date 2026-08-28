import Foundation

public enum HealthCheckNotificationRoute: Equatable, Sendable {
    case healthCheckDetail(reminderID: UUID)
}

public enum HealthCheckNotificationRouteCodec {
    private static let version = "1"
    private static let route = "health-check-detail"
    private static let payloadKeys: Set<String> = ["version", "route", "reminderID"]

    public static func encode(
        _ route: HealthCheckNotificationRoute
    ) -> [String: String] {
        switch route {
        case let .healthCheckDetail(reminderID):
            return [
                "version": version,
                "route": Self.route,
                "reminderID": reminderID.uuidString.lowercased(),
            ]
        }
    }

    public static func decode(
        _ payload: [String: String]
    ) -> HealthCheckNotificationRoute? {
        guard Set(payload.keys) == payloadKeys,
              payload["version"] == version,
              payload["route"] == route,
              let rawIdentifier = payload["reminderID"],
              let reminderID = UUID(uuidString: rawIdentifier),
              rawIdentifier == reminderID.uuidString.lowercased() else {
            return nil
        }
        return .healthCheckDetail(reminderID: reminderID)
    }
}
