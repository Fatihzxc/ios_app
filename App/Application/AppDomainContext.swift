import Foundation

enum AppDomainContext {
    static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        #if DEBUG
        calendar.timeZone = AppUITestLaunchConfiguration.resolve()?.fixedTimeZone
            ?? .autoupdatingCurrent
        #else
        calendar.timeZone = .autoupdatingCurrent
        #endif
        return calendar
    }

    @MainActor
    static func now() -> Date {
        #if DEBUG
        if let configuration = AppUITestLaunchConfiguration.resolve(),
           let fixedNow = configuration.fixedNow {
            return fixedNow
        }
        #endif
        return .now
    }
}
