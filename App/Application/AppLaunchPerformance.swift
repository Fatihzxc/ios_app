import Foundation
import os

@MainActor
enum AppLaunchPerformance {
    static let startedAt = ProcessInfo.processInfo.systemUptime

    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "HealthTrackingApp",
        category: "LaunchPerformance"
    )
    private static let signpostID = OSSignpostID(log: log)
    private static var didBegin = false
    private static var didFinish = false

    static func beginIfNeeded() {
        _ = startedAt
        guard !didBegin else { return }
        didBegin = true
        os_signpost(
            .begin,
            log: log,
            name: "LaunchToToday",
            signpostID: signpostID
        )
    }

    static func finish(_ elapsed: TimeInterval) {
        guard didBegin, !didFinish else { return }
        didFinish = true
        os_signpost(
            .end,
            log: log,
            name: "LaunchToToday",
            signpostID: signpostID,
            "elapsed_seconds=%{public}.6f",
            elapsed
        )
    }
}
