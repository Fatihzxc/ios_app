import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case training
    case nutrition
    case progress
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: String(localized: "tab.today")
        case .training: String(localized: "tab.training")
        case .nutrition: String(localized: "tab.nutrition")
        case .progress: String(localized: "tab.progress")
        case .settings: String(localized: "tab.settings")
        }
    }

    var hint: String {
        switch self {
        case .today: String(localized: "tab.today.hint")
        case .training: String(localized: "tab.training.hint")
        case .nutrition: String(localized: "tab.nutrition.hint")
        case .progress: String(localized: "tab.progress.hint")
        case .settings: String(localized: "tab.settings.hint")
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .training: "dumbbell"
        case .nutrition: "fork.knife"
        case .progress: "chart.bar"
        case .settings: "gearshape"
        }
    }

    var tabIdentifier: String { "tab.\(rawValue)" }
}
