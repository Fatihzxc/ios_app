import Foundation
import HealthChecksKit
import NotificationsKit
import PersistenceKit
import SwiftData

enum HealthCheckNotificationMapper {
    static func descriptors(
        from snapshots: [HealthCheckReminderSnapshot]
    ) -> [HealthCheckNotificationDescriptor] {
        snapshots.map { snapshot in
            HealthCheckNotificationDescriptor(
                reminderID: snapshot.id,
                dueDate: snapshot.dueDate,
                isEligible: snapshot.status == .pending
            )
        }
    }
}

@MainActor
final class HealthCheckNotificationLifecycleCoordinator {
    private let repository: any HealthChecksRepository
    private let reconciler: any HealthCheckNotificationReconciling
    private var didCompleteLaunchReconciliation = false
    private var generation: UInt64 = 0
    private var activeReconciliationTask:
        Task<NotificationReconciliationResult, Error>?
    private var activeReconciliationGeneration: UInt64?

    init(
        repository: any HealthChecksRepository,
        reconciler: any HealthCheckNotificationReconciling
    ) {
        self.repository = repository
        self.reconciler = reconciler
    }

    func reconcileAfterFirstMeaningfulTodayContent() async throws -> Bool {
        guard !didCompleteLaunchReconciliation else { return true }
        return try await reconcile(markLaunchComplete: true)
    }

    func reconcileAfterHealthCheckMutation() async throws {
        _ = try await reconcile(markLaunchComplete: false)
    }

    private func reconcile(markLaunchComplete: Bool) async throws -> Bool {
        generation += 1
        let currentGeneration = generation
        let previousReconciliationTask = activeReconciliationTask
        previousReconciliationTask?.cancel()
        if let previousReconciliationTask {
            _ = await previousReconciliationTask.result
        }
        guard generation == currentGeneration else { return false }

        let snapshots = try await repository.fetchReminders()
        guard generation == currentGeneration else { return false }
        let descriptors = HealthCheckNotificationMapper.descriptors(from: snapshots)
        let reconciliationTask = Task {
            try await reconciler.reconcile(descriptors)
        }
        activeReconciliationTask = reconciliationTask
        activeReconciliationGeneration = currentGeneration

        do {
            _ = try await reconciliationTask.value
            guard generation == currentGeneration else { return false }
            if markLaunchComplete {
                didCompleteLaunchReconciliation = true
            }
            clearActiveReconciliation(ifOwnedBy: currentGeneration)
            return true
        } catch {
            clearActiveReconciliation(ifOwnedBy: currentGeneration)
            throw error
        }
    }

    private func clearActiveReconciliation(ifOwnedBy generation: UInt64) {
        guard activeReconciliationGeneration == generation else { return }
        activeReconciliationTask = nil
        activeReconciliationGeneration = nil
    }
}

@MainActor
final class NotificationReconcilingHealthChecksRepository: HealthChecksRepository {
    private let repository: any HealthChecksRepository
    private let lifecycle: HealthCheckNotificationLifecycleCoordinator

    init(
        repository: any HealthChecksRepository,
        lifecycle: HealthCheckNotificationLifecycleCoordinator
    ) {
        self.repository = repository
        self.lifecycle = lifecycle
    }

    func fetchReminders() async throws -> [HealthCheckReminderSnapshot] {
        try await repository.fetchReminders()
    }

    func createReminder(
        _ input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        let created = try await repository.createReminder(input)
        try await reconcileAfterCommittedMutation()
        return created
    }

    func updateReminder(
        id: UUID,
        expectedUpdatedAt: Date,
        input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        let updated = try await repository.updateReminder(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt,
            input: input
        )
        try await reconcileAfterCommittedMutation()
        return updated
    }

    func deleteReminder(id: UUID, expectedUpdatedAt: Date) async throws {
        try await repository.deleteReminder(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt
        )
        try await reconcileAfterCommittedMutation()
    }

    func completeReminder(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws -> HealthCheckCompletionMutation {
        let completion = try await repository.completeReminder(
            id: id,
            expectedUpdatedAt: expectedUpdatedAt
        )
        try await reconcileAfterCommittedMutation()
        return completion
    }

    func undoCompletion(
        _ token: HealthCheckCompletionUndoToken
    ) async throws -> HealthCheckReminderSnapshot {
        let restored = try await repository.undoCompletion(token)
        try await reconcileAfterCommittedMutation()
        return restored
    }

    private func reconcileAfterCommittedMutation() async throws {
        do {
            try await lifecycle.reconcileAfterHealthCheckMutation()
        } catch {
            try await lifecycle.reconcileAfterHealthCheckMutation()
        }
    }
}

@MainActor
final class HealthCheckNotificationComposition {
    let repository: any HealthChecksRepository
    let lifecycleCoordinator: HealthCheckNotificationLifecycleCoordinator
    let healthChecksRepository: NotificationReconcilingHealthChecksRepository
    let authorizationController: HealthCheckNotificationAuthorizationController

    init(
        repository: any HealthChecksRepository,
        notificationCenter: any NotificationCenterClient,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        let reconciler = HealthCheckNotificationReconciler(
            center: notificationCenter,
            now: now
        )
        self.repository = repository
        lifecycleCoordinator = HealthCheckNotificationLifecycleCoordinator(
            repository: repository,
            reconciler: reconciler
        )
        healthChecksRepository = NotificationReconcilingHealthChecksRepository(
            repository: repository,
            lifecycle: lifecycleCoordinator
        )
        authorizationController = HealthCheckNotificationAuthorizationController(
            center: notificationCenter
        )
    }

    init(
        repository: any HealthChecksRepository,
        reconciler: any HealthCheckNotificationReconciling,
        authorizationController: HealthCheckNotificationAuthorizationController? = nil,
        notificationCenter: any NotificationCenterClient =
            SystemNotificationCenterAdapter()
    ) {
        self.repository = repository
        lifecycleCoordinator = HealthCheckNotificationLifecycleCoordinator(
            repository: repository,
            reconciler: reconciler
        )
        healthChecksRepository = NotificationReconcilingHealthChecksRepository(
            repository: repository,
            lifecycle: lifecycleCoordinator
        )
        self.authorizationController = authorizationController
            ?? HealthCheckNotificationAuthorizationController(
                center: notificationCenter
            )
    }
}

@MainActor
final class HealthCheckNotificationLaunchGate {
    private let reconcile: @MainActor () async throws -> Bool
    private var todayContentIsMeaningful = false
    private var didComplete = false
    private var activeTask: Task<Void, Never>?
    private var activeGeneration: UInt64 = 0

    init(reconcile: @escaping @MainActor () async throws -> Bool) {
        self.reconcile = reconcile
    }

    func markTodayContentMeaningful() {
        todayContentIsMeaningful = true
    }

    func reconcileIfNeeded() async {
        guard todayContentIsMeaningful, !didComplete else { return }
        if let activeTask {
            await activeTask.value
            return
        }

        activeGeneration &+= 1
        let generation = activeGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<2 {
                do {
                    let converged = try await self.reconcile()
                    guard converged else { continue }
                    self.didComplete = true
                    return
                } catch {
                    // The launch owner retries once without reopening the Today callback.
                }
            }
        }
        activeTask = task
        await task.value
        if activeGeneration == generation {
            activeTask = nil
        }
    }
}

@MainActor
enum DefaultHealthCheckNotificationFactory {
    static func make(
        modelContext: ModelContext,
        notificationCenter: any NotificationCenterClient
    ) -> HealthCheckNotificationComposition {
        let calendar = AppDomainContext.makeCalendar()
        let now: @MainActor () -> Date = { AppDomainContext.now() }
        let repository = SwiftDataHealthChecksRepository(
            modelContext: modelContext,
            calendar: calendar,
            now: now
        )
        return HealthCheckNotificationComposition(
            repository: repository,
            notificationCenter: notificationCenter,
            now: { .now }
        )
    }
}
