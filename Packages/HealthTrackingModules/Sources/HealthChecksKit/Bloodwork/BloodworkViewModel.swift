import DesignSystem
import Foundation
import Observation

public enum BloodworkLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

public enum BloodworkEditPhase: Equatable, Sendable {
    case idle
    case saving
    case saved
    case failed
}

@MainActor
@Observable
public final class BloodworkViewModel {
    public private(set) var snapshots: [BloodworkResultSnapshot] = []
    public private(set) var loadPhase: BloodworkLoadPhase = .idle
    public private(set) var editPhase: BloodworkEditPhase = .idle
    public private(set) var lastCreatedSnapshot: BloodworkResultSnapshot?
    public private(set) var mutationPhase:
        QuickEntryMutationPhase<BloodworkCreationUndoToken> = .idle

    @ObservationIgnored
    private let repository: any BloodworkRepository
    @ObservationIgnored
    private let makeRequestID: @MainActor () -> UUID
    @ObservationIgnored
    private var mutationMachine =
        QuickEntryMutationStateMachine<BloodworkCreationUndoToken>()
    @ObservationIgnored
    private var pendingCreate: BloodworkResultInput?
    @ObservationIgnored
    private var loadGeneration: UInt64 = 0
    @ObservationIgnored
    private var editGeneration: UInt64 = 0

    public init(
        repository: any BloodworkRepository,
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
            let loaded = try await repository.fetchResults()
            guard generation == loadGeneration else { return }
            snapshots = loaded.sorted(by: BloodworkResultOrdering.newestFirst)
            loadPhase = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            loadPhase = .failed
        }
    }

    @discardableResult
    public func create(_ input: BloodworkResultInput) async -> Bool {
        guard let attempt = mutationMachine.beginSave(requestID: makeRequestID()) else {
            return false
        }
        lastCreatedSnapshot = nil
        pendingCreate = input
        publishMutationPhase()
        return await performCreate(input, attempt: attempt)
    }

    @discardableResult
    public func retryCreate() async -> Bool {
        guard let pendingCreate,
              let attempt = mutationMachine.retrySave() else {
            return false
        }
        publishMutationPhase()
        return await performCreate(pendingCreate, attempt: attempt)
    }

    @discardableResult
    public func undoLastCreate() async -> Bool {
        guard case let .saved(undoToken) = mutationMachine.phase,
              let attempt = mutationMachine.beginUndo(
                requestID: makeRequestID()
              ) else {
            return false
        }
        publishMutationPhase()
        return await performUndo(undoToken, attempt: attempt)
    }

    @discardableResult
    public func retryUndo() async -> Bool {
        guard case let .undoFailed(_, undoToken) = mutationMachine.phase,
              let attempt = mutationMachine.retryUndo() else {
            return false
        }
        publishMutationPhase()
        return await performUndo(undoToken, attempt: attempt)
    }

    @discardableResult
    public func retryFailedMutation() async -> Bool {
        switch mutationMachine.phase {
        case .saveFailed:
            return await retryCreate()
        case .undoFailed:
            return await retryUndo()
        case .idle, .saving, .saved, .undoing:
            return false
        }
    }

    @discardableResult
    public func update(
        _ snapshot: BloodworkResultSnapshot,
        input: BloodworkResultInput
    ) async -> Bool {
        editGeneration &+= 1
        let generation = editGeneration
        editPhase = .saving
        do {
            let updated = try await repository.updateResult(
                id: snapshot.id,
                expectedUpdatedAt: snapshot.updatedAt,
                input: input
            )
            guard generation == editGeneration else { return false }
            replaceSnapshot(updated)
            editPhase = .saved
            return true
        } catch {
            guard generation == editGeneration else { return false }
            editPhase = .failed
            return false
        }
    }

    @discardableResult
    public func delete(_ snapshot: BloodworkResultSnapshot) async -> Bool {
        editGeneration &+= 1
        let generation = editGeneration
        editPhase = .saving
        do {
            try await repository.deleteResult(
                id: snapshot.id,
                expectedUpdatedAt: snapshot.updatedAt
            )
            guard generation == editGeneration else { return false }
            snapshots.removeAll { $0.id == snapshot.id }
            editPhase = .saved
            return true
        } catch {
            guard generation == editGeneration else { return false }
            editPhase = .failed
            return false
        }
    }

    public func prepareForCreation() {
        guard !hasMutationInFlight else { return }
        _ = mutationMachine.expireUndo()
        pendingCreate = nil
        lastCreatedSnapshot = nil
        editGeneration &+= 1
        editPhase = .idle
        publishMutationPhase()
    }

    public func prepareForEditing() {
        guard !hasMutationInFlight else { return }
        _ = mutationMachine.expireUndo()
        pendingCreate = nil
        lastCreatedSnapshot = nil
        editGeneration &+= 1
        editPhase = .idle
        publishMutationPhase()
    }

    private var hasMutationInFlight: Bool {
        switch mutationMachine.phase {
        case .saving, .undoing:
            true
        case .idle, .saved, .saveFailed, .undoFailed:
            false
        }
    }

    private func performCreate(
        _ input: BloodworkResultInput,
        attempt: QuickEntryMutationAttempt
    ) async -> Bool {
        do {
            let mutation = try await repository.createResult(input)
            guard mutationMachine.completeSave(
                attempt,
                undoToken: mutation.undoToken
            ) else {
                return false
            }
            replaceSnapshot(mutation.snapshot)
            lastCreatedSnapshot = mutation.snapshot
            publishMutationPhase()
            return true
        } catch {
            guard mutationMachine.failSave(attempt) else { return false }
            publishMutationPhase()
            return false
        }
    }

    private func performUndo(
        _ token: BloodworkCreationUndoToken,
        attempt: QuickEntryMutationAttempt
    ) async -> Bool {
        do {
            try await repository.undoResultCreation(token)
            guard mutationMachine.completeUndo(attempt) else { return false }
            snapshots.removeAll { $0.id == token.id }
            lastCreatedSnapshot = nil
            pendingCreate = nil
            publishMutationPhase()
            return true
        } catch {
            guard mutationMachine.failUndo(attempt) else { return false }
            publishMutationPhase()
            return false
        }
    }

    private func replaceSnapshot(_ snapshot: BloodworkResultSnapshot) {
        snapshots = (snapshots.filter { $0.id != snapshot.id } + [snapshot])
            .sorted(by: BloodworkResultOrdering.newestFirst)
    }

    private func publishMutationPhase() {
        mutationPhase = mutationMachine.phase
    }
}
