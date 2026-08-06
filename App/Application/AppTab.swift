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
