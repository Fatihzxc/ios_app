import Foundation

public enum TodayAlertPriority {
    public enum Kind: Equatable, Sendable {
        case activeSymptoms
        case ohp
        case deload
        case phase
        case bloodwork
        case measurement
    }

    public struct Candidate: Equatable, Sendable {
        public let sourceID: UUID
        public let kind: Kind
        public let date: Date?

        public init(sourceID: UUID, kind: Kind, date: Date? = nil) {
            self.sourceID = sourceID
            self.kind = kind
            self.date = date
        }
    }

    public struct Selection: Equatable, Sendable {
        public let primary: Candidate
        public let additionalCount: Int

        public init(primary: Candidate, additionalCount: Int) {
            self.primary = primary
            self.additionalCount = additionalCount
        }
    }

    public static func select(_ candidates: [Candidate]) -> Selection? {
        guard let primary = candidates.sorted(by: orderedBefore).first else { return nil }
        return Selection(primary: primary, additionalCount: candidates.count - 1)
    }

    private static func orderedBefore(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let lhsPriority = priority(lhs.kind)
        let rhsPriority = priority(rhs.kind)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        switch (lhs.date, rhs.date) {
        case let (.some(lhsDate), .some(rhsDate)) where lhsDate != rhsDate:
            return lhsDate < rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.sourceID.uuidString < rhs.sourceID.uuidString
        }
    }

    private static func priority(_ kind: Kind) -> Int {
        switch kind {
        case .activeSymptoms: 0
        case .ohp: 1
        case .deload: 2
        case .phase: 3
        case .bloodwork: 4
        case .measurement: 5
        }
    }
}
