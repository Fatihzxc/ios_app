import Foundation
import SwiftUI

#if DEBUG
enum AppUITestScenario: String {
    case seeded
    case emptyOnce = "empty-once"
    case errorOnce = "error-once"
    case loading
    case fatalConfiguration = "fatal-configuration"
}

struct AppUITestLaunchConfiguration {
    enum Appearance: String {
        case light
        case dark

        var colorScheme: ColorScheme {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }
    }

    let scenario: AppUITestScenario
    let appearance: Appearance

    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard arguments.filter({ $0 == "-ui-testing" }).count == 1,
              let scenarioValue = uniqueValue(after: "-ui-test-scenario", in: arguments),
              let scenario = AppUITestScenario(rawValue: scenarioValue),
              let appearanceValue = uniqueValue(after: "-ui-test-appearance", in: arguments),
              let appearance = Appearance(rawValue: appearanceValue) else {
            return nil
        }

        return Self(scenario: scenario, appearance: appearance)
    }

    private static func uniqueValue(after flag: String, in arguments: [String]) -> String? {
        let indexes = arguments.indices.filter { arguments[$0] == flag }
        guard indexes.count == 1,
              let index = indexes.first,
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

enum AppUITestConfigurationError: Error {
    case forcedFatalConfiguration
}
#endif

enum AppLaunchEnvironment {
    static func resolve() throws -> AppEnvironment {
        let environment = try AppEnvironment.resolve()

        #if DEBUG
        if environment == .uiTesting,
           AppUITestLaunchConfiguration.resolve()?.scenario == .fatalConfiguration {
            throw AppUITestConfigurationError.forcedFatalConfiguration
        }
        #endif

        return environment
    }
}
