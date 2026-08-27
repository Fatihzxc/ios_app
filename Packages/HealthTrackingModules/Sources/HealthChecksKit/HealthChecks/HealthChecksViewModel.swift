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

    @ObservationIgnored
    private let repository: any HealthChecksRepository
    @ObservationIgnored
    private var pendingCompletion: PendingCompletion?
    @ObservationIgnored
    private var loadGeneration: UInt64 = 0

    public init(repository: any HealthChecksRepository) {
        self.repository = repository
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

    public func complete(_ snapshot: HealthCheckReminderSnapshot) async {
        guard mutationPhase != .saving else { return }
        let request = PendingCompletion(
            id: snapshot.id,
            expectedUpdatedAt: snapshot.updatedAt
        )
        pendingCompletion = request
        mutationPhase = .saving
        await performCompletion(request)
    }

    public func retryCompletion() async {
        guard mutationPhase == .failed,
              let pendingCompletion else { return }
        mutationPhase = .saving
        await performCompletion(pendingCompletion)
    }

    private func performCompletion(_ request: PendingCompletion) async {
        do {
            let mutation = try await repository.completeReminder(
                id: request.id,
                expectedUpdatedAt: request.expectedUpdatedAt
            )
            guard mutationPhase == .saving,
                  pendingCompletion == request else { return }
            var updated = snapshots.filter { $0.id != mutation.completed.id }
            updated.append(mutation.completed)
            if let successor = mutation.successor {
                updated.removeAll { $0.id == successor.id }
                updated.append(successor)
            }
            snapshots = updated.sorted(by: HealthCheckReminderOrdering.dueFirst)
            lastCompletion = mutation
            mutationPhase = .saved
        } catch {
            guard mutationPhase == .saving,
                  pendingCompletion == request else { return }
            mutationPhase = .failed
        }
    }

    private struct PendingCompletion: Equatable {
        let id: UUID
        let expectedUpdatedAt: Date
    }
}
