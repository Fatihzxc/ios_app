import Foundation

public enum PhaseTransition {
    public struct Phase: Equatable, Sendable {
        public let id: UUID
        public let orderIndex: Int
        public let monthStart: Int
        public let monthEnd: Int
        public let entryCriteria: String
        public let milestone: String

        public init(
            id: UUID,
            orderIndex: Int,
            monthStart: Int,
            monthEnd: Int,
            entryCriteria: String,
            milestone: String
        ) {
            self.id = id
            self.orderIndex = orderIndex
            self.monthStart = monthStart
            self.monthEnd = monthEnd
            self.entryCriteria = entryCriteria
            self.milestone = milestone
        }
    }

    public enum ChecklistKind: Equatable, Sendable {
        case entryCriteria
        case milestone
    }

    public struct ChecklistItem: Equatable, Sendable {
        public let kind: ChecklistKind
        public let text: String

        public init(kind: ChecklistKind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    public struct Input: Equatable, Sendable {
        public let programStartDate: Date
        public let currentPhaseID: UUID
        public let phases: [Phase]
        public let evaluatedAt: Date

        public init(
            programStartDate: Date,
            currentPhaseID: UUID,
            phases: [Phase],
            evaluatedAt: Date
        ) {
            self.programStartDate = programStartDate
            self.currentPhaseID = currentPhaseID
            self.phases = phases
            self.evaluatedAt = evaluatedAt
        }
    }

    public struct Review: Equatable, Sendable {
        public let currentPhaseID: UUID
        public let nextPhaseID: UUID
        public let estimatedStart: Date
        public let checklist: [ChecklistItem]

        public init(
            currentPhaseID: UUID,
            nextPhaseID: UUID,
            estimatedStart: Date,
            checklist: [ChecklistItem]
        ) {
            self.currentPhaseID = currentPhaseID
            self.nextPhaseID = nextPhaseID
            self.estimatedStart = estimatedStart
            self.checklist = checklist
        }
    }

    public enum UnavailableReason: Equatable, Sendable {
        case currentPhaseMissing
        case invalidMonthRange
    }

    public enum Recommendation: Equatable, Sendable {
        case upcoming(Review)
        case review(Review)
        case finalPhase(currentPhaseID: UUID)
        case unavailable(UnavailableReason)
    }

    public enum Choice: Equatable, Sendable {
        case confirm
        case stay
    }

    public struct Resolution: Equatable, Sendable {
        public let selectedPhaseID: UUID
        public let phaseStartedAt: Date?
        public let dismissesPriority: Bool
        public let automaticReevaluationAt: Date?

        public init(
            selectedPhaseID: UUID,
            phaseStartedAt: Date?,
            dismissesPriority: Bool,
            automaticReevaluationAt: Date?
        ) {
            self.selectedPhaseID = selectedPhaseID
            self.phaseStartedAt = phaseStartedAt
            self.dismissesPriority = dismissesPriority
            self.automaticReevaluationAt = automaticReevaluationAt
        }
    }

    public static func evaluate(
        _ input: Input,
        calendar: Calendar = .current
    ) -> Recommendation {
        let phases = input.phases.sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex < rhs.orderIndex
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard let currentIndex = phases.firstIndex(where: { $0.id == input.currentPhaseID }) else {
            return .unavailable(.currentPhaseMissing)
        }
        guard phases.indices.contains(currentIndex + 1) else {
            return .finalPhase(currentPhaseID: input.currentPhaseID)
        }

        let next = phases[currentIndex + 1]
        guard next.monthStart >= 1,
              next.monthEnd >= next.monthStart,
              let estimatedStart = calendar.date(
                  byAdding: .month,
                  value: next.monthStart - 1,
                  to: input.programStartDate
              ) else {
            return .unavailable(.invalidMonthRange)
        }
        let review = Review(
            currentPhaseID: input.currentPhaseID,
            nextPhaseID: next.id,
            estimatedStart: estimatedStart,
            checklist: checklist(for: next)
        )
        return input.evaluatedAt >= estimatedStart ? .review(review) : .upcoming(review)
    }

    public static func resolve(
        _ review: Review,
        choice: Choice,
        at date: Date
    ) -> Resolution {
        switch choice {
        case .confirm:
            Resolution(
                selectedPhaseID: review.nextPhaseID,
                phaseStartedAt: date,
                dismissesPriority: true,
                automaticReevaluationAt: nil
            )
        case .stay:
            Resolution(
                selectedPhaseID: review.currentPhaseID,
                phaseStartedAt: nil,
                dismissesPriority: true,
                automaticReevaluationAt: nil
            )
        }
    }

    private static func checklist(for phase: Phase) -> [ChecklistItem] {
        let candidates: [(ChecklistKind, String)] = [
            (.entryCriteria, phase.entryCriteria),
            (.milestone, phase.milestone),
        ]
        return candidates.compactMap { kind, source in
            let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : ChecklistItem(kind: kind, text: text)
        }
    }
}
