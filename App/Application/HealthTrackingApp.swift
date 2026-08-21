import SwiftUI

@main
struct HealthTrackingApp: App {
    private let bootstrapRuntime: AppBootstrapRuntime

    init() {
        AppLaunchPerformance.beginIfNeeded()
        bootstrapRuntime = Self.makeBootstrapRuntime()
    }

    var body: some Scene {
        WindowGroup {
            AppBootstrapView(runtime: bootstrapRuntime)
        }
    }

    private static func makeBootstrapRuntime() -> AppBootstrapRuntime {
        do {
            let environment = try AppLaunchEnvironment.resolve()
            AppLaunchPerformance.record(.environment)
            let prewarmer = AppDependencyPrewarmer(environment: environment)
            return AppBootstrapRuntime(
                resolveEnvironment: { environment },
                makeDependencies: { _ in
                    try await prewarmer.makeDependencies()
                },
                startsInitialLoad: true
            )
        } catch {
            return AppBootstrapRuntime(
                resolveEnvironment: { throw error },
                makeDependencies: { _ in throw error },
                startsInitialLoad: true
            )
        }
    }
}
