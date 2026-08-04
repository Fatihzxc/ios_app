import Foundation

public enum ReminderWeekday: Int, Codable, CaseIterable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
}

public enum ReminderSchedule: Equatable, Sendable {
    case oneTime(Date)
    case daily(hour: Int, minute: Int)
    case weekly(weekdays: Set<ReminderWeekday>, hour: Int, minute: Int)
    case intervalDays(count: Int, hour: Int, minute: Int)
}
