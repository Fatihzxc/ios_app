import Foundation

public enum OHPSafetyGate {
    public enum SymptomResponse: Equatable, Sendable {
        case notAsked
        case symptomFree
        case symptomsPresent
        case uncertain
    }

    public enum EntryVariant: String, Equatable, Sendable {
        case seatedNeutral = "seated-neutral"
        case standingNeutral = "standing-neutral"
        case standingStandard = "standing-standard"
    }

    public enum Alternative: String, Equatable, Sendable {
        case halfKneelingDBPress = "half-kneeling-db-press"
    }

    public struct PreviousSession: Equatable, Sendable {
        public let id: UUID
        public let response: SymptomResponse

        public init(id: UUID, response: SymptomResponse) {
            self.id = id
            self.response = response
        }
    }

    public struct Input: Equatable, Sendable {
        public let trainingWeekIndex: Int
        public let previousSession: PreviousSession?
        public let currentSymptomsPresent: Bool

        public init(
            trainingWeekIndex: Int,
            previousSession: PreviousSession?,
            currentSymptomsPresent: Bool
        ) {
            self.trainingWeekIndex = trainingWeekIndex
            self.previousSession = previousSession
            self.currentSymptomsPresent = currentSymptomsPresent
        }
    }

    public enum LoadIncreaseBlockReason: Equatable, Sendable {
        case firstSession
        case previousResponseRequired
        case previousSymptomsPresent
        case previousResponseUncertain
        case currentSymptomsPresent
    }

    public enum LoadIncreasePolicy: Equatable, Sendable {
        case allowed
        case blocked(LoadIncreaseBlockReason)
    }

    public struct PriorSessionQuestion: Equatable, Sendable {
        public let sessionID: UUID

        public init(sessionID: UUID) {
            self.sessionID = sessionID
        }
    }

    public struct SafetyStop: Equatable, Sendable {
        public let alternative: Alternative

        public init(alternative: Alternative) {
            self.alternative = alternative
        }
    }

    public struct Decision: Equatable, Sendable {
        public let entryVariant: EntryVariant
        public let loadIncreasePolicy: LoadIncreasePolicy
        public let priorSessionQuestion: PriorSessionQuestion?
        public let safetyStop: SafetyStop?

        public init(
            entryVariant: EntryVariant,
            loadIncreasePolicy: LoadIncreasePolicy,
            priorSessionQuestion: PriorSessionQuestion?,
            safetyStop: SafetyStop?
        ) {
            self.entryVariant = entryVariant
            self.loadIncreasePolicy = loadIncreasePolicy
            self.priorSessionQuestion = priorSessionQuestion
            self.safetyStop = safetyStop
        }
    }

    public enum DataError: Equatable, Sendable {
        case trainingWeekIndexOutOfRange
    }

    public enum Outcome: Equatable, Sendable {
        case decision(Decision)
        case invalid(DataError)
    }

    public static func resolve(_ input: Input) -> Outcome {
        guard input.trainingWeekIndex >= 1 else {
            return .invalid(.trainingWeekIndexOutOfRange)
        }

        let variant = entryVariant(for: input.trainingWeekIndex)
        if input.currentSymptomsPresent {
            return .decision(
                Decision(
                    entryVariant: variant,
                    loadIncreasePolicy: .blocked(.currentSymptomsPresent),
                    priorSessionQuestion: nil,
                    safetyStop: SafetyStop(alternative: .halfKneelingDBPress)
                )
            )
        }

        guard let previousSession = input.previousSession else {
            return .decision(
                Decision(
                    entryVariant: variant,
                    loadIncreasePolicy: .blocked(.firstSession),
                    priorSessionQuestion: nil,
                    safetyStop: nil
                )
            )
        }

        switch previousSession.response {
        case .notAsked:
            return .decision(
                Decision(
                    entryVariant: variant,
                    loadIncreasePolicy: .blocked(.previousResponseRequired),
                    priorSessionQuestion: PriorSessionQuestion(
                        sessionID: previousSession.id
                    ),
                    safetyStop: nil
                )
            )
        case .symptomFree:
            return .decision(
                Decision(
                    entryVariant: variant,
                    loadIncreasePolicy: .allowed,
                    priorSessionQuestion: nil,
                    safetyStop: nil
                )
            )
        case .symptomsPresent:
            return .decision(
                Decision(
                    entryVariant: variant,
                    loadIncreasePolicy: .blocked(.previousSymptomsPresent),
                    priorSessionQuestion: nil,
                    safetyStop: nil
                )
            )
        case .uncertain:
            return .decision(
                Decision(
                    entryVariant: variant,
                    loadIncreasePolicy: .blocked(.previousResponseUncertain),
                    priorSessionQuestion: nil,
                    safetyStop: nil
                )
            )
        }
    }

    private static func entryVariant(for week: Int) -> EntryVariant {
        switch week {
        case 1...2:
            .seatedNeutral
        case 3...4:
            .standingNeutral
        default:
            .standingStandard
        }
    }
}
