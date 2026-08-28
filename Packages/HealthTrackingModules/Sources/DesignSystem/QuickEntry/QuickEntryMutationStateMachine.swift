import Foundation

public enum QuickEntryMutationKind: String, Equatable, Sendable {
    case save
    case undo
}

public struct QuickEntryMutationAttempt: Equatable, Sendable {
    public let requestID: UUID
    public let generation: UInt64
    public let kind: QuickEntryMutationKind

    public init(
        requestID: UUID,
        generation: UInt64,
        kind: QuickEntryMutationKind
    ) {
        self.requestID = requestID
        self.generation = generation
        self.kind = kind
    }
}

public enum QuickEntryMutationPhase<UndoToken>: Equatable, Sendable
where UndoToken: Equatable & Sendable {
    case idle
    case saving(QuickEntryMutationAttempt)
    case saved(undoToken: UndoToken)
    case saveFailed(requestID: UUID)
    case undoing(attempt: QuickEntryMutationAttempt, undoToken: UndoToken)
    case undoFailed(requestID: UUID, undoToken: UndoToken)
}

public struct QuickEntryMutationStateMachine<UndoToken>: Equatable, Sendable
where UndoToken: Equatable & Sendable {
    public private(set) var phase: QuickEntryMutationPhase<UndoToken>
    public private(set) var generation: UInt64

    public init() {
        phase = .idle
        generation = 0
    }

    @discardableResult
    public mutating func beginSave(requestID: UUID) -> QuickEntryMutationAttempt? {
        guard !hasMutationInFlight else {
            return nil
        }

        let attempt = makeAttempt(requestID: requestID, kind: .save)
        phase = .saving(attempt)
        return attempt
    }

    @discardableResult
    public mutating func retrySave() -> QuickEntryMutationAttempt? {
        guard case let .saveFailed(requestID) = phase else {
            return nil
        }

        let attempt = makeAttempt(requestID: requestID, kind: .save)
        phase = .saving(attempt)
        return attempt
    }

    @discardableResult
    public mutating func abandonFailedSave() -> Bool {
        guard case .saveFailed = phase else {
            return false
        }

        phase = .idle
        return true
    }

    @discardableResult
    public mutating func completeSave(
        _ attempt: QuickEntryMutationAttempt,
        undoToken: UndoToken
    ) -> Bool {
        guard case let .saving(currentAttempt) = phase,
              attempt.kind == .save,
              attempt == currentAttempt else {
            return false
        }

        phase = .saved(undoToken: undoToken)
        return true
    }

    @discardableResult
    public mutating func failSave(_ attempt: QuickEntryMutationAttempt) -> Bool {
        guard case let .saving(currentAttempt) = phase,
              attempt.kind == .save,
              attempt == currentAttempt else {
            return false
        }

        phase = .saveFailed(requestID: currentAttempt.requestID)
        return true
    }

    @discardableResult
    public mutating func beginUndo(requestID: UUID) -> QuickEntryMutationAttempt? {
        guard case let .saved(undoToken) = phase else {
            return nil
        }

        let attempt = makeAttempt(requestID: requestID, kind: .undo)
        phase = .undoing(attempt: attempt, undoToken: undoToken)
        return attempt
    }

    @discardableResult
    public mutating func retryUndo() -> QuickEntryMutationAttempt? {
        guard case let .undoFailed(requestID, undoToken) = phase else {
            return nil
        }

        let attempt = makeAttempt(requestID: requestID, kind: .undo)
        phase = .undoing(attempt: attempt, undoToken: undoToken)
        return attempt
    }

    @discardableResult
    public mutating func completeUndo(_ attempt: QuickEntryMutationAttempt) -> Bool {
        guard case let .undoing(currentAttempt, _) = phase,
              attempt.kind == .undo,
              attempt == currentAttempt else {
            return false
        }

        phase = .idle
        return true
    }

    @discardableResult
    public mutating func failUndo(_ attempt: QuickEntryMutationAttempt) -> Bool {
        guard case let .undoing(currentAttempt, undoToken) = phase,
              attempt.kind == .undo,
              attempt == currentAttempt else {
            return false
        }

        phase = .undoFailed(
            requestID: currentAttempt.requestID,
            undoToken: undoToken
        )
        return true
    }

    @discardableResult
    public mutating func expireUndo() -> Bool {
        switch phase {
        case .saved, .undoFailed:
            phase = .idle
            return true
        case .idle, .saving, .saveFailed, .undoing:
            return false
        }
    }

    private var hasMutationInFlight: Bool {
        switch phase {
        case .saving, .undoing:
            true
        case .idle, .saved, .saveFailed, .undoFailed:
            false
        }
    }

    private mutating func makeAttempt(
        requestID: UUID,
        kind: QuickEntryMutationKind
    ) -> QuickEntryMutationAttempt {
        precondition(generation < UInt64.max, "Quick-entry generation exhausted.")
        generation += 1
        return QuickEntryMutationAttempt(
            requestID: requestID,
            generation: generation,
            kind: kind
        )
    }
}
