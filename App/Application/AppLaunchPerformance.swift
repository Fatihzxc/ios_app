import Foundation
import os

@MainActor
enum AppLaunchPerformance {
    enum Checkpoint: String, CaseIterable {
        case environment
        case container
        case dependencyEntry
        case dependencyContext
        case dependencyRepository
        case dependencyRouting
        case dependencyViewModel
        case dependencies
        case seed
        case today
    }

    static let startedAt = ProcessInfo.processInfo.systemUptime

    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "HealthTrackingApp",
        category: "LaunchPerformance"
    )
    private static let signpostID = OSSignpostID(log: log)
    private static var didBegin = false
    private static var didFinish = false
    private static var checkpoints: [Checkpoint: TimeInterval] = [:]

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

    static func record(_ checkpoint: Checkpoint) {
        record(checkpoint, elapsed: max(0, ProcessInfo.processInfo.systemUptime - startedAt))
    }

    static func evidenceValue() -> String? {
        guard checkpoints.count == Checkpoint.allCases.count else { return nil }
        let values = Dictionary(
            uniqueKeysWithValues: Checkpoint.allCases.compactMap { checkpoint in
                checkpoints[checkpoint].map { (checkpoint.rawValue, $0) }
            }
        )
        guard values.count == Checkpoint.allCases.count,
              let data = try? JSONSerialization.data(
                  withJSONObject: values,
                  options: [.sortedKeys]
              ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func finish(_ elapsed: TimeInterval) {
        guard didBegin, !didFinish else { return }
        record(.today, elapsed: elapsed)
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

    private static func record(_ checkpoint: Checkpoint, elapsed: TimeInterval) {
        guard checkpoints[checkpoint] == nil else { return }
        checkpoints[checkpoint] = elapsed
    }
}
