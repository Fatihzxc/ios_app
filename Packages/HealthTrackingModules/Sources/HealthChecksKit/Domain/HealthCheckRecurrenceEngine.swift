import CoreModels
import Foundation

public enum HealthCheckRecurrenceEngineError: Error, Equatable, Sendable {
    case invalidDate
}

public enum HealthCheckRecurrenceEngine {
    public static func nextDueDate(
        after dueDate: Date,
        recurrence: HealthCheckRecurrence,
        calendar: Calendar
    ) throws -> Date? {
        let monthDelta: Int
        switch recurrence {
        case .none:
            return nil
        case .monthly:
            monthDelta = 1
        case .quarterly:
            monthDelta = 3
        case .yearly:
            monthDelta = 12
        }

        let source = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: dueDate
        )
        guard let sourceYear = source.year,
              let sourceMonth = source.month,
              let sourceDay = source.day else {
            throw HealthCheckRecurrenceEngineError.invalidDate
        }

        let zeroBasedMonth = sourceMonth - 1 + monthDelta
        let targetYear = sourceYear + zeroBasedMonth / 12
        let targetMonth = zeroBasedMonth % 12 + 1
        var firstOfMonth = DateComponents()
        firstOfMonth.calendar = calendar
        firstOfMonth.timeZone = calendar.timeZone
        firstOfMonth.year = targetYear
        firstOfMonth.month = targetMonth
        firstOfMonth.day = 1
        guard let firstDate = calendar.date(from: firstOfMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: firstDate) else {
            throw HealthCheckRecurrenceEngineError.invalidDate
        }

        var target = DateComponents()
        target.calendar = calendar
        target.timeZone = calendar.timeZone
        target.year = targetYear
        target.month = targetMonth
        target.day = min(sourceDay, dayRange.count)
        target.hour = source.hour
        target.minute = source.minute
        target.second = source.second
        target.nanosecond = source.nanosecond
        guard let result = calendar.date(from: target) else {
            throw HealthCheckRecurrenceEngineError.invalidDate
        }
        return result
    }
}
