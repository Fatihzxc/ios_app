import Foundation

public enum NutritionManualEntryMode: Hashable, Sendable {
    case food
    case adhoc
}

public enum NutritionManualEntryPhase: Equatable, Sendable {
    case idle
    case loading
    case foodSelection
    case foodConfirmation
    case adhocEntry
    case saving
    case saveError
    case loadError
    case completed
}
