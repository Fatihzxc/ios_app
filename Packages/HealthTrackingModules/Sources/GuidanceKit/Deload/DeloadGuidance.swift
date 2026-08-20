import Foundation

public enum DeloadGuidance {
    public enum Status: Equatable, Sendable {
        case none
        case recommended
        case active
        case skipped
    }

    public enum Reason: Equatable, Sendable {
        case scheduled
        case reactive(exerciseID: UUID)
    }

    public enum Action: Equatable, Sendable {
        case accepted
        case stay
        case techniqueReview
        case skipped
    }

    public struct WorkingSet: Equatable, Sendable {
        public let setIndex: Int
        public let weightKg: Double?
        public let reps: Int?
        public let isWarmupSet: Bool

        public init(
            setIndex: Int,
            weightKg: Double?,
            reps: Int?,
            isWarmupSet: Bool
        ) {
            self.setIndex = setIndex
            self.weightKg = weightKg
            self.reps = reps
            self.isWarmupSet = isWarmupSet
        }
    }

    public struct CompletedSession: Equatable, Sendable {
        public let id: UUID
        public let completedAt: Date
        public let perceivedRecovery: Int?
        public let sets: [WorkingSet]

        public init(
            id: UUID,
            completedAt: Date,
            perceivedRecovery: Int?,
            sets: [WorkingSet]
        ) {
            self.id = id
            self.completedAt = completedAt
            self.perceivedRecovery = perceivedRecovery
            self.sets = sets
        }
    }

    public struct ExerciseHistory: Equatable, Sendable {
        public let exerciseID: UUID
        public let sessions: [CompletedSession]

        public init(exerciseID: UUID, sessions: [CompletedSession]) {
            self.exerciseID = exerciseID
            self.sessions = sessions
        }
    }

    public struct Input: Equatable, Sendable {
        public let trainingWeekIndex: Int
        public let status: Status
        public let storedReason: Reason?
        public let histories: [ExerciseHistory]

        public init(
            trainingWeekIndex: Int,
            status: Status,
            storedReason: Reason?,
            histories: [ExerciseHistory]
        ) {
            self.trainingWeekIndex = trainingWeekIndex
            self.status = status
            self.storedReason = storedReason
            self.histories = histories
        }
    }

    public enum Recommendation: Equatable, Sendable {
        case none
        case recommended(Reason)
        case active(Reason)
    }

    public struct LoadRecommendation: Equatable, Sendable {
        public let defaultWeightKg: Double
        public let allowedFractionRange: ClosedRange<Double>

        public init(
            defaultWeightKg: Double,
            allowedFractionRange: ClosedRange<Double>
        ) {
            self.defaultWeightKg = defaultWeightKg
            self.allowedFractionRange = allowedFractionRange
        }
    }

    public struct StoredState: Equatable, Sendable {
        public let status: Status
        public let reason: Reason?
        public let deloadUpdatedAt: Date?
        public let lastDeloadSkippedAt: Date?
        public let lastAction: Action?

        public init(
            status: Status,
            reason: Reason?,
            deloadUpdatedAt: Date?,
            lastDeloadSkippedAt: Date?,
            lastAction: Action?
        ) {
            self.status = status
            self.reason = reason
            self.deloadUpdatedAt = deloadUpdatedAt
            self.lastDeloadSkippedAt = lastDeloadSkippedAt
            self.lastAction = lastAction
        }
    }

    public static func evaluate(_ input: Input) -> Recommendation {
        switch input.status {
        case .active:
            guard let storedReason = input.storedReason else { return .none }
            return .active(storedReason)
        case .skipped:
            return .none
        case .recommended:
            guard let storedReason = input.storedReason else { return .none }
            return .recommended(storedReason)
        case .none:
            break
        }

        guard input.trainingWeekIndex >= 1 else { return .none }
        if input.trainingWeekIndex.isMultiple(of: 5) {
            return .recommended(.scheduled)
        }

        let reactiveExerciseID = input.histories
            .sorted { $0.exerciseID.uuidString < $1.exerciseID.uuidString }
            .first(where: isReactiveStagnation)?
            .exerciseID
        guard let reactiveExerciseID else { return .none }
        return .recommended(.reactive(exerciseID: reactiveExerciseID))
    }

    public static func loadRecommendation(
        lastWeightKg: Double?,
        equipmentIncrementKg: Double
    ) -> LoadRecommendation? {
        guard let lastWeightKg,
              lastWeightKg.isFinite,
              lastWeightKg > 0,
              equipmentIncrementKg.isFinite,
              equipmentIncrementKg > 0 else {
            return nil
        }
        let halfLoad = lastWeightKg * 0.5
        let rounded = (halfLoad / equipmentIncrementKg).rounded() * equipmentIncrementKg
        return LoadRecommendation(
            defaultWeightKg: max(equipmentIncrementKg, rounded),
            allowedFractionRange: 0.4...0.5
        )
    }

    public static func transition(
        reason: Reason,
        action: Action,
        at date: Date
    ) -> StoredState {
        let status: Status = action == .accepted ? .active : .skipped
        return StoredState(
            status: status,
            reason: reason,
            deloadUpdatedAt: date,
            lastDeloadSkippedAt: action == .accepted ? nil : date,
            lastAction: action
        )
    }

    public static func rollover(
        _ state: StoredState,
        completedAt: Date,
        calendar: Calendar
    ) -> StoredState {
        guard state.status == .active || state.status == .skipped,
              let updatedAt = state.deloadUpdatedAt,
              localWeekStart(containing: updatedAt, calendar: calendar) !=
                  localWeekStart(containing: completedAt, calendar: calendar) else {
            return state
        }
        return StoredState(
            status: .none,
            reason: nil,
            deloadUpdatedAt: state.deloadUpdatedAt,
            lastDeloadSkippedAt: state.lastDeloadSkippedAt,
            lastAction: state.lastAction
        )
    }

    private struct Performance {
        let weightKg: Double
        let totalReps: Int
    }

    private static func isReactiveStagnation(_ history: ExerciseHistory) -> Bool {
        let sessions = history.sessions.sorted { lhs, rhs in
            if lhs.completedAt != rhs.completedAt {
                return lhs.completedAt > rhs.completedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard sessions.count >= 2,
              let newer = performance(sessions[0]),
              let older = performance(sessions[1]) else {
            return false
        }
        return newer.weightKg == older.weightKg && newer.totalReps <= older.totalReps
    }

    private static func performance(_ session: CompletedSession) -> Performance? {
        let workingSets = session.sets.filter { !$0.isWarmupSet }
        guard let first = workingSets.first,
              let weightKg = first.weightKg,
              weightKg.isFinite,
              weightKg > 0,
              workingSets.allSatisfy({ $0.weightKg == weightKg }),
              workingSets.allSatisfy({ ($0.reps ?? -1) >= 0 }) else {
            return nil
        }
        return Performance(
            weightKg: weightKg,
            totalReps: workingSets.compactMap(\.reps).reduce(0, +)
        )
    }

    private static func localWeekStart(
        containing date: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }
}
