import Foundation

public enum ReportDateRangePreset: String, CaseIterable, Equatable, Sendable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
}

public struct ReportDateInterval: Equatable, Sendable {
    public let start: Date
    public let endExclusive: Date

    public init(start: Date, endExclusive: Date) {
        self.start = start
        self.endExclusive = endExclusive
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < endExclusive
    }
}

public enum ReportDateRangeError: Error, Equatable, Sendable {
    case unrepresentableBoundary
}

public enum ReportDateRangeResolver {
    public static func resolve(
        _ preset: ReportDateRangePreset,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> ReportDateInterval {
        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        guard let endExclusive = calendar.date(
            byAdding: .day,
            value: 1,
            to: startOfReferenceDay
        ) else {
            throw ReportDateRangeError.unrepresentableBoundary
        }

        let component: Calendar.Component
        let amount: Int
        switch preset {
        case .oneMonth:
            component = .month
            amount = -1
        case .threeMonths:
            component = .month
            amount = -3
        case .sixMonths:
            component = .month
            amount = -6
        case .oneYear:
            component = .year
            amount = -1
        }

        guard let start = calendar.date(
            byAdding: component,
            value: amount,
            to: endExclusive
        ) else {
            throw ReportDateRangeError.unrepresentableBoundary
        }
        return ReportDateInterval(start: start, endExclusive: endExclusive)
    }
}
