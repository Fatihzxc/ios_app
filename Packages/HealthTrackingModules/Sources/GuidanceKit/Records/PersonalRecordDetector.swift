import Foundation

public enum PersonalRecordDetector {
    public enum Measurement: Equatable, Sendable {
        case weightedReps(weightKg: Double?, reps: Int?)
        case bodyweightReps(reps: Int?, performedVariant: String?)
        case duration(seconds: Int?, performedVariant: String?)
        case steps(count: Int?, loadKg: Double?)
    }

    public struct Attempt: Equatable, Sendable {
        public let id: UUID
        public let completedAt: Date
        public let measurement: Measurement
        public let isWarmupSet: Bool

        public init(
            id: UUID,
            completedAt: Date,
            measurement: Measurement,
            isWarmupSet: Bool = false
        ) {
            self.id = id
            self.completedAt = completedAt
            self.measurement = measurement
            self.isWarmupSet = isWarmupSet
        }
    }

    public enum ExclusionReason: Equatable, Sendable {
        case warmupSet
        case invalidMeasurement
    }

    public enum Outcome: Equatable, Sendable {
        case excluded(ExclusionReason)
        case baseline(value: Double)
        case notRecord(value: Double, previousBest: Double)
        case newRecord(value: Double, previousBest: Double)
    }

    public struct Result: Equatable, Sendable {
        public let attemptID: UUID
        public let outcome: Outcome

        public init(attemptID: UUID, outcome: Outcome) {
            self.attemptID = attemptID
            self.outcome = outcome
        }
    }

    public static func evaluate(_ attempts: [Attempt]) -> [Result] {
        var bestByGroup: [ComparisonGroup: Best] = [:]

        return attempts
            .sorted(by: chronologicalOrder)
            .map { attempt in
                guard !attempt.isWarmupSet else {
                    return Result(
                        attemptID: attempt.id,
                        outcome: .excluded(.warmupSet)
                    )
                }
                guard let candidate = candidate(for: attempt.measurement) else {
                    return Result(
                        attemptID: attempt.id,
                        outcome: .excluded(.invalidMeasurement)
                    )
                }
                guard let previous = bestByGroup[candidate.group] else {
                    bestByGroup[candidate.group] = Best(
                        value: candidate.value,
                        loadKg: candidate.loadKg
                    )
                    return Result(
                        attemptID: attempt.id,
                        outcome: .baseline(value: candidate.value)
                    )
                }

                let isImprovement: Bool
                switch candidate.group {
                case .weighted:
                    isImprovement = EpleyEstimate.isImprovement(
                        candidate.value,
                        over: previous.value
                    )
                case .steps:
                    isImprovement = candidate.value > previous.value &&
                        candidate.loadKg >= previous.loadKg
                case .bodyweightReps, .duration:
                    isImprovement = candidate.value > previous.value
                }

                guard isImprovement else {
                    return Result(
                        attemptID: attempt.id,
                        outcome: .notRecord(
                            value: candidate.value,
                            previousBest: previous.value
                        )
                    )
                }
                bestByGroup[candidate.group] = Best(
                    value: candidate.value,
                    loadKg: candidate.loadKg
                )
                return Result(
                    attemptID: attempt.id,
                    outcome: .newRecord(
                        value: candidate.value,
                        previousBest: previous.value
                    )
                )
            }
    }

    private enum ComparisonGroup: Hashable {
        case weighted
        case bodyweightReps(String)
        case duration(String)
        case steps
    }

    private struct Candidate {
        let group: ComparisonGroup
        let value: Double
        let loadKg: Double
    }

    private struct Best {
        let value: Double
        let loadKg: Double
    }

    private static func candidate(for measurement: Measurement) -> Candidate? {
        switch measurement {
        case let .weightedReps(weightKg, reps):
            guard let value = EpleyEstimate.calculate(weightKg: weightKg, reps: reps) else {
                return nil
            }
            return Candidate(group: .weighted, value: value, loadKg: weightKg ?? 0)
        case let .bodyweightReps(reps, performedVariant):
            guard let reps, reps > 0 else { return nil }
            return Candidate(
                group: .bodyweightReps(normalizedVariant(performedVariant)),
                value: Double(reps),
                loadKg: 0
            )
        case let .duration(seconds, performedVariant):
            guard let seconds, seconds > 0 else { return nil }
            return Candidate(
                group: .duration(normalizedVariant(performedVariant)),
                value: Double(seconds),
                loadKg: 0
            )
        case let .steps(count, loadKg):
            let normalizedLoad = loadKg ?? 0
            guard let count,
                  count > 0,
                  normalizedLoad.isFinite,
                  normalizedLoad >= 0 else {
                return nil
            }
            return Candidate(
                group: .steps,
                value: Double(count),
                loadKg: normalizedLoad
            )
        }
    }

    private static func normalizedVariant(_ variant: String?) -> String {
        variant?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func chronologicalOrder(_ lhs: Attempt, _ rhs: Attempt) -> Bool {
        if lhs.completedAt != rhs.completedAt {
            return lhs.completedAt < rhs.completedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
