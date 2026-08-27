import Foundation

enum AppDomainContext {
    static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    @MainActor
    static func now() -> Date {
        .now
    }
}
