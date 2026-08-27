import DesignSystem
import Foundation
import Observation

public enum HealthChecksLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

public enum HealthChecksMutationPhase: Equatable, Sendable {
    case idle
    case saving
    case saved
    case failed
}

@MainActor
@Observable
public final class HealthChecksViewModel {
    public private(set) var snapshots: [HealthCheckReminderSnapshot] = []
    public private(set) var loadPhase: HealthChecksLoadPhase = .idle
    public private(set) var mutationPhase: HealthChecksMutationPhase = .idle
    public private(set) var lastCompletion: HealthCheckCompletionMutation?

    public var failedCompletionID: UUID? {
        guard case let .saveFailed(requestID) = mutationMachine.phase,
              pendingCompletion?.requestID == requestID else { return nil }
        return pendingCompletion?.id
    }

    public var hasFailedUndo: Bool {
        if case .undoFailed = mutationMachine.phase { return true }
        return false
    }

    @ObservationIgnored
    private let repository: any HealthChecksRepository
    @ObservationIgnored
    private let makeRequestID: @MainActor () -> UUID
    @ObservationIgnored
    private var mutationMachine =
        QuickEntryMutationStateMachine<HealthCheckCompletionUndoToken>()
    @ObservationIgnored
    private var pendingCompletion: PendingCompletion?
    @ObservationIgnored
    private var loadGeneration: UInt64 = 0

    public init(
        repository: any HealthChecksRepository,
        makeRequestID: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        self.repository = repository
        self.makeRequestID = makeRequestID
    }

    public func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadPhase = .loading
        do {
            let values = try await repository.fetchReminders()
            guard generation == loadGeneration else { return }
            snapshots = values.sorted(by: HealthCheckReminderOrdering.dueFirst)
            loadPhase = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            loadPhase = .failed
        }
    }

    @discardableResult
    public func complete(_ snapshot: HealthCheckReminderSnapshot) async -> Bool {
        let requestID = makeRequestID()
        guard let attempt = mutationMachine.beginSave(requestID: requestID) else {
            return false
        }
        let request = PendingCompletion(
            requestID: requestID,
            id: snapshot.id,
            expectedUpdatedAt: snapshot.updatedAt
        )
        pendingCompletion = request
        publishMutationPhase()
        return await performCompletion(request, attempt: attempt)
    }

    @discardableResult
    public func retryCompletion(
        for snapshot: HealthCheckReminderSnapshot
    ) async -> Bool {
        guard let pendingCompletion,
              pendingCompletion.id == snapshot.id,
              pendingCompletion.expectedUpdatedAt == snapshot.updatedAt,
              let attempt = mutationMachine.retrySave() else { return false }
        publishMutationPhase()
        return await performCompletion(pendingCompletion, attempt: attempt)
    }

    @discardableResult
    public func undoLastCompletion() async -> Bool {
        guard case let .saved(undoToken) = mutationMachine.phase,
              let attempt = mutationMachine.beginUndo(
                  requestID: makeRequestID()
              ) else { return false }
        publishMutationPhase()
        return await performUndo(undoToken, attempt: attempt)
    }

    @discardableResult
    public func retryUndo() async -> Bool {
        guard case let .undoFailed(_, undoToken) = mutationMachine.phase,
              let attempt = mutationMachine.retryUndo() else { return false }
        publishMutationPhase()
        return await performUndo(undoToken, attempt: attempt)
    }

    private func performCompletion(
        _ request: PendingCompletion,
        attempt: QuickEntryMutationAttempt
    ) async -> Bool {
        do {
            let mutation = try await repository.completeReminder(
                id: request.id,
                expectedUpdatedAt: request.expectedUpdatedAt
            )
            guard pendingCompletion == request,
                  mutationMachine.completeSave(
                      attempt,
                      undoToken: mutation.undoToken
                  ) else { return false }
            var updated = snapshots.filter { $0.id != mutation.completed.id }
            updated.append(mutation.completed)
            if let successor = mutation.successor {
                updated.removeAll { $0.id == successor.id }
                updated.append(successor)
            }
            snapshots = updated.sorted(by: HealthCheckReminderOrdering.dueFirst)
            lastCompletion = mutation
            publishMutationPhase()
            return true
        } catch {
            guard pendingCompletion == request,
                  mutationMachine.failSave(attempt) else { return false }
            publishMutationPhase()
            return false
        }
    }

    private func performUndo(
        _ undoToken: HealthCheckCompletionUndoToken,
        attempt: QuickEntryMutationAttempt
    ) async -> Bool {
        do {
            let restored = try await repository.undoCompletion(undoToken)
            guard mutationMachine.completeUndo(attempt) else { return false }
            snapshots.removeAll {
                $0.id == restored.id || $0.id == undoToken.successorID
            }
            snapshots.append(restored)
            snapshots.sort(by: HealthCheckReminderOrdering.dueFirst)
            lastCompletion = nil
            pendingCompletion = nil
            publishMutationPhase()
            return true
        } catch {
            guard mutationMachine.failUndo(attempt) else { return false }
            publishMutationPhase()
            return false
        }
    }

    private func publishMutationPhase() {
        switch mutationMachine.phase {
        case .idle:
            mutationPhase = .idle
        case .saving, .undoing:
            mutationPhase = .saving
        case .saved:
            mutationPhase = .saved
        case .saveFailed, .undoFailed:
            mutationPhase = .failed
        }
    }

    private struct PendingCompletion: Equatable {
        let requestID: UUID
        let id: UUID
        let expectedUpdatedAt: Date
    }
}
