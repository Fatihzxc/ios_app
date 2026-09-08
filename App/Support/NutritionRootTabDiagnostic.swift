// Temporary diagnostic branch only. Not part of M4 acceptance.
// The fixed-path Stage-A privacy scan does not cover this file; independently
// review its closed payload types and remove it with all temporary instrumentation.
#if DEBUG
import Foundation
import os

@MainActor
enum NutritionRootTabDiagnostic {
    enum Event: String {
        case rootAppear = "root-appear"
        case rootDisappear = "root-disappear"
        case selectionChange = "selection-change"
    }

    private static let log = OSLog(
        subsystem: "com.fatihzxc.HealthTrackingApp.NutritionDiagnostic",
        category: "RootTab"
    )
    private static var sequence = 0

    static func record(_ event: Event, selected: AppTab, previous: AppTab? = nil) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ui-testing"),
              arguments.contains("-nutrition-quick-add-diagnostics"),
              sequence < 512 else { return }
        sequence += 1
        let flow = arguments.contains("-ui-test-store-identifier") ? "persistent" : "transient"
        let message = "scope=root seq=\(sequence) flow=\(flow) "
            + "selected=\(selected.rawValue) previous=\(previous?.rawValue ?? "none") event=\(event.rawValue)"
        os_log("%{public}@", log: log, type: .default, message)
    }
}
#endif
