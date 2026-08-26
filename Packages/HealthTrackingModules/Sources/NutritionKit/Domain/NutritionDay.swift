import Foundation

public enum NutritionDayResolutionError: Error, Equatable, Sendable {
    case calendarCouldNotResolveDay(date: Date)
}

public struct NutritionDayKey: Equatable, Hashable, Sendable {
    public let start: Date
    public let end: Date

    public init(containing date: Date, calendar: Calendar) throws {
        guard let interval = calendar.dateInterval(of: .day, for: date),
              interval.end > interval.start else {
            throw NutritionDayResolutionError.calendarCouldNotResolveDay(date: date)
        }
        start = interval.start
        end = interval.end
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
