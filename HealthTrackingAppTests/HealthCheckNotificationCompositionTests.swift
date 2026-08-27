@testable import HealthTrackingApp
import CoreModels
import Foundation
import HealthChecksKit
import NotificationsKit
import SwiftUI
import XCTest

@MainActor
final class HealthCheckNotificationCompositionTests: XCTestCase {
    func testRealMapperExposesOnlyOpaqueIdentityDueDateAndPendingEligibility() throws {
        let pendingID = try XCTUnwrap(
            UUID(uuidString: "a3a3a3a3-0000-0000-0000-000000000311")
        )
        let doneID = try XCTUnwrap(
            UUID(uuidString: "b4b4b4b4-0000-0000-0000-000000000312")
        )
        let pendingDate = Date(timeIntervalSince1970: 1_804_060_800)
        let doneDate = pendingDate.addingTimeInterval(123_456)
        let snapshots = [
            snapshot(
                id: pendingID,
                name: "HIV pozitif; HbA1c 13.2; MR sonucu; marker=CA-125",
                dueDate: pendingDate,
                recurrence: .quarterly,
                status: .pending
            ),
            snapshot(
                id: doneID,
                name: "Servikal bulgu; sonuç 987; 2027-03-01 09:30",
                dueDate: doneDate,
                recurrence: .yearly,
                status: .done
            ),
        ]

        let descriptors = HealthCheckNotificationMapper.descriptors(from: snapshots)
        let reflected = String(reflecting: descriptors)

        XCTAssertEqual(descriptors, [
            .init(reminderID: pendingID, dueDate: pendingDate, isEligible: true),
            .init(reminderID: doneID, dueDate: doneDate, isEligible: false),
        ])
        for sensitiveValue in [
            "HIV",
            "HbA1c",
            "MR sonucu",
            "CA-125",
            "Servikal",
            "987",
            "quarterly",
            "yearly",
        ] {
            XCTAssertFalse(reflected.localizedCaseInsensitiveContains(sensitiveValue))
        }
    }

    func testFirstMeaningfulTodayContentRunsOnceThenEveryCommittedMutationRefetchesAndRemaps() async throws {
        let first = snapshot(
            id: UUID(),
            name: "Sensitive first name",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .monthly,
            status: .pending
        )
        let edited = snapshot(
            id: first.id,
            name: "Sensitive edited name",
            dueDate: first.dueDate.addingTimeInterval(7_200),
            recurrence: .monthly,
            status: .pending
        )
        let completed = snapshot(
            id: first.id,
            name: edited.name,
            dueDate: edited.dueDate,
            recurrence: .monthly,
            status: .done
        )
        let repository = NotificationHealthChecksRepositoryFake(snapshots: [first])
        let reconciler = HealthCheckNotificationReconcilerSpy()
        let lifecycle = HealthCheckNotificationLifecycleCoordinator(
            repository: repository,
            reconciler: reconciler
        )

        let initialFetchCount = repository.fetchCount
        let initialReconciliations = await reconciler.invocations
        XCTAssertEqual(initialFetchCount, 0)
        XCTAssertTrue(initialReconciliations.isEmpty)

        try await lifecycle.reconcileAfterFirstMeaningfulTodayContent()
        try await lifecycle.reconcileAfterFirstMeaningfulTodayContent()

        repository.snapshots = [edited]
        try await lifecycle.reconcileAfterHealthCheckMutation() // edit
        repository.snapshots = [completed]
        try await lifecycle.reconcileAfterHealthCheckMutation() // complete
        repository.snapshots = []
        try await lifecycle.reconcileAfterHealthCheckMutation() // delete

        let invocations = await reconciler.invocations
        XCTAssertEqual(repository.fetchCount, 4)
        XCTAssertEqual(invocations, [
            HealthCheckNotificationMapper.descriptors(from: [first]),
            HealthCheckNotificationMapper.descriptors(from: [edited]),
            HealthCheckNotificationMapper.descriptors(from: [completed]),
            [],
        ])
    }

    func testNewerMutationGenerationIgnoresOlderSuspendedLaunchFetch() async throws {
        let old = snapshot(
            id: UUID(),
            name: "Old sensitive value",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .monthly,
            status: .pending
        )
        let current = snapshot(
            id: UUID(),
            name: "Current sensitive value",
            dueDate: Date(timeIntervalSince1970: 1_804_147_200),
            recurrence: .none,
            status: .pending
        )
        let repository = NotificationHealthChecksRepositoryFake(
            snapshots: [old],
            suspendedFetchCalls: [1]
        )
        let reconciler = HealthCheckNotificationReconcilerSpy()
        let lifecycle = HealthCheckNotificationLifecycleCoordinator(
            repository: repository,
            reconciler: reconciler
        )

        let launch = Task {
            try await lifecycle.reconcileAfterFirstMeaningfulTodayContent()
        }
        let didSuspendNewestFetch = await repository.waitUntilFetch(call: 1)
        XCTAssertTrue(didSuspendNewestFetch)
        repository.snapshots = [current]
        let mutation = Task {
            try await lifecycle.reconcileAfterHealthCheckMutation()
        }
        try await mutation.value
        repository.resumeFetch(call: 1, snapshots: [old])
        let supersededFetchLaunchConverged = try await launch.value
        XCTAssertFalse(supersededFetchLaunchConverged)
        let invocations = await reconciler.invocations

        XCTAssertEqual(repository.fetchCount, 2)
        XCTAssertEqual(
            invocations,
            [HealthCheckNotificationMapper.descriptors(from: [current])]
        )
    }

    func testNewerMutationCancelsOlderReconciliationAlreadySuspendedAtSystemSeam() async throws {
        let old = snapshot(
            id: UUID(),
            name: "Old suspended sensitive value",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .monthly,
            status: .pending
        )
        let current = snapshot(
            id: UUID(),
            name: "Current replacement sensitive value",
            dueDate: Date(timeIntervalSince1970: 1_804_147_200),
            recurrence: .none,
            status: .pending
        )
        let repository = NotificationHealthChecksRepositoryFake(snapshots: [old])
        let reconciler = HealthCheckNotificationReconcilerSpy(suspendedCalls: [1])
        let lifecycle = HealthCheckNotificationLifecycleCoordinator(
            repository: repository,
            reconciler: reconciler
        )
        let oldLaunch = Task {
            try await lifecycle.reconcileAfterFirstMeaningfulTodayContent()
        }
        let didStartOldReconciliation = await reconciler.waitUntilReconciliation(call: 1)
        XCTAssertTrue(didStartOldReconciliation)

        repository.snapshots = [current]
        let mutation = Task {
            try await lifecycle.reconcileAfterHealthCheckMutation()
        }
        let didCancelOldReconciliation = await reconciler.waitUntilCancellation(call: 1)
        XCTAssertTrue(didCancelOldReconciliation)
        await reconciler.resumeReconciliation(call: 1)
        try await mutation.value

        do {
            try await oldLaunch.value
            XCTFail("The older suspended reconciliation must be canceled.")
        } catch is CancellationError {
            // Expected: the current generation owns the only committed invocation.
        }
        let invocations = await reconciler.invocations
        XCTAssertEqual(
            invocations,
            [HealthCheckNotificationMapper.descriptors(from: [current])]
        )
    }

    func testNewerMutationWaitsForNonCancellableInFlightEffectAndConvergesNewestLast() async throws {
        let old = snapshot(
            id: UUID(),
            name: "Old in-flight sensitive value",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .monthly,
            status: .pending
        )
        let current = snapshot(
            id: UUID(),
            name: "Newest authoritative sensitive value",
            dueDate: Date(timeIntervalSince1970: 1_804_147_200),
            recurrence: .none,
            status: .pending
        )
        let repository = NotificationHealthChecksRepositoryFake(snapshots: [old])
        let reconciler = HealthCheckNotificationReconcilerSpy(
            nonCancellableSuspendedCalls: [1]
        )
        let lifecycle = HealthCheckNotificationLifecycleCoordinator(
            repository: repository,
            reconciler: reconciler
        )
        let oldLaunch = Task {
            try await lifecycle.reconcileAfterFirstMeaningfulTodayContent()
        }
        let didStartOldEffect = await reconciler.waitUntilReconciliation(call: 1)
        XCTAssertTrue(didStartOldEffect)

        repository.snapshots = [current]
        let newestMutation = Task {
            try await lifecycle.reconcileAfterHealthCheckMutation()
        }
        let didCancelOldEffect = await reconciler.waitUntilCancellation(call: 1)
        XCTAssertTrue(didCancelOldEffect)
        let attemptsBeforeOldEffectFinishes = await reconciler.attemptCount

        XCTAssertEqual(
            attemptsBeforeOldEffectFinishes,
            1,
            "The newest reconciliation must wait until the canceled in-flight effect finishes."
        )

        await reconciler.resumeReconciliation(call: 1)
        do {
            let supersededEffectConverged = try await oldLaunch.value
            XCTAssertFalse(supersededEffectConverged)
        } catch is CancellationError {
            // Either stale-call completion policy is safe once newest state converges last.
        }
        try await newestMutation.value
        let invocations = await reconciler.invocations
        let committedDescriptors = await reconciler.committedDescriptors

        XCTAssertEqual(invocations, [
            HealthCheckNotificationMapper.descriptors(from: [old]),
            HealthCheckNotificationMapper.descriptors(from: [current]),
        ])
        XCTAssertEqual(
            invocations.last,
            HealthCheckNotificationMapper.descriptors(from: [current])
        )
        XCTAssertEqual(
            committedDescriptors,
            HealthCheckNotificationMapper.descriptors(from: [current])
        )
    }

    func testThreeGenerationsSkipMiddleWorkAndCommitOnlyNewestAfterOldNonCancellableEffect() async throws {
        let old = snapshot(
            id: UUID(),
            name: "Old three-generation value",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .monthly,
            status: .pending
        )
        let middle = snapshot(
            id: UUID(),
            name: "Middle value must never commit",
            dueDate: old.dueDate.addingTimeInterval(3_600),
            recurrence: .quarterly,
            status: .pending
        )
        let newest = snapshot(
            id: UUID(),
            name: "Newest authoritative three-generation value",
            dueDate: middle.dueDate.addingTimeInterval(3_600),
            recurrence: .yearly,
            status: .pending
        )
        let repository = NotificationHealthChecksRepositoryFake(snapshots: [old])
        let reconciler = HealthCheckNotificationReconcilerSpy(
            nonCancellableSuspendedCalls: [1]
        )
        let lifecycle = HealthCheckNotificationLifecycleCoordinator(
            repository: repository,
            reconciler: reconciler
        )

        let oldLaunch = Task {
            try await lifecycle.reconcileAfterFirstMeaningfulTodayContent()
        }
        let didStartOldThreeGenerationEffect = await reconciler
            .waitUntilReconciliation(call: 1)
        XCTAssertTrue(didStartOldThreeGenerationEffect)

        repository.snapshots = [middle]
        let middleMutation = Task {
            try await lifecycle.reconcileAfterHealthCheckMutation()
        }
        let didCancelOldThreeGenerationEffect = await reconciler
            .waitUntilCancellation(call: 1)
        XCTAssertTrue(didCancelOldThreeGenerationEffect)

        repository.snapshots = [newest]
        let newestGenerationEntered = expectation(
            description: "newest notification generation entered"
        )
        let newestMutation = Task { @MainActor in
            newestGenerationEntered.fulfill()
            try await lifecycle.reconcileAfterHealthCheckMutation()
        }
        await fulfillment(of: [newestGenerationEntered], timeout: 1)
        await Task.yield()
        let attemptsWhileOldEffectIsSuspended = await reconciler.attemptCount
        XCTAssertEqual(attemptsWhileOldEffectIsSuspended, 1)

        await reconciler.resumeReconciliation(call: 1)
        let supersededThreeGenerationLaunchConverged = try await oldLaunch.value
        XCTAssertFalse(supersededThreeGenerationLaunchConverged)
        _ = await middleMutation.result
        try await newestMutation.value

        let invocations = await reconciler.invocations
        let finalAttemptCount = await reconciler.attemptCount
        let committedDescriptors = await reconciler.committedDescriptors
        XCTAssertEqual(finalAttemptCount, 2)
        XCTAssertEqual(invocations, [
            HealthCheckNotificationMapper.descriptors(from: [old]),
            HealthCheckNotificationMapper.descriptors(from: [newest]),
        ])
        XCTAssertEqual(
            committedDescriptors,
            HealthCheckNotificationMapper.descriptors(from: [newest])
        )
    }

    func testStaleSuccessfulLaunchCannotCloseGateWhenNewestMutationFailsAndLaunchRetries() async throws {
        let old = snapshot(
            id: UUID(),
            name: "Old successful stale launch value",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .monthly,
            status: .pending
        )
        let newest = snapshot(
            id: UUID(),
            name: "Newest value retried after failure",
            dueDate: old.dueDate.addingTimeInterval(7_200),
            recurrence: .none,
            status: .pending
        )
        let repository = NotificationHealthChecksRepositoryFake(snapshots: [old])
        let reconciler = HealthCheckNotificationReconcilerSpy(
            failingCalls: [2],
            nonCancellableSuspendedCalls: [1]
        )
        let lifecycle = HealthCheckNotificationLifecycleCoordinator(
            repository: repository,
            reconciler: reconciler
        )

        let oldLaunch = Task {
            try await lifecycle.reconcileAfterFirstMeaningfulTodayContent()
        }
        let didStartStaleLaunchEffect = await reconciler.waitUntilReconciliation(call: 1)
        XCTAssertTrue(didStartStaleLaunchEffect)

        repository.snapshots = [newest]
        let newestMutation = Task {
            try await lifecycle.reconcileAfterHealthCheckMutation()
        }
        let didCancelStaleLaunchEffect = await reconciler.waitUntilCancellation(call: 1)
        XCTAssertTrue(didCancelStaleLaunchEffect)
        await reconciler.resumeReconciliation(call: 1)
        let staleLaunchConverged = try await oldLaunch.value
        XCTAssertFalse(staleLaunchConverged)

        do {
            try await newestMutation.value
            XCTFail("The newest injected reconciliation failure must propagate.")
        } catch HealthCheckNotificationReconcilerSpy.Failure.injected {
            // The stale successful launch must not close the launch retry gate.
        }

        let retryConverged = try await lifecycle
            .reconcileAfterFirstMeaningfulTodayContent()
        XCTAssertTrue(retryConverged)

        let retryAttemptCount = await reconciler.attemptCount
        let retryInvocations = await reconciler.invocations
        let retriedDescriptors = await reconciler.committedDescriptors
        XCTAssertEqual(repository.fetchCount, 3)
        XCTAssertEqual(retryAttemptCount, 3)
        XCTAssertEqual(retryInvocations, [
            HealthCheckNotificationMapper.descriptors(from: [old]),
            HealthCheckNotificationMapper.descriptors(from: [newest]),
        ])
        XCTAssertEqual(
            retriedDescriptors,
            HealthCheckNotificationMapper.descriptors(from: [newest])
        )
    }

    func testLaunchGateRetriesSupersededOutcomeAndClosesOnlyAfterConvergence() async {
        var outcomes = [false, true]
        var attemptCount = 0
        let gate = HealthCheckNotificationLaunchGate {
            attemptCount += 1
            return outcomes.removeFirst()
        }
        gate.markTodayContentMeaningful()

        await gate.reconcileIfNeeded()
        await gate.reconcileIfNeeded()

        XCTAssertEqual(attemptCount, 2)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testFailedFirstMeaningfulReconciliationCanRetryAfterFailure() async throws {
        let reminder = snapshot(
            id: UUID(),
            name: "Retry-sensitive name",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .quarterly,
            status: .pending
        )
        let repository = NotificationHealthChecksRepositoryFake(snapshots: [reminder])
        let reconciler = HealthCheckNotificationReconcilerSpy(failingCalls: [1])
        let lifecycle = HealthCheckNotificationLifecycleCoordinator(
            repository: repository,
            reconciler: reconciler
        )

        do {
            try await lifecycle.reconcileAfterFirstMeaningfulTodayContent()
            XCTFail("The injected first launch failure must propagate.")
        } catch HealthCheckNotificationReconcilerSpy.Failure.injected {
            // The one-shot launch gate must remain retryable after a real failure.
        }
        try await lifecycle.reconcileAfterFirstMeaningfulTodayContent()

        let attemptCount = await reconciler.attemptCount
        let invocations = await reconciler.invocations
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(
            invocations,
            [HealthCheckNotificationMapper.descriptors(from: [reminder])]
        )
    }

    func testDeniedAndNotDeterminedReconciliationNeverMutateRepositoryRemindersOrPrompt() async throws {
        for status in [
            NotificationAuthorizationStatus.denied,
            NotificationAuthorizationStatus.notDetermined,
        ] {
            let original = snapshot(
                id: UUID(),
                name: "Sensitive repository value",
                dueDate: Date(timeIntervalSince1970: 1_804_060_800),
                recurrence: .quarterly,
                status: .pending
            )
            let repository = NotificationHealthChecksRepositoryFake(snapshots: [original])
            let center = PermissionPreservingNotificationCenterFake(status: status)
            let reconciler = HealthCheckNotificationReconciler(
                center: center,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            let lifecycle = HealthCheckNotificationLifecycleCoordinator(
                repository: repository,
                reconciler: reconciler
            )

            try await lifecycle.reconcileAfterFirstMeaningfulTodayContent()
            let centerSnapshot = await center.snapshot()

            XCTAssertEqual(repository.snapshots, [original])
            XCTAssertEqual(repository.mutationCount, 0)
            XCTAssertEqual(centerSnapshot.addCount, 0)
            XCTAssertEqual(centerSnapshot.authorizationRequestCount, 0)
        }
    }

    func testConcreteBundleMutationRepositoryDrivesLaunchEditCompleteDeleteAndExplicitPermissionThroughSystemAdapter() async throws {
        let reminderID = UUID()
        let first = snapshot(
            id: reminderID,
            name: "Sensitive initial check",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .quarterly,
            status: .pending
        )
        let edited = snapshot(
            id: reminderID,
            name: "Sensitive edited check",
            dueDate: Date(timeIntervalSince1970: 1_804_147_200),
            recurrence: .yearly,
            status: .pending
        )
        let repository = NotificationHealthChecksRepositoryFake(
            snapshots: [first],
            failingMutationOperations: [.delete],
            suspendedMutationOperations: [.update, .complete]
        )
        let backend = CompositionNotificationSystemBackendFake()
        let adapter = SystemNotificationCenterAdapter(backend: backend)
        let bundle = TrackerFeatureBundle(
            metricsRepository: TrackerMetricsRepositoryStub(),
            lifestyleRepository: TrackerLifestyleRepositoryStub(),
            healthChecksRepository: repository,
            bloodworkRepository: TrackerBloodworkRepositoryStub(),
            notificationCenter: adapter,
            calendar: Calendar(identifier: .gregorian)
        )
        var todayRefreshCount = 0
        let actions = bundle.makeHealthCheckListNotificationActions {
            todayRefreshCount += 1
        }

        try await bundle.reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent()
        let edit = Task {
            try await bundle.healthChecksRepository.updateReminder(
                id: first.id,
                expectedUpdatedAt: first.updatedAt,
                input: HealthCheckReminderInput(
                    name: edited.name,
                    dueDate: edited.dueDate,
                    recurrence: edited.recurrence
                )
            )
        }
        await repository.waitUntilMutationIsSuspended(.update)
        XCTAssertEqual(repository.fetchCount, 1)
        repository.resumeMutation(.update)
        let editedResult = try await edit.value

        let complete = Task {
            try await bundle.healthChecksRepository.completeReminder(
                id: editedResult.id,
                expectedUpdatedAt: editedResult.updatedAt
            )
        }
        await repository.waitUntilMutationIsSuspended(.complete)
        XCTAssertEqual(repository.fetchCount, 2)
        repository.resumeMutation(.complete)
        let completion = try await complete.value

        do {
            try await bundle.healthChecksRepository.deleteReminder(
                id: completion.completed.id,
                expectedUpdatedAt: completion.completed.updatedAt
            )
            XCTFail("The first delete failure must propagate without reconciliation.")
        } catch NotificationHealthChecksRepositoryFake.Failure.injectedMutation {
            XCTAssertEqual(repository.fetchCount, 3)
        }
        try await bundle.healthChecksRepository.deleteReminder(
            id: completion.completed.id,
            expectedUpdatedAt: completion.completed.updatedAt
        )
        await actions.onRequestNotificationAuthorization()

        let backendSnapshot = await backend.snapshot()
        XCTAssertEqual(repository.fetchCount, 4)
        XCTAssertEqual(repository.mutationOperations, [.update, .complete, .delete])
        XCTAssertEqual(todayRefreshCount, 0)
        XCTAssertEqual(
            backendSnapshot.addedRequests.map(\.deliveryDate),
            [first.dueDate, edited.dueDate]
        )
        XCTAssertEqual(
            Set(backendSnapshot.addedRequests.map(\.identifier)),
            [HealthCheckNotificationPlanner.requestIdentifier(for: reminderID)]
        )
        XCTAssertTrue(backendSnapshot.pending.isEmpty)
        XCTAssertEqual(backendSnapshot.authorizationRequestCount, 1)
    }

    func testConcretePermissionActionsBindPresentationDismissalAndRejectStaleCallback() async throws {
        let repository = NotificationHealthChecksRepositoryFake(snapshots: [])
        let center = CompositionAuthorizationCenterFake()
        let bundle = TrackerFeatureBundle(
            metricsRepository: TrackerMetricsRepositoryStub(),
            lifestyleRepository: TrackerLifestyleRepositoryStub(),
            healthChecksRepository: repository,
            bloodworkRepository: TrackerBloodworkRepositoryStub(),
            notificationCenter: center,
            calendar: Calendar(identifier: .gregorian)
        )
        let actions = bundle.makeHealthCheckListNotificationActions {}

        actions.onPresentation()
        let oldRequest = Task {
            await actions.onRequestNotificationAuthorization()
        }
        await center.waitUntilAuthorizationRequest(call: 1)
        actions.onDismissal()
        actions.onPresentation()
        let newestRequest = Task {
            await actions.onRequestNotificationAuthorization()
        }
        await center.waitUntilAuthorizationRequest(call: 2)

        try await center.resumeAuthorizationRequest(call: 2, granted: true)
        await newestRequest.value
        XCTAssertEqual(actions.authorizationState, .authorized)

        try await center.resumeAuthorizationRequest(call: 1, granted: false)
        await oldRequest.value
        let requestCount = await center.authorizationRequestCount

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(actions.authorizationState, .authorized)
    }

    func testFailedConcreteMutationDoesNotRefetchOrReconcile() async throws {
        let first = snapshot(
            id: UUID(),
            name: "Preserved after failed edit",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .monthly,
            status: .pending
        )
        let repository = NotificationHealthChecksRepositoryFake(
            snapshots: [first],
            failingMutationOperations: [.update]
        )
        let backend = CompositionNotificationSystemBackendFake()
        let adapter = SystemNotificationCenterAdapter(backend: backend)
        let bundle = TrackerFeatureBundle(
            metricsRepository: TrackerMetricsRepositoryStub(),
            lifestyleRepository: TrackerLifestyleRepositoryStub(),
            healthChecksRepository: repository,
            bloodworkRepository: TrackerBloodworkRepositoryStub(),
            notificationCenter: adapter,
            calendar: Calendar(identifier: .gregorian)
        )

        try await bundle.reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent()
        do {
            _ = try await bundle.healthChecksRepository.updateReminder(
                id: first.id,
                expectedUpdatedAt: first.updatedAt,
                input: HealthCheckReminderInput(
                    name: "Must not commit",
                    dueDate: first.dueDate.addingTimeInterval(3_600),
                    recurrence: .yearly
                )
            )
            XCTFail("The injected repository failure must propagate.")
        } catch NotificationHealthChecksRepositoryFake.Failure.injectedMutation {
            // A failed repository mutation must not start notification reconciliation.
        }

        let backendSnapshot = await backend.snapshot()
        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertTrue(repository.mutationOperations.isEmpty)
        XCTAssertEqual(
            backendSnapshot.addedRequests.map(\.deliveryDate),
            [first.dueDate]
        )
    }

    func testCommittedMutationReturnsSuccessAndRetriesNotificationFailureWithoutRepeatingRepositoryWrite() async throws {
        let first = snapshot(
            id: UUID(),
            name: "Committed repository value",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .monthly,
            status: .pending
        )
        let editedDate = first.dueDate.addingTimeInterval(7_200)
        let repository = NotificationHealthChecksRepositoryFake(snapshots: [first])
        let reconciler = HealthCheckNotificationReconcilerSpy(failingCalls: [1])
        let composition = HealthCheckNotificationComposition(
            repository: repository,
            reconciler: reconciler
        )
        let bundle = TrackerFeatureBundle(
            metricsRepository: TrackerMetricsRepositoryStub(),
            lifestyleRepository: TrackerLifestyleRepositoryStub(),
            healthChecksRepository: repository,
            bloodworkRepository: TrackerBloodworkRepositoryStub(),
            healthCheckNotificationComposition: composition,
            calendar: Calendar(identifier: .gregorian)
        )

        let updated = try await bundle.healthChecksRepository.updateReminder(
            id: first.id,
            expectedUpdatedAt: first.updatedAt,
            input: HealthCheckReminderInput(
                name: "Committed edited value",
                dueDate: editedDate,
                recurrence: .yearly
            )
        )

        let notificationAttemptCount = await reconciler.attemptCount
        let successfulInvocations = await reconciler.invocations
        XCTAssertEqual(updated.dueDate, editedDate)
        XCTAssertEqual(repository.mutationOperations, [.update])
        XCTAssertEqual(repository.fetchCount, 2)
        XCTAssertEqual(notificationAttemptCount, 2)
        XCTAssertEqual(
            successfulInvocations,
            [HealthCheckNotificationMapper.descriptors(from: [updated])]
        )
    }

    func testRealTypeErasedTrackerEntryPointsExposeLaunchMutationAndExplicitPermissionActions() {
        let launchEntry: @MainActor (any TrackerFeatureRouting) async throws -> Void = {
            try await $0.reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent()
        }
        let mutationEntry: @MainActor (any TrackerFeatureRouting) async throws -> Void = {
            try await $0.reconcileHealthCheckNotificationsAfterCommittedMutation()
        }
        let explicitPermissionEntry: @MainActor (any TrackerFeatureRouting) async -> Void = {
            await $0.requestHealthCheckNotificationAuthorizationFromExplicitUserAction()
        }

        withExtendedLifetime(launchEntry) {}
        withExtendedLifetime(mutationEntry) {}
        withExtendedLifetime(explicitPermissionEntry) {}
    }

    func testRealAppDependenciesUseDedicatedLaunchCallbackWithoutInstantiatingLazyTrackerFactory() async throws {
        let launchReconciliation = expectation(
            description: "first meaningful Today notification reconciliation"
        )
        launchReconciliation.assertForOverFulfill = true
        let router = NotificationTrackerRouterSpy()
        var trackerFactoryCalls = 0
        var launchReconciliationCount = 0
        let dependencies = try AppDependencies(
            environment: .uiTesting,
            makeTrackerFeatureBundle: { _ in
                trackerFactoryCalls += 1
                return router
            },
            reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent: {
                launchReconciliationCount += 1
                launchReconciliation.fulfill()
            }
        )

        XCTAssertEqual(trackerFactoryCalls, 0)
        XCTAssertEqual(launchReconciliationCount, 0)
        try dependencies.load()
        XCTAssertEqual(trackerFactoryCalls, 0)
        XCTAssertEqual(launchReconciliationCount, 0)

        await dependencies.loadInitialContent()
        await fulfillment(of: [launchReconciliation], timeout: 1)
        await dependencies.loadInitialContent()

        XCTAssertEqual(trackerFactoryCalls, 0)
        XCTAssertEqual(router.launchReconciliationCount, 0)
        XCTAssertEqual(
            launchReconciliationCount,
            1,
            "Only the first meaningful Today callback may start launch reconciliation."
        )
    }

    func testRealAppDependenciesTodayRetryAfterInitialEmptyTriggersOwnedNotificationCallbackOnce() async throws {
        let launchReconciliation = expectation(
            description: "retry publishes first meaningful notification reconciliation"
        )
        launchReconciliation.assertForOverFulfill = true
        var launchReconciliationCount = 0
        let dependencies = try AppDependencies(
            environment: .uiTesting,
            reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent: {
                launchReconciliationCount += 1
                launchReconciliation.fulfill()
            }
        )

        await dependencies.todayViewModel.load()
        XCTAssertEqual(dependencies.todayViewModel.state, .empty)
        XCTAssertEqual(launchReconciliationCount, 0)

        try dependencies.load()
        await dependencies.todayViewModel.retry()
        await fulfillment(of: [launchReconciliation], timeout: 1)
        guard case .content = dependencies.todayViewModel.state else {
            return XCTFail("The seeded retry must publish meaningful Today content.")
        }

        await dependencies.todayViewModel.retry()
        XCTAssertEqual(
            launchReconciliationCount,
            1,
            "Later retries must not reopen the completed first-meaningful launch gate."
        )
    }

    func testDefaultAppDependenciesLaunchFactoryRunsRealLifecycleWithoutInstantiatingTrackerFactory() async throws {
        let center = PermissionPreservingNotificationCenterFake(status: .notDetermined)
        let router = NotificationTrackerRouterSpy()
        var trackerFactoryCalls = 0
        let dependencies = try AppDependencies(
            environment: .uiTesting,
            makeTrackerFeatureBundle: { _ in
                trackerFactoryCalls += 1
                return router
            },
            healthCheckNotificationCenter: center
        )

        try dependencies.load()
        let beforeLoad = await center.snapshot()
        XCTAssertEqual(beforeLoad.authorizationStatusCount, 0)
        XCTAssertEqual(trackerFactoryCalls, 0)

        await dependencies.loadInitialContent()
        let observedLaunchReconciliation = await center.waitUntilAuthorizationStatus(call: 1)
        await dependencies.loadInitialContent()

        let afterLoad = await center.snapshot()
        XCTAssertTrue(observedLaunchReconciliation)
        XCTAssertEqual(afterLoad.authorizationStatusCount, 1)
        XCTAssertEqual(afterLoad.authorizationRequestCount, 0)
        XCTAssertEqual(trackerFactoryCalls, 0)
        XCTAssertEqual(router.launchReconciliationCount, 0)
    }

    func testShippedDefaultPrewarmerCenterSerializesLaunchWithLazyBundleMutation() async throws {
        let center = DefaultCompositionOwnerNotificationCenterFake()
        let prewarmer = AppDependencyPrewarmer(
            environment: .uiTesting,
            healthCheckNotificationCenter: center
        )

        let dependencies: AppDependencies = try await prewarmer.makeDependencies()
        try dependencies.load()
        let launch = Task {
            await dependencies.loadInitialContent()
        }
        let didStartLaunch = await center.waitUntilAuthorizationStatus(call: 1)
        XCTAssertTrue(didStartLaunch)
        XCTAssertEqual(dependencies.trackerFeatureRouterInstantiationCount, 0)

        let bundle = try XCTUnwrap(
            dependencies.makeTrackerFeatureRouter() as? TrackerFeatureBundle
        )
        XCTAssertEqual(dependencies.trackerFeatureRouterInstantiationCount, 1)
        let dueDate = Date(timeIntervalSince1970: 1_804_147_200)
        let mutation = Task {
            try await bundle.healthChecksRepository.createReminder(
                HealthCheckReminderInput(
                    name: "Default owner sensitive value",
                    dueDate: dueDate,
                    recurrence: .monthly
                )
            )
        }

        let ownershipSignal = await center.waitForCancellationOrSecondAuthorizationStatus()
        XCTAssertTrue(
            ownershipSignal.cancelledFirstCall,
            "The default lazy bundle must cancel work owned by the default launch composition."
        )
        XCTAssertEqual(
            ownershipSignal.authorizationStatusCount,
            1,
            "A second composition must not run around the suspended launch owner."
        )

        await center.resumeAuthorizationStatus(call: 1)
        let created = try await mutation.value
        await launch.value
        let finalCenter = await center.snapshot()
        let expectedIdentifier = HealthCheckNotificationPlanner.requestIdentifier(
            for: created.id
        )

        XCTAssertTrue(
            finalCenter.pending.contains(where: {
                $0.identifier == expectedIdentifier && $0.deliveryDate == dueDate
            }),
            "The newest committed default-repository value must survive stale launch cleanup."
        )
        XCTAssertEqual(finalCenter.authorizationRequestCount, 0)
    }

    func testAppDependenciesRetriesFailedMeaningfulLaunchReconciliationWithinSingleBootstrapLoad() async throws {
        var attemptCount = 0
        let dependencies = try AppDependencies(
            environment: .uiTesting,
            reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent: {
                attemptCount += 1
                if attemptCount == 1 {
                    throw HealthCheckNotificationLaunchFailure.injected
                }
            }
        )

        try dependencies.load()
        await dependencies.loadInitialContent()
        XCTAssertEqual(attemptCount, 2)

        await dependencies.loadInitialContent()
        XCTAssertEqual(attemptCount, 2)
    }

    func testDefaultAppDependenciesSharesLaunchCompositionWithLazyBundleMutationRepository() async throws {
        let first = snapshot(
            id: UUID(),
            name: "Shared launch sensitive value",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .monthly,
            status: .pending
        )
        let edited = snapshot(
            id: first.id,
            name: "Shared mutation sensitive value",
            dueDate: first.dueDate.addingTimeInterval(7_200),
            recurrence: .yearly,
            status: .pending
        )
        let repository = NotificationHealthChecksRepositoryFake(snapshots: [first])
        let backend = CompositionNotificationSystemBackendFake()
        let adapter = SystemNotificationCenterAdapter(backend: backend)
        let composition = HealthCheckNotificationComposition(
            repository: repository,
            notificationCenter: adapter,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let dependencies = try AppDependencies(
            environment: .uiTesting,
            healthCheckNotificationComposition: composition
        )

        try dependencies.load()
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertEqual(dependencies.trackerFeatureRouterInstantiationCount, 0)
        await dependencies.loadInitialContent()
        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertEqual(dependencies.trackerFeatureRouterInstantiationCount, 0)

        let bundle = try XCTUnwrap(
            dependencies.makeTrackerFeatureRouter() as? TrackerFeatureBundle
        )
        XCTAssertEqual(dependencies.trackerFeatureRouterInstantiationCount, 1)
        XCTAssertTrue(bundle.healthCheckNotificationComposition === composition)
        _ = try await bundle.healthChecksRepository.updateReminder(
            id: first.id,
            expectedUpdatedAt: first.updatedAt,
            input: HealthCheckReminderInput(
                name: edited.name,
                dueDate: edited.dueDate,
                recurrence: edited.recurrence
            )
        )

        let backendSnapshot = await backend.snapshot()
        XCTAssertEqual(repository.fetchCount, 2)
        XCTAssertEqual(repository.mutationOperations, [.update])
        XCTAssertEqual(
            backendSnapshot.addedRequests.map(\.deliveryDate),
            [first.dueDate, edited.dueDate]
        )
        XCTAssertEqual(backendSnapshot.authorizationRequestCount, 0)
    }

    func testShippedPrewarmerSerializesPreloadedLaunchWithLazyBundleMutationOnSharedComposition() async throws {
        let first = snapshot(
            id: UUID(),
            name: "Prewarmed launch sensitive value",
            dueDate: Date(timeIntervalSince1970: 1_804_060_800),
            recurrence: .monthly,
            status: .pending
        )
        let editedDate = first.dueDate.addingTimeInterval(7_200)
        let repository = NotificationHealthChecksRepositoryFake(snapshots: [first])
        let reconciler = HealthCheckNotificationReconcilerSpy(
            nonCancellableSuspendedCalls: [1]
        )
        let composition = HealthCheckNotificationComposition(
            repository: repository,
            reconciler: reconciler
        )
        let prewarmer = AppDependencyPrewarmer(
            environment: .uiTesting,
            healthCheckNotificationComposition: composition
        )

        let dependencies = try await prewarmer.makeDependencies()
        XCTAssertEqual(dependencies.trackerFeatureRouterInstantiationCount, 0)

        try dependencies.load()
        let preloadedLaunch = Task {
            await dependencies.loadInitialContent()
        }
        let didStartPreloadedLaunch = await reconciler.waitUntilReconciliation(call: 1)
        XCTAssertTrue(
            didStartPreloadedLaunch,
            "The shipped sync-preloaded Today callback must mark the launch gate."
        )
        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertEqual(dependencies.trackerFeatureRouterInstantiationCount, 0)

        let bundle = try XCTUnwrap(
            dependencies.makeTrackerFeatureRouter() as? TrackerFeatureBundle
        )
        XCTAssertIdentical(
            bundle.healthCheckNotificationComposition,
            composition,
            "The shipped prewarmer must bind launch and lazy tracker mutations to one composition."
        )
        XCTAssertEqual(dependencies.trackerFeatureRouterInstantiationCount, 1)

        let mutation = Task {
            try await bundle.healthChecksRepository.updateReminder(
                id: first.id,
                expectedUpdatedAt: first.updatedAt,
                input: HealthCheckReminderInput(
                    name: "Prewarmed edited value",
                    dueDate: editedDate,
                    recurrence: .yearly
                )
            )
        }
        let didCancelPreloadedLaunch = await reconciler.waitUntilCancellation(call: 1)
        let attemptsBeforePreloadedLaunchFinishes = await reconciler.attemptCount
        XCTAssertTrue(didCancelPreloadedLaunch)
        XCTAssertEqual(
            attemptsBeforePreloadedLaunchFinishes,
            1,
            "The lazy bundle mutation must share and serialize behind the preloaded launch owner."
        )

        await reconciler.resumeReconciliation(call: 1)
        let updated = try await mutation.value
        await preloadedLaunch.value

        let invocations = await reconciler.invocations
        let committedDescriptors = await reconciler.committedDescriptors
        XCTAssertGreaterThanOrEqual(repository.fetchCount, 2)
        XCTAssertEqual(repository.mutationOperations, [.update])
        XCTAssertEqual(
            invocations.first,
            HealthCheckNotificationMapper.descriptors(from: [first])
        )
        XCTAssertEqual(
            invocations.last,
            HealthCheckNotificationMapper.descriptors(from: [updated])
        )
        XCTAssertTrue(
            invocations.dropFirst().allSatisfy {
                $0 == HealthCheckNotificationMapper.descriptors(from: [updated])
            }
        )
        XCTAssertEqual(
            committedDescriptors,
            HealthCheckNotificationMapper.descriptors(from: [updated])
        )
    }

    private func snapshot(
        id: UUID,
        name: String,
        dueDate: Date,
        recurrence: HealthCheckRecurrence,
        status: HealthCheckStatus
    ) -> HealthCheckReminderSnapshot {
        HealthCheckReminderSnapshot(
            id: id,
            createdAt: dueDate.addingTimeInterval(-1),
            updatedAt: dueDate.addingTimeInterval(-1),
            name: name,
            dueDate: dueDate,
            recurrence: recurrence,
            status: status
        )
    }
}

private enum HealthCheckNotificationLaunchFailure: Error {
    case injected
}

@MainActor
private final class NotificationHealthChecksRepositoryFake: HealthChecksRepository {
    enum Failure: Error {
        case unexpectedMutation
        case injectedMutation
    }

    enum MutationOperation: Hashable {
        case create
        case update
        case delete
        case complete
        case undo
    }

    var snapshots: [HealthCheckReminderSnapshot]
    private(set) var fetchCount = 0
    private(set) var mutationCount = 0
    private(set) var mutationOperations: [MutationOperation] = []
    private var suspendedFetchCalls: Set<Int>
    private var failingMutationOperations: Set<MutationOperation>
    private var suspendedMutationOperations: Set<MutationOperation>
    private var fetchContinuations: [
        Int: CheckedContinuation<[HealthCheckReminderSnapshot], Never>
    ] = [:]
    private var suspendedMutationContinuations: [
        MutationOperation: CheckedContinuation<Void, Never>
    ] = [:]
    private var suspendedMutationWaiters: [
        MutationOperation: [CheckedContinuation<Void, Never>]
    ] = [:]

    init(
        snapshots: [HealthCheckReminderSnapshot],
        suspendedFetchCalls: Set<Int> = [],
        failingMutationOperations: Set<MutationOperation> = [],
        suspendedMutationOperations: Set<MutationOperation> = []
    ) {
        self.snapshots = snapshots
        self.suspendedFetchCalls = suspendedFetchCalls
        self.failingMutationOperations = failingMutationOperations
        self.suspendedMutationOperations = suspendedMutationOperations
    }

    func fetchReminders() async throws -> [HealthCheckReminderSnapshot] {
        fetchCount += 1
        let call = fetchCount
        guard suspendedFetchCalls.remove(call) != nil else {
            return snapshots
        }
        return await withCheckedContinuation { continuation in
            fetchContinuations[call] = continuation
        }
    }

    func waitUntilFetch(call: Int) async -> Bool {
        for _ in 0..<200 {
            if fetchCount >= call { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return fetchCount >= call
    }

    func resumeFetch(call: Int, snapshots: [HealthCheckReminderSnapshot]) {
        fetchContinuations.removeValue(forKey: call)?.resume(returning: snapshots)
    }

    func createReminder(
        _ input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        await suspendIfRequested(.create)
        try failIfRequested(.create)
        let snapshot = HealthCheckReminderSnapshot(
            id: UUID(),
            createdAt: input.dueDate.addingTimeInterval(-1),
            updatedAt: input.dueDate.addingTimeInterval(-1),
            name: input.name,
            dueDate: input.dueDate,
            recurrence: input.recurrence,
            status: .pending
        )
        snapshots.append(snapshot)
        record(.create)
        return snapshot
    }

    func updateReminder(
        id: UUID,
        expectedUpdatedAt: Date,
        input: HealthCheckReminderInput
    ) async throws -> HealthCheckReminderSnapshot {
        await suspendIfRequested(.update)
        try failIfRequested(.update)
        guard let index = snapshots.firstIndex(where: {
            $0.id == id && $0.updatedAt == expectedUpdatedAt
        }) else { throw Failure.unexpectedMutation }
        let original = snapshots[index]
        let updated = HealthCheckReminderSnapshot(
            id: original.id,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt.addingTimeInterval(1),
            name: input.name,
            dueDate: input.dueDate,
            recurrence: input.recurrence,
            status: original.status
        )
        snapshots[index] = updated
        record(.update)
        return updated
    }

    func deleteReminder(id: UUID, expectedUpdatedAt: Date) async throws {
        await suspendIfRequested(.delete)
        try failIfRequested(.delete)
        guard snapshots.contains(where: {
            $0.id == id && $0.updatedAt == expectedUpdatedAt
        }) else { throw Failure.unexpectedMutation }
        snapshots.removeAll { $0.id == id }
        record(.delete)
    }

    func completeReminder(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws -> HealthCheckCompletionMutation {
        await suspendIfRequested(.complete)
        try failIfRequested(.complete)
        guard let index = snapshots.firstIndex(where: {
            $0.id == id && $0.updatedAt == expectedUpdatedAt
        }) else { throw Failure.unexpectedMutation }
        let original = snapshots[index]
        let completed = HealthCheckReminderSnapshot(
            id: original.id,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt.addingTimeInterval(1),
            name: original.name,
            dueDate: original.dueDate,
            recurrence: original.recurrence,
            status: .done
        )
        snapshots[index] = completed
        record(.complete)
        return HealthCheckCompletionMutation(
            completed: completed,
            successor: nil,
            undoToken: HealthCheckCompletionUndoToken(
                original: original,
                completedUpdatedAt: completed.updatedAt,
                successorID: nil,
                successorUpdatedAt: nil
            )
        )
    }

    func undoCompletion(
        _ token: HealthCheckCompletionUndoToken
    ) async throws -> HealthCheckReminderSnapshot {
        await suspendIfRequested(.undo)
        try failIfRequested(.undo)
        snapshots.removeAll { $0.id == token.original.id }
        snapshots.append(token.original)
        record(.undo)
        return token.original
    }

    private func failIfRequested(_ operation: MutationOperation) throws {
        guard failingMutationOperations.remove(operation) != nil else { return }
        throw Failure.injectedMutation
    }

    private func record(_ operation: MutationOperation) {
        mutationCount += 1
        mutationOperations.append(operation)
    }

    func waitUntilMutationIsSuspended(_ operation: MutationOperation) async {
        if suspendedMutationContinuations[operation] != nil { return }
        await withCheckedContinuation { continuation in
            suspendedMutationWaiters[operation, default: []].append(continuation)
        }
    }

    func resumeMutation(_ operation: MutationOperation) {
        suspendedMutationContinuations.removeValue(forKey: operation)?.resume()
    }

    private func suspendIfRequested(_ operation: MutationOperation) async {
        guard suspendedMutationOperations.remove(operation) != nil else { return }
        let waiters = suspendedMutationWaiters.removeValue(forKey: operation) ?? []
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            suspendedMutationContinuations[operation] = continuation
        }
    }
}

private actor DefaultCompositionOwnerNotificationCenterFake: NotificationCenterClient {
    struct OwnershipSignal: Sendable {
        let authorizationStatusCount: Int
        let cancelledFirstCall: Bool
    }

    struct Snapshot: Sendable {
        let pending: [NotificationRequestValue]
        let authorizationRequestCount: Int
    }

    private var pending: [String: NotificationRequestValue] = [:]
    private var delivered: Set<String> = []
    private var authorizationStatusCount = 0
    private var authorizationStatusContinuations: [
        Int: CheckedContinuation<Void, Never>
    ] = [:]
    private var cancelledAuthorizationCalls: Set<Int> = []
    private var authorizationRequestCount = 0

    func authorizationStatus() async throws -> NotificationAuthorizationStatus {
        authorizationStatusCount += 1
        let call = authorizationStatusCount
        if call == 1 {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    authorizationStatusContinuations[call] = continuation
                }
            } onCancel: {
                Task { await self.recordCancellation(call: call) }
            }
        }
        return .authorized
    }

    func pendingRequests() async throws -> [PendingNotificationRequestValue] {
        pending.values
            .map { .init(identifier: $0.identifier, request: $0) }
            .sorted { $0.identifier < $1.identifier }
    }

    func deliveredRequestIdentifiers() async throws -> Set<String> { delivered }

    func removePendingRequests(withIdentifiers identifiers: [String]) async throws {
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
        }
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws {
        delivered.subtract(identifiers)
    }

    func add(_ request: NotificationRequestValue) async throws {
        pending[request.identifier] = request
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return false
    }

    func waitUntilAuthorizationStatus(call: Int) async -> Bool {
        for _ in 0..<200 {
            if authorizationStatusCount >= call { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return authorizationStatusCount >= call
    }

    func waitForCancellationOrSecondAuthorizationStatus() async -> OwnershipSignal {
        for _ in 0..<200 {
            if cancelledAuthorizationCalls.contains(1) || authorizationStatusCount >= 2 {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return OwnershipSignal(
            authorizationStatusCount: authorizationStatusCount,
            cancelledFirstCall: cancelledAuthorizationCalls.contains(1)
        )
    }

    func resumeAuthorizationStatus(call: Int) {
        authorizationStatusContinuations.removeValue(forKey: call)?.resume()
    }

    func snapshot() -> Snapshot {
        Snapshot(
            pending: pending.values.sorted { $0.identifier < $1.identifier },
            authorizationRequestCount: authorizationRequestCount
        )
    }

    private func recordCancellation(call: Int) {
        cancelledAuthorizationCalls.insert(call)
    }
}

private actor PermissionPreservingNotificationCenterFake: NotificationCenterClient {
    struct Snapshot: Sendable {
        let authorizationStatusCount: Int
        let addCount: Int
        let authorizationRequestCount: Int
    }

    private let status: NotificationAuthorizationStatus
    private var authorizationStatusCount = 0
    private var addCount = 0
    private var authorizationRequestCount = 0

    init(status: NotificationAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async throws -> NotificationAuthorizationStatus {
        authorizationStatusCount += 1
        return status
    }

    func pendingRequests() async throws -> [PendingNotificationRequestValue] { [] }

    func deliveredRequestIdentifiers() async throws -> Set<String> { [] }

    func removePendingRequests(withIdentifiers identifiers: [String]) async throws {
        _ = identifiers
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws {
        _ = identifiers
    }

    func add(_ request: NotificationRequestValue) async throws {
        _ = request
        addCount += 1
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return false
    }

    func waitUntilAuthorizationStatus(call: Int) async -> Bool {
        for _ in 0..<100 {
            if authorizationStatusCount >= call { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return authorizationStatusCount >= call
    }

    func snapshot() -> Snapshot {
        Snapshot(
            authorizationStatusCount: authorizationStatusCount,
            addCount: addCount,
            authorizationRequestCount: authorizationRequestCount
        )
    }
}

private actor CompositionNotificationSystemBackendFake: NotificationCenterSystemBackend {
    struct Snapshot: Sendable {
        let pending: [String: PendingNotificationSystemRequest]
        let addedRequests: [NotificationSystemRequest]
        let authorizationRequestCount: Int
    }

    private var pending: [String: PendingNotificationSystemRequest] = [:]
    private var delivered: Set<String> = []
    private var addedRequests: [NotificationSystemRequest] = []
    private var authorizationRequestCount = 0

    func authorizationStatus() async throws -> NotificationAuthorizationStatus {
        .authorized
    }

    func pendingRequests() async throws -> [PendingNotificationSystemRequest] {
        pending.values.sorted { $0.identifier < $1.identifier }
    }

    func deliveredRequestIdentifiers() async throws -> Set<String> {
        delivered
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async throws {
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
        }
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws {
        delivered.subtract(identifiers)
    }

    func add(_ request: NotificationSystemRequest) async throws {
        pending[request.identifier] = .init(
            identifier: request.identifier,
            request: request
        )
        addedRequests.append(request)
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return true
    }

    func snapshot() -> Snapshot {
        Snapshot(
            pending: pending,
            addedRequests: addedRequests,
            authorizationRequestCount: authorizationRequestCount
        )
    }
}

private actor CompositionAuthorizationCenterFake: NotificationCenterClient {
    enum Failure: Error {
        case unexpectedReconciliationOperation
        case missingRequest
    }

    private var requestCount = 0
    private var requestContinuations: [
        Int: CheckedContinuation<Bool, Never>
    ] = [:]
    private var requestWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    var authorizationRequestCount: Int { requestCount }

    func authorizationStatus() async throws -> NotificationAuthorizationStatus {
        throw Failure.unexpectedReconciliationOperation
    }

    func pendingRequests() async throws -> [PendingNotificationRequestValue] {
        throw Failure.unexpectedReconciliationOperation
    }

    func deliveredRequestIdentifiers() async throws -> Set<String> {
        throw Failure.unexpectedReconciliationOperation
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async throws {
        _ = identifiers
        throw Failure.unexpectedReconciliationOperation
    }

    func removeDeliveredRequests(withIdentifiers identifiers: [String]) async throws {
        _ = identifiers
        throw Failure.unexpectedReconciliationOperation
    }

    func add(_ request: NotificationRequestValue) async throws {
        _ = request
        throw Failure.unexpectedReconciliationOperation
    }

    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        let call = requestCount
        let waiters = requestWaiters.removeValue(forKey: call) ?? []
        for waiter in waiters {
            waiter.resume()
        }
        return await withCheckedContinuation { continuation in
            requestContinuations[call] = continuation
        }
    }

    func waitUntilAuthorizationRequest(call: Int) async {
        if requestCount >= call { return }
        await withCheckedContinuation { continuation in
            requestWaiters[call, default: []].append(continuation)
        }
    }

    func resumeAuthorizationRequest(call: Int, granted: Bool) throws {
        guard let continuation = requestContinuations.removeValue(forKey: call) else {
            throw Failure.missingRequest
        }
        continuation.resume(returning: granted)
    }
}

private actor HealthCheckNotificationReconcilerSpy: HealthCheckNotificationReconciling {
    enum Failure: Error {
        case injected
    }

    private(set) var invocations: [[HealthCheckNotificationDescriptor]] = []
    private(set) var committedDescriptors: [HealthCheckNotificationDescriptor] = []
    private(set) var attemptCount = 0
    private var failingCalls: Set<Int>
    private let suspendedCalls: Set<Int>
    private let nonCancellableSuspendedCalls: Set<Int>
    private var suspendedContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var cancelledCalls: Set<Int> = []

    init(
        failingCalls: Set<Int> = [],
        suspendedCalls: Set<Int> = [],
        nonCancellableSuspendedCalls: Set<Int> = []
    ) {
        self.failingCalls = failingCalls
        self.suspendedCalls = suspendedCalls
        self.nonCancellableSuspendedCalls = nonCancellableSuspendedCalls
    }

    func reconcile(
        _ descriptors: [HealthCheckNotificationDescriptor]
    ) async throws -> NotificationReconciliationResult {
        attemptCount += 1
        let call = attemptCount
        if suspendedCalls.contains(call) || nonCancellableSuspendedCalls.contains(call) {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    suspendedContinuations[call] = continuation
                }
            } onCancel: {
                Task { await self.recordCancellation(call: call) }
            }
        }
        if !nonCancellableSuspendedCalls.contains(call) {
            try Task.checkCancellation()
        }
        if failingCalls.remove(call) != nil {
            throw Failure.injected
        }
        invocations.append(descriptors)
        committedDescriptors = descriptors
        return .converged(added: 0, removedPending: 0, removedDelivered: 0)
    }

    func waitUntilReconciliation(call: Int) async -> Bool {
        for _ in 0..<200 {
            if attemptCount >= call { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return attemptCount >= call
    }

    func resumeReconciliation(call: Int) {
        suspendedContinuations.removeValue(forKey: call)?.resume()
    }

    func waitUntilCancellation(call: Int) async -> Bool {
        for _ in 0..<200 {
            if cancelledCalls.contains(call) { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return cancelledCalls.contains(call)
    }

    private func recordCancellation(call: Int) {
        cancelledCalls.insert(call)
    }
}

@MainActor
private final class NotificationTrackerRouterSpy: TrackerFeatureRouting {
    private(set) var launchReconciliationCount = 0

    func reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent() async throws {
        launchReconciliationCount += 1
    }

    func reconcileHealthCheckNotificationsAfterCommittedMutation() async throws {}

    func requestHealthCheckNotificationAuthorizationFromExplicitUserAction() async {}

    func makeBodyMetricEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        _ = onClose
        return AnyView(EmptyView())
    }

    func makeLifestyleEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        _ = onClose
        return AnyView(EmptyView())
    }

    func makePostureEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        _ = onClose
        return AnyView(EmptyView())
    }

    func makeHealthCheckListView(
        onCommittedMutation: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        _ = (onCommittedMutation, onClose)
        return AnyView(EmptyView())
    }

    func makeBloodworkListView(
        onCommittedMutation: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        _ = (onCommittedMutation, onClose)
        return AnyView(EmptyView())
    }

    func makeProgressPhotoLifecycleView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView {
        _ = onClose
        return AnyView(EmptyView())
    }

    func makeProgressView(
        onOpenBloodwork: @escaping @MainActor () -> Void,
        onOpenProgressPhotos: @escaping @MainActor () -> Void
    ) -> AnyView {
        _ = (onOpenBloodwork, onOpenProgressPhotos)
        return AnyView(EmptyView())
    }
}
