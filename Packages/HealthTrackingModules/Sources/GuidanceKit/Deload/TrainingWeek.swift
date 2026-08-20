import Foundation

public enum TrainingWeek {
    public struct Input: Equatable, Sendable {
        public let programStartDate: Date
        public let completedSessionDates: [Date]

        public init(programStartDate: Date, completedSessionDates: [Date]) {
            self.programStartDate = programStartDate
            self.completedSessionDates = completedSessionDates
        }
    }

    public struct Decision: Equatable, Sendable {
        public let trainingWeekIndex: Int
        public let countedWeekStarts: [Date]

        public init(trainingWeekIndex: Int, countedWeekStarts: [Date]) {
            self.trainingWeekIndex = trainingWeekIndex
            self.countedWeekStarts = countedWeekStarts
        }
    }

    public static func resolve(_ input: Input, calendar: Calendar) -> Decision {
        let programStart = calendar.startOfDay(for: input.programStartDate)
        let weekStarts = Set(
            input.completedSessionDates.compactMap { completion -> Date? in
                guard completion >= programStart else { return nil }
                return calendar.dateInterval(of: .weekOfYear, for: completion)?.start
            }
        ).sorted()

        return Decision(
            trainingWeekIndex: max(1, weekStarts.count),
            countedWeekStarts: weekStarts
        )
    }
}
