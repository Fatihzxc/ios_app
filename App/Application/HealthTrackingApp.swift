import SwiftUI

@main
struct HealthTrackingApp: App {
    init() {
        AppLaunchPerformance.beginIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
        }
    }
}
