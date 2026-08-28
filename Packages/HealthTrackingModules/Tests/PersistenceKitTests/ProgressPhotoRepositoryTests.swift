import CoreModels
import Foundation
@testable import ProgressPhotosKit
import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class ProgressPhotoRepositoryTests: XCTestCase {
    func testImportPersistsOnlyOpaqueAssetIDAndNormalizedMetadata() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000037"
        let assetStore = ProgressPhotoAssetStoreFake(
            importResults: [.success(.init(assetID: assetID))]
        )
        let timestamp = Date(timeIntervalSince1970: 300)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            now: { timestamp },
            makeID: { id }
        )
        let bytes = Data([0xde, 0xad, 0xbe, 0xef])
        let input = try ProgressPhotoInput(
            date: Date(timeIntervalSince1970: 200),
            pose: .side,
            note: "  Aylık kayıt  "
        )

        let snapshot = try await repository.importPhoto(input, bytes: bytes)

        XCTAssertEqual(assetStore.importRequests, [bytes])
        XCTAssertEqual(snapshot.id, id)
        XCTAssertEqual(snapshot.imageRef, assetID)
        XCTAssertEqual(snapshot.note, "Aylık kayıt")
        XCTAssertFalse(snapshot.imageRef.hasPrefix("/"))
        XCTAssertFalse(snapshot.imageRef.contains("file:"))
        let models = try context.fetch(FetchDescriptor<ProgressPhoto>())
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].imageRef, assetID)
        XCTAssertFalse(
            Mirror(reflecting: models[0]).children.contains { $0.value is Data },
            "SwiftData metadata must never persist photo binary data."
        )
    }

    func testThumbnailAndFullImageUseExplicitAssetVariants() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000036"
        let assetStore = ProgressPhotoAssetStoreFake(
            loadResults: [
                .success(.available(Data([1]))),
                .success(.available(Data([2]))),
            ]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )

        let thumbnail = try await repository.thumbnail(assetID: assetID)
        let fullImage = try await repository.fullImage(assetID: assetID)

        XCTAssertEqual(thumbnail, .available(Data([1])))
        XCTAssertEqual(fullImage, .available(Data([2])))
        XCTAssertEqual(assetStore.loadRequests, [
            .init(id: assetID, variant: .thumbnail),
            .init(id: assetID, variant: .full),
        ])
    }

    func testMetadataSaveFailureDeletesImportedAssetAndRollsBackModel() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000038"
        let assetStore = ProgressPhotoAssetStoreFake(
            importResults: [.success(.init(assetID: assetID))]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            save: { throw FixtureError.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.importPhoto(
                try ProgressPhotoInput(date: .now, pose: .front, note: nil),
                bytes: Data([1])
            )
            XCTFail("A metadata save failure must fail the import.")
        } catch {
            XCTAssertEqual(error as? ProgressPhotoRepositoryOperationError, .saveFailed)
        }

        XCTAssertEqual(assetStore.deleteRequests, [assetID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProgressPhoto>()).isEmpty)
    }

    func testProtectedCleanupFailureRemainsPendingUntilExactRetrySucceeds() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000039"
        let journal = PhotoAssetCleanupJournalFake()
        let firstAssetStore = ProgressPhotoAssetStoreFake(
            importResults: [.success(.init(assetID: assetID))],
            deleteResults: [.failure(.protectedDataUnavailable)]
        )
        let firstRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: firstAssetStore,
            cleanupJournal: journal,
            save: { throw FixtureError.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await firstRepository.importPhoto(
                try ProgressPhotoInput(date: .now, pose: .back, note: nil),
                bytes: Data([1])
            )
            XCTFail("The imported file still requires protected-data cleanup.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryOperationError,
                .metadataSaveFailedCleanupPending(assetID: assetID)
            )
        }
        XCTAssertEqual(firstRepository.pendingAssetCleanupIDs, [assetID])
        let persistedAfterFailure = try await journal.loadPendingAssetIDs()
        XCTAssertEqual(persistedAfterFailure, [assetID])

        let relaunchedAssetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [.success(())],
            localAssetIDs: [assetID]
        )
        let relaunchedRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: relaunchedAssetStore,
            cleanupJournal: journal
        )

        _ = try await relaunchedRepository.fetchPhotos()

        XCTAssertTrue(relaunchedRepository.pendingAssetCleanupIDs.isEmpty)
        let persistedAfterRelaunch = try await journal.loadPendingAssetIDs()
        XCTAssertEqual(persistedAfterRelaunch, [])
        XCTAssertEqual(firstAssetStore.deleteRequests, [assetID])
        XCTAssertEqual(relaunchedAssetStore.deleteRequests, [assetID])
    }

    func testJournalAndImmediateDeleteFailureQueuesOrphanForCurrentProcessRetry() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000066"
        let assetStore = ProgressPhotoAssetStoreFake(
            importResults: [.success(.init(assetID: assetID))],
            deleteResults: [
                .failure(.protectedDataUnavailable),
                .success(()),
            ]
        )
        let journal = PhotoAssetCleanupJournalFake(addError: FixtureError.save)
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: journal
        )

        do {
            _ = try await repository.importPhoto(
                try ProgressPhotoInput(date: .now, pose: .front, note: nil),
                bytes: Data([1])
            )
            XCTFail("An unjournaled asset must not report a successful import.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryOperationError,
                .cleanupJournalFailed(assetID: assetID)
            )
        }
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetID])
        XCTAssertEqual(assetStore.deleteRequests, [assetID])

        journal.addError = nil
        try await repository.retryPendingAssetCleanup()

        XCTAssertTrue(repository.pendingAssetCleanupIDs.isEmpty)
        XCTAssertEqual(assetStore.deleteRequests, [assetID, assetID])
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)
    }

    func testJournalAndDeleteCompensationFailureQueuesOrphanForRetry() async throws {
        let context = try makeContext()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000073")!
        let assetID = "00000000-0000-0000-0000-000000000067"
        let timestamp = Date(timeIntervalSince1970: 670)
        context.insert(
            ProgressPhoto(
                id: id,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [.success(())],
            localAssetIDs: [assetID]
        )
        let journal = PhotoAssetCleanupJournalFake(addError: FixtureError.save)
        var saveCallCount = 0
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: journal,
            save: {
                saveCallCount += 1
                if saveCallCount == 2 { throw FixtureError.save }
                try context.save()
            },
            rollback: { context.rollback() }
        )

        do {
            try await repository.deletePhoto(
                id: id,
                expectedUpdatedAt: timestamp
            )
            XCTFail("Failed metadata compensation must leave cleanup retryable.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryOperationError,
                .deleteCompensationFailed
            )
        }
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProgressPhoto>()).isEmpty)

        journal.addError = nil
        try await repository.retryPendingAssetCleanup()

        XCTAssertTrue(repository.pendingAssetCleanupIDs.isEmpty)
        XCTAssertEqual(assetStore.deleteRequests, [assetID])
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)
    }

    func testStartupReconciliationKeepsReferencedAssetAndDeletesCrashWindowOrphan() async throws {
        let context = try makeContext()
        let referencedID = "00000000-0000-0000-0000-000000000061"
        let orphanID = "00000000-0000-0000-0000-000000000062"
        let date = Date(timeIntervalSince1970: 620)
        context.insert(
            ProgressPhoto(
                id: UUID(),
                createdAt: date,
                updatedAt: date,
                date: date,
                imageRef: referencedID,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let journal = PhotoAssetCleanupJournalFake(
            pendingAssetIDs: [referencedID, orphanID]
        )
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [.success(())],
            localAssetIDs: [referencedID, orphanID]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: journal
        )

        let snapshots = try await repository.fetchPhotos()

        XCTAssertEqual(snapshots.map(\.imageRef), [referencedID])
        XCTAssertEqual(assetStore.deleteRequests, [orphanID])
        XCTAssertEqual(assetStore.localAssetIDs, [referencedID])
        let persistedAfterReconciliation = try await journal.loadPendingAssetIDs()
        XCTAssertEqual(persistedAfterReconciliation, [])
    }

    func testStartupInventoryDeletesUnjournaledOrphanFromRenameCrashWindow() async throws {
        let context = try makeContext()
        let orphanID = "00000000-0000-0000-0000-000000000063"
        let journal = PhotoAssetCleanupJournalFake()
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [.success(())],
            localAssetIDs: [orphanID]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: journal
        )

        _ = try await repository.fetchPhotos()

        XCTAssertEqual(assetStore.deleteRequests, [orphanID])
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)
        let persistedAfterReconciliation = try await journal.loadPendingAssetIDs()
        XCTAssertEqual(persistedAfterReconciliation, [])
    }

    func testInboundRestoreProtectsPreviouslyFailedOrphanFromCleanupRetry() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-00000000007a"
        let bytes = Data([7, 10])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundURL = directory.appendingPathComponent("cloud-inbound.json")
        let inboundJournal = FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        let cleanupJournal = PhotoAssetCleanupJournalFake()
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [.failure(.protectedDataUnavailable)],
            localAssetIDs: [assetID],
            cloudAssets: [assetID: bytes],
            requiredInboundJournal: inboundJournal
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: cleanupJournal,
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetJournal: inboundJournal
        )

        _ = try await repository.fetchPhotos()
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetID])
        XCTAssertEqual(assetStore.deleteRequests, [assetID])

        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: directory.appendingPathComponent("transfers", isDirectory: true)
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: bytes)
        let record = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            stagedFileURL: stagedURL
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: PersistenceCloudPhotoAssetDatabaseFake(
                changePage: .init(
                    changes: [.changed(record)],
                    changeToken: Data([7, 10]),
                    moreComing: false
                )
            ),
            localStore: assetStore,
            stateStore: FileCloudPhotoAssetSyncStateStore(
                fileURL: directory.appendingPathComponent("cloud-state.json")
            ),
            referenceSnapshotProvider: PersistenceCloudPhotoReferenceProvider(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: inboundJournal,
                localStore: assetStore
            ),
            temporaryStore: temporaryStore
        )

        _ = try await coordinator.synchronize()
        try await repository.retryPendingAssetCleanup()
        let pendingCleanup = try await cleanupJournal.loadPendingAssetIDs()
        let pendingInbound = try await inboundJournal.pendingInboundAssetIDs()

        XCTAssertEqual(
            assetStore.deleteRequests,
            [assetID],
            "Fresh inbound ownership must suppress an older cleanup retry."
        )
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetID])
        XCTAssertEqual(pendingCleanup, [assetID])
        XCTAssertEqual(pendingInbound, [assetID])
        XCTAssertEqual(assetStore.localAssetIDs, [assetID])
        XCTAssertEqual(assetStore.cloudAssets[assetID], bytes)
    }

    func testInitialOrphanSweepRereadsInboundOwnershipAtDeleteBoundary() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-00000000007b"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: directory.appendingPathComponent("cloud-inbound.json")
        )
        let cleanupJournal = PhotoAssetCleanupJournalFake()
        let assetStore = InterleavingProgressPhotoAssetStore(assetID: assetID)
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: cleanupJournal,
            inboundAssetJournal: inboundJournal
        )

        let fetchTask = Task { try await repository.fetchPhotos() }
        await waitForInventoryCallCount(1, in: assetStore)
        try await inboundJournal.recordInboundAssetID(assetID)
        await assetStore.resumeInventory(with: [assetID])
        _ = try await fetchTask.value
        let callCounts = await assetStore.callCounts()
        let pendingInbound = try await inboundJournal.pendingInboundAssetIDs()
        let pendingCleanup = try await cleanupJournal.loadPendingAssetIDs()

        XCTAssertTrue(callCounts.deletes.isEmpty)
        XCTAssertEqual(pendingInbound, [assetID])
        XCTAssertTrue(pendingCleanup.isEmpty)
        XCTAssertTrue(repository.pendingAssetCleanupIDs.isEmpty)
    }

    func testInboundJournalReadFailureStopsPendingCleanupRetryBeforeDelete() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-00000000007c"
        let inboundJournal = SequencedCloudPhotoAssetInboundJournal(
            pendingResults: [
                .success([]),
                .success([]),
                .success([]),
                .failure(.inboundRead),
            ]
        )
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [
                .failure(.protectedDataUnavailable),
                .success(()),
            ],
            localAssetIDs: [assetID]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            inboundAssetJournal: inboundJournal
        )

        _ = try await repository.fetchPhotos()
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetID])

        do {
            try await repository.retryPendingAssetCleanup()
            XCTFail("A fresh inbound-journal failure must fail closed before retry deletion.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryOperationError,
                .cleanupJournalFailed(assetID: nil)
            )
        }

        XCTAssertEqual(assetStore.deleteRequests, [assetID])
        XCTAssertEqual(assetStore.localAssetIDs, [assetID])
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetID])
    }

    func testCleanupRetryRechecksInboundOwnershipAfterEarlierAssetDeleteSuspends() async throws {
        let context = try makeContext()
        let assetA = "00000000-0000-0000-0000-00000000007d"
        let assetB = "00000000-0000-0000-0000-00000000007e"
        let bytesB = Data([7, 14])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: directory.appendingPathComponent("cloud-inbound.json")
        )
        let cleanupJournal = PhotoAssetCleanupJournalFake()
        let assetStore = CleanupLeaseInterleavingAssetStore(
            assets: [assetA: Data([7, 13]), assetB: Data([7, 13])],
            initialDeleteFailures: [assetA: 1, assetB: 1]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: cleanupJournal,
            inboundAssetJournal: inboundJournal
        )

        _ = try await repository.fetchPhotos()
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetA, assetB])
        await assetStore.suspendNextDelete(of: assetA)

        let retryTask = Task { try await repository.retryPendingAssetCleanup() }
        let didSuspendA = await assetStore.waitUntilDeleteIsSuspended(assetA)
        guard didSuspendA else {
            await assetStore.resumeSuspendedDelete(of: assetA)
            retryTask.cancel()
            _ = try? await retryTask.value
            XCTFail("The cleanup retry did not reach the requested delete suspension.")
            return
        }
        try await inboundJournal.recordInboundAssetID(assetB)
        await assetStore.restoreAsset(id: assetB, bytes: bytesB)
        await assetStore.resumeSuspendedDelete(of: assetA)
        try await retryTask.value

        let snapshot = await assetStore.snapshot()
        let pendingInbound = try await inboundJournal.pendingInboundAssetIDs()
        let pendingCleanup = try await cleanupJournal.loadPendingAssetIDs()
        XCTAssertEqual(snapshot.deleteRequests, [assetA, assetB, assetA])
        XCTAssertNil(snapshot.assets[assetA])
        XCTAssertEqual(snapshot.assets[assetB], bytesB)
        XCTAssertEqual(pendingInbound, [assetB])
        XCTAssertEqual(pendingCleanup, [assetB])
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetB])
    }

    func testInboundRecordWaitsForCleanupLeaseAndRestoreSurvivesDeleteBoundary() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-00000000007f"
        let restoredBytes = Data([7, 15])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: directory.appendingPathComponent("cloud-inbound.json")
        )
        let cleanupJournal = PhotoAssetCleanupJournalFake()
        let assetStore = CleanupLeaseInterleavingAssetStore(
            assets: [assetID: Data([7, 0])],
            initialDeleteFailures: [assetID: 1]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: cleanupJournal,
            inboundAssetJournal: inboundJournal
        )

        _ = try await repository.fetchPhotos()
        await assetStore.suspendNextDelete(of: assetID)
        let retryTask = Task { try await repository.retryPendingAssetCleanup() }
        let didSuspendDelete = await assetStore.waitUntilDeleteIsSuspended(assetID)
        guard didSuspendDelete else {
            await assetStore.resumeSuspendedDelete(of: assetID)
            retryTask.cancel()
            _ = try? await retryTask.value
            XCTFail("The cleanup retry did not reach the requested delete suspension.")
            return
        }

        let completion = CloudDeletionCompletionProbe()
        let restoreTask = Task {
            try await inboundJournal.recordInboundAssetID(assetID)
            await assetStore.restoreAsset(id: assetID, bytes: restoredBytes)
            await completion.markFinished()
        }
        let exactWaiterID = try await inboundJournal.waitForInboundRecordWaiter(
            for: assetID
        )
        let observedWaiters = try await inboundJournal.inboundRecordWaiterIDs(
            for: assetID
        )
        XCTAssertEqual(
            observedWaiters,
            [exactWaiterID],
            "The test must observe recordInbound blocked on the exact held cleanup lease."
        )
        let returnedBeforeLeaseRelease = await completion.isFinished
        XCTAssertFalse(
            returnedBeforeLeaseRelease,
            "Inbound ownership and restore must wait until cleanup releases its atomic lease."
        )

        await assetStore.resumeSuspendedDelete(of: assetID)
        try await retryTask.value
        try await restoreTask.value

        let snapshot = await assetStore.snapshot()
        let pendingInbound = try await inboundJournal.pendingInboundAssetIDs()
        let pendingCleanup = try await cleanupJournal.loadPendingAssetIDs()
        XCTAssertEqual(snapshot.assets[assetID], restoredBytes)
        XCTAssertEqual(snapshot.deleteRequests, [assetID, assetID])
        XCTAssertEqual(pendingInbound, [assetID])
        XCTAssertTrue(pendingCleanup.isEmpty)
        XCTAssertTrue(repository.pendingAssetCleanupIDs.isEmpty)
    }

    func testCancelledInboundRecordRemovesExactWaiterAndAllowsLaterCleanupLease() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: directory.appendingPathComponent("cloud-inbound.json")
        )
        let assetID = "00000000-0000-0000-0000-000000000945"
        let heldLeaseValue = try await inboundJournal.acquireCleanupLease(
            for: assetID
        )
        let heldLease = try XCTUnwrap(heldLeaseValue)

        let recordTask = Task {
            try await inboundJournal.recordInboundAssetID(assetID)
        }
        let exactWaiterID = try await inboundJournal.waitForInboundRecordWaiter(
            for: assetID
        )
        let waitersBeforeCancellation = try await inboundJournal
            .inboundRecordWaiterIDs(for: assetID)
        XCTAssertEqual(waitersBeforeCancellation, [exactWaiterID])

        recordTask.cancel()
        do {
            try await recordTask.value
            XCTFail("A cancelled inbound record must finish before lease release.")
        } catch is CancellationError {
            // Expected identified waiter cancellation.
        }

        let waitersAfterCancellation = try await inboundJournal
            .inboundRecordWaiterIDs(for: assetID)
        let pendingBeforeLeaseRelease = try await inboundJournal
            .pendingInboundAssetIDs()
        XCTAssertTrue(waitersAfterCancellation.isEmpty)
        XCTAssertTrue(pendingBeforeLeaseRelease.isEmpty)

        await inboundJournal.releaseCleanupLease(heldLease)
        let laterLeaseValue = try await inboundJournal.acquireCleanupLease(
            for: assetID
        )
        let laterLease = try XCTUnwrap(laterLeaseValue)
        await inboundJournal.releaseCleanupLease(laterLease)
        let pendingAfterLaterLease = try await inboundJournal
            .pendingInboundAssetIDs()
        XCTAssertTrue(pendingAfterLaterLease.isEmpty)
    }

    func testCommittedMetadataDeletionPersistsUntilCloudRetrySucceedsAfterRelaunch() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000068"
        let photoID = UUID(uuidString: "00000000-0000-0000-0000-000000000074")!
        let timestamp = Date(timeIntervalSince1970: 680)
        context.insert(
            ProgressPhoto(
                id: photoID,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let deletionURL = directory.appendingPathComponent("cloud-deletions.json")
        let stateURL = directory.appendingPathComponent("state.json")
        let inboundURL = directory.appendingPathComponent("cloud-inbound.json")
        let assetStore = ProgressPhotoAssetStoreFake(
            localAssetIDs: [assetID],
            cloudAssets: [assetID: Data([6, 8])]
        )
        let firstDeletionStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        )
        let firstResolution = await firstDeletionStore.beginAccountResolution()
        _ = try await firstDeletionStore.activateAccountIdentity(
            "opaque-account-a",
            resolution: firstResolution
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: firstDeletionStore,
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        )

        try await repository.deletePhoto(id: photoID, expectedUpdatedAt: timestamp)
        let pendingAfterMetadataCommit = try await FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        ).pendingDeletionAssetIDs(forAccountIdentity: "opaque-account-a")

        XCTAssertEqual(pendingAfterMetadataCommit, [assetID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProgressPhoto>()).isEmpty)

        let initialState = FileCloudPhotoAssetSyncStateStore(fileURL: stateURL)
        try await initialState.save(
            .init(accountIdentity: "opaque-account-a", uploadedAssetIDs: [assetID])
        )
        let firstDatabase = PersistenceCloudPhotoAssetDatabaseFake(
            deleteResults: [.failure(.permanent)]
        )
        let firstCoordinator = CloudPhotoAssetCoordinator(
            database: firstDatabase,
            localStore: assetStore,
            stateStore: initialState,
            referenceSnapshotProvider: PersistenceCloudPhotoReferenceProvider(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: deletionURL
            ),
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL),
                localStore: assetStore
            ),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("first-transfers", isDirectory: true)
            )
        )

        do {
            _ = try await firstCoordinator.synchronize()
            XCTFail("Failed cloud deletion must remain durable for relaunch retry.")
        } catch {
            XCTAssertEqual(error as? CloudPhotoAssetDatabaseError, .permanent)
        }
        let pendingAfterFailure = try await FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        ).pendingDeletionAssetIDs(forAccountIdentity: "opaque-account-a")
        let firstDeleteRequests = await firstDatabase.deleteRequests
        XCTAssertEqual(pendingAfterFailure, [assetID])
        XCTAssertEqual(firstDeleteRequests, ["progress-photo-asset-\(assetID)"])

        let retryDatabase = PersistenceCloudPhotoAssetDatabaseFake()
        let retryDeletionStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        )
        let retryCoordinator = CloudPhotoAssetCoordinator(
            database: retryDatabase,
            localStore: assetStore,
            stateStore: FileCloudPhotoAssetSyncStateStore(fileURL: stateURL),
            referenceSnapshotProvider: PersistenceCloudPhotoReferenceProvider(),
            deletionIntentStore: retryDeletionStore,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL),
                localStore: assetStore
            ),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("retry-transfers", isDirectory: true)
            )
        )

        _ = try await retryCoordinator.synchronize()
        let retriedDeletes = await retryDatabase.deleteRequests
        let pendingAfterSuccess = try await retryDeletionStore.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )
        let stateAfterSuccess = try await FileCloudPhotoAssetSyncStateStore(
            fileURL: stateURL
        ).load()

        XCTAssertEqual(retriedDeletes, ["progress-photo-asset-\(assetID)"])
        XCTAssertTrue(pendingAfterSuccess.isEmpty)
        XCTAssertTrue(stateAfterSuccess.pendingDeletionAssetIDs.isEmpty)
        XCTAssertTrue(stateAfterSuccess.uploadedAssetIDs.isEmpty)
    }

    func testMetadataDeleteSaveFailureNeverCreatesCloudDeletionIntent() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-00000000006b"
        let photoID = UUID(uuidString: "00000000-0000-0000-0000-000000000077")!
        let timestamp = Date(timeIntervalSince1970: 681)
        context.insert(
            ProgressPhoto(
                id: photoID,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let deletionURL = directory.appendingPathComponent("cloud-deletions.json")
        let durableIntentStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        )
        let deletionIntentStore = RecordingCloudPhotoAssetDeletionIntentStore(
            backing: durableIntentStore
        )
        let assetStore = ProgressPhotoAssetStoreFake(localAssetIDs: [assetID])
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: deletionIntentStore,
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(
                fileURL: directory.appendingPathComponent("cloud-inbound.json")
            ),
            save: { throw FixtureError.save },
            rollback: { context.rollback() }
        )

        do {
            try await repository.deletePhoto(
                id: photoID,
                expectedUpdatedAt: timestamp
            )
            XCTFail("An uncommitted metadata deletion must not create cloud intent.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryOperationError,
                .saveFailed
            )
        }
        let pending = try await FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        ).unresolvedDeletionAssetIDs()
        let intentCalls = await deletionIntentStore.calls()
        let persisted = try context.fetch(FetchDescriptor<ProgressPhoto>())

        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(intentCalls.recordCalls, [])
        XCTAssertEqual(intentCalls.clearCalls, [])
        XCTAssertEqual(intentCalls.accountClearCalls, [])
        XCTAssertEqual(persisted.map(\.id), [photoID])
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)
    }

    func testCompensatedLocalDeleteFailureClearsCloudIntentBeforeReturning() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ProgressPhoto.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let assetID = "00000000-0000-0000-0000-00000000006c"
        let photoID = UUID(uuidString: "00000000-0000-0000-0000-000000000078")!
        let timestamp = Date(timeIntervalSince1970: 682)
        context.insert(
            ProgressPhoto(
                id: photoID,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .side,
                note: nil
            )
        )
        try context.save()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let deletionURL = directory.appendingPathComponent("cloud-deletions.json")
        let durableIntentStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        )
        let recordingIntentStore = RecordingCloudPhotoAssetDeletionIntentStore(
            backing: durableIntentStore
        )
        let compensationResolution = await recordingIntentStore
            .beginAccountResolution()
        _ = try await recordingIntentStore.activateAccountIdentity(
            "opaque-account-a",
            resolution: compensationResolution
        )
        let trace = CloudDeletionOperationTrace()
        let blockingIntentStore = BlockingCloudPhotoAssetDeletionIntentStore(
            backing: recordingIntentStore,
            trace: trace
        )
        let completion = CloudDeletionCompletionProbe()
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [.failure(.protectedDataUnavailable)],
            localAssetIDs: [assetID],
            deleteObserver: { _ in trace.append(.localDeleteAttempted) }
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: blockingIntentStore,
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(
                fileURL: directory.appendingPathComponent("cloud-inbound.json")
            ),
            save: {
                try context.save()
                let persistedContext = ModelContext(container)
                let persistedPhotoIDs = try persistedContext.fetch(
                    FetchDescriptor<ProgressPhoto>()
                ).map(\.id).sorted {
                    $0.uuidString < $1.uuidString
                }
                trace.append(.persistedPhotoIDs(persistedPhotoIDs))
            },
            rollback: { context.rollback() }
        )

        let deletion = Task { @MainActor in
            do {
                try await repository.deletePhoto(
                    id: photoID,
                    expectedUpdatedAt: timestamp
                )
                XCTFail("The local delete fixture must fail.")
            } catch {
                XCTAssertEqual(
                    error as? ProgressPhotoRepositoryOperationError,
                    .protectedDataUnavailable
                )
            }
            await completion.markFinished()
        }
        let clearWasAttempted = await blockingIntentStore.waitUntilClearAttempted()
        guard clearWasAttempted else {
            deletion.cancel()
            return XCTFail("Timed out waiting for compensated intent cleanup.")
        }

        let pendingBeforeClear = try await FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        ).pendingDeletionAssetIDs(forAccountIdentity: "opaque-account-a")
        let returnedBeforeClear = await completion.isFinished
        XCTAssertEqual(pendingBeforeClear, [assetID])
        XCTAssertFalse(returnedBeforeClear)
        XCTAssertEqual(
            trace.snapshot(),
            [
                .persistedPhotoIDs([]),
                .intentRecorded,
                .localDeleteAttempted,
                .persistedPhotoIDs([photoID]),
                .intentClearStarted,
            ]
        )

        await blockingIntentStore.resumeClear()
        await deletion.value
        let pendingAfterReturn = try await FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        ).pendingDeletionAssetIDs(forAccountIdentity: "opaque-account-a")
        let intentCalls = await recordingIntentStore.calls()
        let persisted = try context.fetch(FetchDescriptor<ProgressPhoto>())

        XCTAssertTrue(pendingAfterReturn.isEmpty)
        XCTAssertEqual(intentCalls.recordCalls, [assetID])
        XCTAssertEqual(intentCalls.clearCalls, [assetID])
        XCTAssertEqual(intentCalls.accountClearCalls, [])
        XCTAssertEqual(persisted.map(\.id), [photoID])
        XCTAssertEqual(assetStore.deleteRequests, [assetID])
        XCTAssertEqual(trace.snapshot().last, .intentCleared)
    }

    func testCompensationClearsExactHintedIntentPromotedWhileReceiptIsPaused() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ProgressPhoto.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let assetID = "00000000-0000-0000-0000-000000000080"
        let photoID = UUID(uuidString: "00000000-0000-0000-0000-000000000081")!
        let timestamp = Date(timeIntervalSince1970: 683)
        context.insert(
            ProgressPhoto(
                id: photoID,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let durableIntentStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: directory.appendingPathComponent("cloud-deletions.json")
        )
        let initialResolution = await durableIntentStore.beginAccountResolution()
        let initialAuthorization = try await durableIntentStore
            .activateAccountIdentity(
                "opaque-account-a",
                resolution: initialResolution
            )
        await durableIntentStore.suspendAccountAuthorization(initialAuthorization)
        let pausingIntentStore = PausingAfterRecordCloudPhotoAssetDeletionIntentStore(
            backing: durableIntentStore
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: ProgressPhotoAssetStoreFake(
                deleteResults: [.failure(.protectedDataUnavailable)],
                localAssetIDs: [assetID]
            ),
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: pausingIntentStore,
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(
                fileURL: directory.appendingPathComponent("cloud-inbound.json")
            )
        )

        let deletion = Task { @MainActor in
            do {
                try await repository.deletePhoto(
                    id: photoID,
                    expectedUpdatedAt: timestamp
                )
                return nil as ProgressPhotoRepositoryOperationError?
            } catch {
                return error as? ProgressPhotoRepositoryOperationError
            }
        }
        let pausedReceipt = await pausingIntentStore.waitForPausedReceipt()
        XCTAssertEqual(pausedReceipt.assetID, assetID)
        XCTAssertEqual(pausedReceipt.quarantineIdentityHint, "opaque-account-a")
        let promotionResolution = await durableIntentStore.beginAccountResolution()
        let promotedAuthorization = try await durableIntentStore
            .activateAccountIdentity(
                "opaque-account-a",
                resolution: promotionResolution
            )
        let scopedWhilePaused = try await durableIntentStore
            .pendingDeletionAssetIDs(forAccountIdentity: "opaque-account-a")
        let quarantineWhilePaused = try await durableIntentStore
            .unresolvedDeletionAssetIDs()
        XCTAssertEqual(scopedWhilePaused, [assetID])
        XCTAssertTrue(quarantineWhilePaused.isEmpty)

        await pausingIntentStore.resumeRecord()
        let deletionError = await deletion.value
        await durableIntentStore.suspendAccountAuthorization(promotedAuthorization)
        let scopedAfterCompensation = try await durableIntentStore
            .pendingDeletionAssetIDs(forAccountIdentity: "opaque-account-a")
        let quarantineAfterCompensation = try await durableIntentStore
            .unresolvedDeletionAssetIDs()
        let persisted = try context.fetch(FetchDescriptor<ProgressPhoto>())

        XCTAssertEqual(
            deletionError,
            .protectedDataUnavailable,
            "The original local-delete error must return only after exact intent cleanup."
        )
        XCTAssertTrue(scopedAfterCompensation.isEmpty)
        XCTAssertTrue(quarantineAfterCompensation.isEmpty)
        XCTAssertEqual(persisted.map(\.id), [photoID])
    }

    func testRepositoryCloudReferenceSnapshotIsImmutableAcrossLaterMetadataChange() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-00000000006a"
        let model = ProgressPhoto(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000076")!,
            imageRef: assetID,
            pose: .front
        )
        context.insert(model)
        try context.save()
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: ProgressPhotoAssetStoreFake(localAssetIDs: [assetID]),
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString
                )
            ),
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString
                )
            )
        )

        let snapshot = try await repository.snapshot()
        context.delete(model)
        try context.save()

        XCTAssertEqual(snapshot.referencedAssetIDs, [assetID])
    }

    func testInboundCloudAssetSurvivesCoordinatorRestoreCrashAndRepositoryRelaunch() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000069"
        let bytes = Data([6, 9])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundURL = directory.appendingPathComponent("cloud-inbound.json")
        let inboundJournal = FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: directory.appendingPathComponent("transfers", isDirectory: true)
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: bytes)
        let record = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            stagedFileURL: stagedURL
        )
        let database = PersistenceCloudPhotoAssetDatabaseFake(
            changePage: .init(
                changes: [.changed(record)],
                changeToken: Data([6, 9]),
                moreComing: false
            )
        )
        let assetStore = ProgressPhotoAssetStoreFake(
            restoreErrorAfterWrite: FixtureError.restoreCrash,
            requiredInboundJournal: inboundJournal
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: assetStore,
            stateStore: FileCloudPhotoAssetSyncStateStore(
                fileURL: directory.appendingPathComponent("state.json")
            ),
            referenceSnapshotProvider: PersistenceCloudPhotoReferenceProvider(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: inboundJournal,
                localStore: assetStore
            ),
            temporaryStore: temporaryStore
        )

        do {
            _ = try await coordinator.synchronize()
            XCTFail("The fixture must simulate a crash immediately after local restore.")
        } catch {
            XCTAssertEqual(error as? FixtureError, .restoreCrash)
        }
        assetStore.restoreErrorAfterWrite = nil
        let pendingAfterCrash = try await FileCloudPhotoAssetInboundJournal(
            fileURL: inboundURL
        ).pendingInboundAssetIDs()
        XCTAssertEqual(pendingAfterCrash, [assetID])
        XCTAssertEqual(assetStore.localAssetIDs, [assetID])

        let beforeMetadataRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        )
        let beforeMetadata = try await beforeMetadataRepository.fetchPhotos()
        XCTAssertTrue(beforeMetadata.isEmpty)
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)

        let timestamp = Date(timeIntervalSince1970: 680)
        context.insert(
            ProgressPhoto(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000075")!,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let recreatedInboundJournal = FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        let afterMetadataRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetJournal: recreatedInboundJournal
        )

        let afterMetadata = try await afterMetadataRepository.fetchPhotos()
        let pendingAfterMetadata = try await recreatedInboundJournal.loadInboundAssetIDs()

        XCTAssertEqual(afterMetadata.map(\.imageRef), [assetID])
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)
        XCTAssertEqual(assetStore.localAssetIDs, [assetID])
        XCTAssertTrue(pendingAfterMetadata.isEmpty)
    }

    func testSuccessfulInboundSyncRetainsIntentUntilMetadataReferencesAsset() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-00000000006d"
        let bytes = Data([6, 13])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundURL = directory.appendingPathComponent("cloud-inbound.json")
        let inboundJournal = FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: directory.appendingPathComponent("transfers", isDirectory: true)
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: bytes)
        let record = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            stagedFileURL: stagedURL
        )
        let database = PersistenceCloudPhotoAssetDatabaseFake(
            changePage: .init(
                changes: [.changed(record)],
                changeToken: Data([6, 13]),
                moreComing: false
            )
        )
        let assetStore = ProgressPhotoAssetStoreFake(
            requiredInboundJournal: inboundJournal
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: assetStore,
            stateStore: FileCloudPhotoAssetSyncStateStore(
                fileURL: directory.appendingPathComponent("state.json")
            ),
            referenceSnapshotProvider: PersistenceCloudPhotoReferenceProvider(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: inboundJournal,
                localStore: assetStore
            ),
            temporaryStore: temporaryStore
        )

        let outcome = try await coordinator.synchronize()
        let pendingAfterSuccess = try await FileCloudPhotoAssetInboundJournal(
            fileURL: inboundURL
        ).pendingInboundAssetIDs()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(pendingAfterSuccess, [assetID])
        XCTAssertEqual(assetStore.localAssetIDs, [assetID])

        for _ in 0..<2 {
            let repository = SwiftDataProgressPhotoRepository(
                modelContext: context,
                assetStore: assetStore,
                cleanupJournal: PhotoAssetCleanupJournalFake(),
                deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                    fileURL: directory.appendingPathComponent("cloud-deletions.json")
                ),
                inboundAssetJournal: FileCloudPhotoAssetInboundJournal(
                    fileURL: inboundURL
                )
            )
            let beforeMetadata = try await repository.fetchPhotos()
            let stillPending = try await FileCloudPhotoAssetInboundJournal(
                fileURL: inboundURL
            ).pendingInboundAssetIDs()

            XCTAssertTrue(beforeMetadata.isEmpty)
            XCTAssertEqual(stillPending, [assetID])
            XCTAssertTrue(assetStore.deleteRequests.isEmpty)
            XCTAssertEqual(assetStore.localAssetIDs, [assetID])
        }

        let timestamp = Date(timeIntervalSince1970: 683)
        context.insert(
            ProgressPhoto(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000079")!,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .back,
                note: nil
            )
        )
        try context.save()
        let referencedRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        )

        let referenced = try await referencedRepository.fetchPhotos()
        let pendingAfterReference = try await FileCloudPhotoAssetInboundJournal(
            fileURL: inboundURL
        ).pendingInboundAssetIDs()

        XCTAssertEqual(referenced.map(\.imageRef), [assetID])
        XCTAssertTrue(pendingAfterReference.isEmpty)
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)
        XCTAssertEqual(assetStore.localAssetIDs, [assetID])
    }

    func testRepositoryConsumesOnlyInboundIDsMatchedByMetadataAcrossRelaunches() async throws {
        let context = try makeContext()
        let assetA = "00000000-0000-0000-0000-00000000006e"
        let assetB = "00000000-0000-0000-0000-00000000006f"
        let bytesA = Data([6, 14])
        let bytesB = Data([6, 15])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundURL = directory.appendingPathComponent("cloud-inbound.json")
        let inboundJournal = FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: directory.appendingPathComponent("transfers", isDirectory: true)
        )
        let stagedA = try temporaryStore.createUploadFile(bytes: bytesA)
        let stagedB = try temporaryStore.createUploadFile(bytes: bytesB)
        let recordA = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetA),
            assetID: assetA,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytesA),
            byteCount: 2,
            stagedFileURL: stagedA
        )
        let recordB = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetB),
            assetID: assetB,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytesB),
            byteCount: 2,
            stagedFileURL: stagedB
        )
        let database = PersistenceCloudPhotoAssetDatabaseFake(
            changePage: .init(
                changes: [.changed(recordA), .changed(recordB)],
                changeToken: Data([6, 14, 15]),
                moreComing: false
            )
        )
        let assetStore = ProgressPhotoAssetStoreFake(
            requiredInboundJournal: inboundJournal
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: assetStore,
            stateStore: FileCloudPhotoAssetSyncStateStore(
                fileURL: directory.appendingPathComponent("state.json")
            ),
            referenceSnapshotProvider: PersistenceCloudPhotoReferenceProvider(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: inboundJournal,
                localStore: assetStore
            ),
            temporaryStore: temporaryStore
        )

        let outcome = try await coordinator.synchronize()
        let pendingAfterSync = try await FileCloudPhotoAssetInboundJournal(
            fileURL: inboundURL
        ).pendingInboundAssetIDs()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(pendingAfterSync, [assetA, assetB])
        XCTAssertEqual(assetStore.localAssetIDs, [assetA, assetB])

        let emptyRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        )
        let emptySnapshots = try await emptyRepository.fetchPhotos()
        let pendingWithoutMetadata = try await FileCloudPhotoAssetInboundJournal(
            fileURL: inboundURL
        ).pendingInboundAssetIDs()

        XCTAssertTrue(emptySnapshots.isEmpty)
        XCTAssertEqual(pendingWithoutMetadata, [assetA, assetB])
        XCTAssertEqual(assetStore.localAssetIDs, [assetA, assetB])
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)

        let timestampA = Date(timeIntervalSince1970: 684)
        context.insert(
            ProgressPhoto(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000007a")!,
                createdAt: timestampA,
                updatedAt: timestampA,
                date: timestampA,
                imageRef: assetA,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let onlyARepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        )

        let onlyASnapshots = try await onlyARepository.fetchPhotos()
        let pendingAfterA = try await FileCloudPhotoAssetInboundJournal(
            fileURL: inboundURL
        ).pendingInboundAssetIDs()

        XCTAssertEqual(onlyASnapshots.map(\.imageRef), [assetA])
        XCTAssertEqual(pendingAfterA, [assetB])
        XCTAssertEqual(assetStore.localAssetIDs, [assetA, assetB])
        XCTAssertEqual(assetStore.cloudAssets[assetA], bytesA)
        XCTAssertEqual(assetStore.cloudAssets[assetB], bytesB)
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)

        let onlyARelaunchedRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        )
        _ = try await onlyARelaunchedRepository.fetchPhotos()
        let pendingAfterARelaunch = try await FileCloudPhotoAssetInboundJournal(
            fileURL: inboundURL
        ).pendingInboundAssetIDs()

        XCTAssertEqual(pendingAfterARelaunch, [assetB])
        XCTAssertEqual(assetStore.localAssetIDs, [assetA, assetB])
        XCTAssertEqual(assetStore.cloudAssets[assetB], bytesB)
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)

        let timestampB = Date(timeIntervalSince1970: 685)
        context.insert(
            ProgressPhoto(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000007b")!,
                createdAt: timestampB,
                updatedAt: timestampB,
                date: timestampB,
                imageRef: assetB,
                pose: .side,
                note: nil
            )
        )
        try context.save()
        let bothReferencedRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        )

        let bothSnapshots = try await bothReferencedRepository.fetchPhotos()
        let pendingAfterB = try await FileCloudPhotoAssetInboundJournal(
            fileURL: inboundURL
        ).pendingInboundAssetIDs()

        XCTAssertEqual(Set(bothSnapshots.map(\.imageRef)), [assetA, assetB])
        XCTAssertTrue(pendingAfterB.isEmpty)
        XCTAssertEqual(assetStore.localAssetIDs, [assetA, assetB])
        XCTAssertEqual(assetStore.cloudAssets[assetA], bytesA)
        XCTAssertEqual(assetStore.cloudAssets[assetB], bytesB)
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)
    }

    func testSnapshotReconcilesInboundOwnershipArrivingAfterInitialFetchPerID() async throws {
        let context = try makeContext()
        let assetA = "00000000-0000-0000-0000-000000000080"
        let assetB = "00000000-0000-0000-0000-000000000081"
        let bytesA = Data([8, 0])
        let bytesB = Data([8, 1])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: directory.appendingPathComponent("cloud-inbound.json")
        )
        let assetStore = ProgressPhotoAssetStoreFake()
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: FileCloudPhotoAssetDeletionIntentStore(
                fileURL: directory.appendingPathComponent("cloud-deletions.json")
            ),
            inboundAssetJournal: inboundJournal
        )

        let initialSnapshots = try await repository.fetchPhotos()
        XCTAssertTrue(initialSnapshots.isEmpty)
        try await inboundJournal.recordInboundAssetID(assetA)
        try await inboundJournal.recordInboundAssetID(assetB)
        try await assetStore.restoreCloudAsset(id: assetA, bytes: bytesA)
        try await assetStore.restoreCloudAsset(id: assetB, bytes: bytesB)
        let timestampA = Date(timeIntervalSince1970: 686)
        context.insert(
            ProgressPhoto(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
                createdAt: timestampA,
                updatedAt: timestampA,
                date: timestampA,
                imageRef: assetA,
                pose: .front,
                note: nil
            )
        )
        try context.save()

        let snapshotAfterA = try await repository.snapshot()
        let pendingAfterA = try await inboundJournal.pendingInboundAssetIDs()

        XCTAssertEqual(snapshotAfterA.referencedAssetIDs, [assetA])
        XCTAssertEqual(pendingAfterA, [assetB])
        XCTAssertEqual(assetStore.cloudAssets[assetA], bytesA)
        XCTAssertEqual(assetStore.cloudAssets[assetB], bytesB)
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)

        let timestampB = Date(timeIntervalSince1970: 687)
        context.insert(
            ProgressPhoto(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000083")!,
                createdAt: timestampB,
                updatedAt: timestampB,
                date: timestampB,
                imageRef: assetB,
                pose: .side,
                note: nil
            )
        )
        try context.save()

        let snapshotAfterB = try await repository.snapshot()
        let pendingAfterB = try await inboundJournal.pendingInboundAssetIDs()

        XCTAssertEqual(snapshotAfterB.referencedAssetIDs, [assetA, assetB])
        XCTAssertTrue(pendingAfterB.isEmpty)
        XCTAssertEqual(assetStore.cloudAssets[assetA], bytesA)
        XCTAssertEqual(assetStore.cloudAssets[assetB], bytesB)
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)
    }

    func testInboundApplyFinishesBeforeQueuedDeleteAndFinalStateRemainsDeleted() async throws {
        let context = try makeContext()
        let photoID = UUID(uuidString: "00000000-0000-0000-0000-000000000084")!
        let assetID = "00000000-0000-0000-0000-000000000085"
        let timestamp = Date(timeIntervalSince1970: 688)
        let bytes = Data([8, 5])
        context.insert(
            ProgressPhoto(
                id: photoID,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: directory.appendingPathComponent("cloud-inbound.json")
        )
        let deletionStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: directory.appendingPathComponent("cloud-deletions.json")
        )
        let resolution = await deletionStore.beginAccountResolution()
        _ = try await deletionStore.activateAccountIdentity(
            "opaque-account-a",
            resolution: resolution
        )
        let restoreGate = CloudInboundRestoreGate()
        let assetStore = ProgressPhotoAssetStoreFake(
            localAssetIDs: [assetID],
            cloudAssets: [assetID: bytes],
            requiredInboundJournal: inboundJournal,
            restoreGate: restoreGate
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: deletionStore,
            inboundAssetJournal: inboundJournal,
            inboundAssetStore: assetStore
        )

        let applyTask = Task { @MainActor in
            let preparation = try await repository.prepareInboundApply(
                id: assetID,
                forAccountIdentity: "opaque-account-a"
            )
            guard case let .prepared(lease) = preparation else {
                throw CloudPhotoAssetSyncError.invalidServerResponse
            }
            try await repository.commitInboundApply(lease, bytes: bytes)
        }
        await restoreGate.waitUntilRestoreStarted()
        let deleteStarted = expectation(description: "delete entered repository")
        let deleteFinished = CloudDeletionCompletionProbe()
        let deleteTask = Task { @MainActor in
            deleteStarted.fulfill()
            do {
                try await repository.deletePhoto(
                    id: photoID,
                    expectedUpdatedAt: timestamp
                )
                await deleteFinished.markFinished()
            } catch {
                await deleteFinished.markFinished()
                throw error
            }
        }
        await fulfillment(of: [deleteStarted], timeout: 2)
        let finishedWhileRestoreHeld = await deleteFinished.isFinished
        XCTAssertFalse(
            finishedWhileRestoreHeld,
            "The metadata deletion must wait for the repository-owned inbound apply."
        )

        await restoreGate.resumeRestore()
        try await applyTask.value
        try await deleteTask.value
        let persisted = try context.fetch(FetchDescriptor<ProgressPhoto>())
        let pendingInbound = try await inboundJournal.pendingInboundAssetIDs()
        let pendingDeletion = try await deletionStore.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )

        XCTAssertTrue(persisted.isEmpty)
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)
        XCTAssertTrue(assetStore.cloudAssets.isEmpty)
        XCTAssertTrue(pendingInbound.isEmpty)
        XCTAssertEqual(pendingDeletion, [assetID])
    }

    func testRepositoryInboundApplyWithoutCommittedDeletionPreservesAssetBeforeMetadata() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000088"
        let bytes = Data([8, 8])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: directory.appendingPathComponent("cloud-inbound.json")
        )
        let deletionStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: directory.appendingPathComponent("cloud-deletions.json")
        )
        let resolution = await deletionStore.beginAccountResolution()
        _ = try await deletionStore.activateAccountIdentity(
            "opaque-account-a",
            resolution: resolution
        )
        let assetStore = ProgressPhotoAssetStoreFake(
            requiredInboundJournal: inboundJournal
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: deletionStore,
            inboundAssetJournal: inboundJournal,
            inboundAssetStore: assetStore
        )

        let preparation = try await repository.prepareInboundApply(
            id: assetID,
            forAccountIdentity: "opaque-account-a"
        )
        guard case let .prepared(lease) = preparation else {
            return XCTFail("A deletion-free inbound asset must receive a lease.")
        }
        try await repository.commitInboundApply(lease, bytes: bytes)
        let snapshots = try await repository.fetchPhotos()
        let pendingInbound = try await inboundJournal.pendingInboundAssetIDs()
        let pendingDeletion = try await deletionStore.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )

        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertEqual(pendingInbound, [assetID])
        XCTAssertTrue(pendingDeletion.isEmpty)
        XCTAssertEqual(assetStore.localAssetIDs, [assetID])
        XCTAssertEqual(assetStore.cloudAssets[assetID], bytes)
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)
    }

    func testDeleteCommittedBeforeStaleChangedPageDiscardsInboundAndRetainsIntent() async throws {
        let context = try makeContext()
        let photoID = UUID(uuidString: "00000000-0000-0000-0000-000000000086")!
        let assetID = "00000000-0000-0000-0000-000000000087"
        let timestamp = Date(timeIntervalSince1970: 689)
        let bytes = Data([8, 7])
        context.insert(
            ProgressPhoto(
                id: photoID,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .back,
                note: nil
            )
        )
        try context.save()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundURL = directory.appendingPathComponent("cloud-inbound.json")
        let deletionURL = directory.appendingPathComponent("cloud-deletions.json")
        let stateURL = directory.appendingPathComponent("cloud-state.json")
        let transferDirectory = directory.appendingPathComponent(
            "transfers",
            isDirectory: true
        )
        let inboundJournal = FileCloudPhotoAssetInboundJournal(fileURL: inboundURL)
        let deletionStore = FileCloudPhotoAssetDeletionIntentStore(fileURL: deletionURL)
        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: transferDirectory
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: bytes)
        let record = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            stagedFileURL: stagedURL
        )
        let assetStore = ProgressPhotoAssetStoreFake(
            localAssetIDs: [assetID],
            cloudAssets: [assetID: bytes],
            requiredInboundJournal: inboundJournal
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: deletionStore,
            inboundAssetJournal: inboundJournal,
            inboundAssetStore: assetStore
        )
        let stateStore = FileCloudPhotoAssetSyncStateStore(fileURL: stateURL)
        try await stateStore.save(
            .init(accountIdentity: "opaque-account-a", uploadedAssetIDs: [assetID])
        )
        let database = PersistenceCloudPhotoAssetDatabaseFake(
            changePage: .init(
                changes: [.changed(record)],
                changeToken: Data([8, 7]),
                moreComing: false
            ),
            suspendedFetchCalls: [1]
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: assetStore,
            stateStore: stateStore,
            referenceSnapshotProvider: repository,
            deletionIntentStore: deletionStore,
            inboundAssetApplier: repository,
            temporaryStore: temporaryStore
        )

        let syncTask = Task { try await coordinator.synchronize() }
        await database.waitForFetchCall(1)
        try await repository.deletePhoto(
            id: photoID,
            expectedUpdatedAt: timestamp
        )
        await database.resumeFetchCall(1)
        let firstOutcome = try await syncTask.value
        let persistedAfterRace = try context.fetch(FetchDescriptor<ProgressPhoto>())
        let pendingInboundAfterRace = try await inboundJournal.pendingInboundAssetIDs()
        let pendingDeletionAfterRace = try await deletionStore.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )
        let firstDeleteRequests = await database.deleteRequests
        let transfersAfterRace = try FileManager.default.contentsOfDirectory(
            at: transferDirectory,
            includingPropertiesForKeys: nil
        )
        let stateAfterRace = try await stateStore.load()

        XCTAssertEqual(firstOutcome, .synchronized)
        XCTAssertTrue(persistedAfterRace.isEmpty)
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)
        XCTAssertTrue(assetStore.cloudAssets.isEmpty)
        XCTAssertTrue(pendingInboundAfterRace.isEmpty)
        XCTAssertEqual(pendingDeletionAfterRace, [assetID])
        XCTAssertTrue(firstDeleteRequests.isEmpty)
        XCTAssertTrue(transfersAfterRace.isEmpty)
        XCTAssertEqual(stateAfterRace.changeToken, Data([8, 7]))

        let relaunchedDeletionStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        )
        let relaunchedInboundJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: inboundURL
        )
        let relaunchedRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: relaunchedDeletionStore,
            inboundAssetJournal: relaunchedInboundJournal,
            inboundAssetStore: assetStore
        )
        let deferredCoordinator = CloudPhotoAssetCoordinator(
            database: PersistenceCloudPhotoAssetDatabaseFake(
                accountStatus: .temporarilyUnavailable
            ),
            localStore: assetStore,
            stateStore: FileCloudPhotoAssetSyncStateStore(fileURL: stateURL),
            referenceSnapshotProvider: relaunchedRepository,
            deletionIntentStore: relaunchedDeletionStore,
            inboundAssetApplier: relaunchedRepository,
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent(
                    "deferred-transfers",
                    isDirectory: true
                )
            )
        )

        let deferredOutcome = try await deferredCoordinator.synchronize()
        let pendingAfterDeferred = try await relaunchedDeletionStore
            .pendingDeletionAssetIDs(forAccountIdentity: "opaque-account-a")
        let snapshotsAfterRelaunch = try await relaunchedRepository.fetchPhotos()

        XCTAssertEqual(deferredOutcome, .deferred(.temporarilyUnavailable))
        XCTAssertEqual(pendingAfterDeferred, [assetID])
        XCTAssertTrue(snapshotsAfterRelaunch.isEmpty)
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)

        let retryDatabase = PersistenceCloudPhotoAssetDatabaseFake()
        let retryCoordinator = CloudPhotoAssetCoordinator(
            database: retryDatabase,
            localStore: assetStore,
            stateStore: FileCloudPhotoAssetSyncStateStore(fileURL: stateURL),
            referenceSnapshotProvider: relaunchedRepository,
            deletionIntentStore: relaunchedDeletionStore,
            inboundAssetApplier: relaunchedRepository,
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent(
                    "retry-transfers",
                    isDirectory: true
                )
            )
        )

        _ = try await retryCoordinator.synchronize()
        let retryDeletes = await retryDatabase.deleteRequests
        let pendingAfterRetry = try await relaunchedDeletionStore
            .pendingDeletionAssetIDs(forAccountIdentity: "opaque-account-a")

        XCTAssertEqual(retryDeletes, ["progress-photo-asset-\(assetID)"])
        XCTAssertTrue(pendingAfterRetry.isEmpty)
    }

    func testStaleChangedPageCannotRestoreDeletionQuarantinedByNewerAccountResolution() async throws {
        let context = try makeContext()
        let photoID = UUID(uuidString: "00000000-0000-0000-0000-000000000089")!
        let assetID = "00000000-0000-0000-0000-000000000090"
        let timestamp = Date(timeIntervalSince1970: 690)
        let bytes = Data([9, 0])
        context.insert(
            ProgressPhoto(
                id: photoID,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .front,
                note: nil
            )
        )
        try context.save()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let deletionURL = directory.appendingPathComponent("cloud-deletions.json")
        let inboundJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: directory.appendingPathComponent("cloud-inbound.json")
        )
        let durableDeletionStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        )
        let initialResolution = await durableDeletionStore.beginAccountResolution()
        let initialAuthorization = try await durableDeletionStore.activateAccountIdentity(
            "opaque-account-a",
            resolution: initialResolution
        )
        await durableDeletionStore.suspendAccountAuthorization(initialAuthorization)
        let pausingDeletionStore = PausingBeforeRecordCloudPhotoAssetDeletionIntentStore(
            backing: durableDeletionStore
        )
        let assetStore = ProgressPhotoAssetStoreFake(
            localAssetIDs: [assetID],
            cloudAssets: [assetID: bytes],
            requiredInboundJournal: inboundJournal
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: pausingDeletionStore,
            inboundAssetJournal: inboundJournal,
            inboundAssetStore: assetStore
        )
        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: directory.appendingPathComponent("transfers", isDirectory: true)
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: bytes)
        let record = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            stagedFileURL: stagedURL
        )
        let database = PersistenceCloudPhotoAssetDatabaseFake(
            changePage: .init(
                changes: [.changed(record)],
                changeToken: Data([9, 0]),
                moreComing: false
            ),
            accountStatuses: [.available, .temporarilyUnavailable],
            suspendedAccountStatusCalls: [2],
            suspendedFetchCalls: [1]
        )
        let stateStore = FileCloudPhotoAssetSyncStateStore(
            fileURL: directory.appendingPathComponent("cloud-state.json")
        )
        try await stateStore.save(
            .init(accountIdentity: "opaque-account-a", uploadedAssetIDs: [assetID])
        )
        let observedInboundApplier = ObservedCloudPhotoAssetInboundApplier(
            backing: repository
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: assetStore,
            stateStore: stateStore,
            referenceSnapshotProvider: repository,
            deletionIntentStore: pausingDeletionStore,
            inboundAssetApplier: observedInboundApplier,
            temporaryStore: temporaryStore
        )

        let staleSync = Task { try await coordinator.synchronize() }
        await database.waitForFetchCall(1)
        let deletion = Task { @MainActor in
            try await repository.deletePhoto(
                id: photoID,
                expectedUpdatedAt: timestamp
            )
        }
        let attemptedAssetID = await pausingDeletionStore.waitForRecordAttempt()
        XCTAssertEqual(attemptedAssetID, assetID)

        await database.resumeFetchCall(1)
        await observedInboundApplier.waitForPrepareCall(1)
        let newerSync = Task { try await coordinator.synchronize() }
        await database.waitForAccountStatusCall(2)

        await pausingDeletionStore.resumeRecord()
        try await deletion.value
        do {
            _ = try await staleSync.value
            XCTFail("The older changed page must become stale before inbound commit.")
        } catch is CancellationError {
            // Expected: C2 invalidated C1 while D still owned the repository lock.
        }
        await database.resumeAccountStatusCall(2)
        let newerOutcome = try await newerSync.value

        let recordedReceiptValue = await pausingDeletionStore.recordedReceipt()
        let recordedReceipt = try XCTUnwrap(recordedReceiptValue)
        let persisted = try context.fetch(FetchDescriptor<ProgressPhoto>())
        let pendingInbound = try await inboundJournal.pendingInboundAssetIDs()
        let unresolved = try await durableDeletionStore.unresolvedDeletionAssetIDs()
        let scoped = try await durableDeletionStore.pendingDeletionIntents(
            forAccountIdentity: "opaque-account-a"
        )
        let durableBytes = try Data(contentsOf: deletionURL)
        let durableText = try XCTUnwrap(String(data: durableBytes, encoding: .utf8))

        XCTAssertEqual(newerOutcome, .deferred(.temporarilyUnavailable))
        XCTAssertNil(recordedReceipt.accountIdentity)
        XCTAssertEqual(recordedReceipt.quarantineIdentityHint, "opaque-account-a")
        XCTAssertTrue(durableText.contains(recordedReceipt.intentID.uuidString))
        XCTAssertEqual(unresolved, [assetID])
        XCTAssertTrue(scoped.isEmpty)
        XCTAssertTrue(persisted.isEmpty)
        XCTAssertTrue(pendingInbound.isEmpty)
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)
        XCTAssertTrue(assetStore.cloudAssets.isEmpty)
    }

    func testStaleGenerationCancelsPreparedInboundLeaseBeforeAnySideEffectAndRepositoryReacquires() async throws {
        let context = try makeContext()
        let blockerID = "00000000-0000-0000-0000-000000000091"
        let inboundID = "00000000-0000-0000-0000-000000000092"
        let retryID = "00000000-0000-0000-0000-000000000093"
        let bytes = Data([9, 2])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let inboundJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: directory.appendingPathComponent("cloud-inbound.json")
        )
        let deletionStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: directory.appendingPathComponent("cloud-deletions.json")
        )
        let assetStore = ProgressPhotoAssetStoreFake(requiredInboundJournal: inboundJournal)
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            deletionIntentStore: deletionStore,
            inboundAssetJournal: inboundJournal,
            inboundAssetStore: assetStore
        )
        let heldPreparation = try await repository.prepareInboundApply(
            id: blockerID,
            forAccountIdentity: "opaque-account-a"
        )
        guard case let .prepared(heldLease) = heldPreparation else {
            return XCTFail("A repository without a deletion intent must issue a lease.")
        }

        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: directory.appendingPathComponent("transfers", isDirectory: true)
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: bytes)
        let record = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: inboundID),
            assetID: inboundID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            stagedFileURL: stagedURL
        )
        let database = PersistenceCloudPhotoAssetDatabaseFake(
            changePage: .init(
                changes: [.changed(record)],
                changeToken: Data([9, 2]),
                moreComing: false
            ),
            accountStatuses: [.available, .temporarilyUnavailable]
        )
        let observedInboundApplier = ObservedCloudPhotoAssetInboundApplier(
            backing: repository
        )
        let stateStore = FileCloudPhotoAssetSyncStateStore(
            fileURL: directory.appendingPathComponent("cloud-state.json")
        )
        try await stateStore.save(
            .init(accountIdentity: "opaque-account-a")
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: assetStore,
            stateStore: stateStore,
            referenceSnapshotProvider: PersistenceCloudPhotoReferenceProvider(),
            deletionIntentStore: deletionStore,
            inboundAssetApplier: observedInboundApplier,
            temporaryStore: temporaryStore
        )

        let staleSync = Task { try await coordinator.synchronize() }
        await observedInboundApplier.waitForPrepareCall(1)
        let newerOutcome = try await coordinator.synchronize()
        await repository.cancelInboundApply(heldLease)
        do {
            _ = try await staleSync.value
            XCTFail("A stale generation must cancel its prepared lease before commit.")
        } catch is CancellationError {
            // Expected after the held repository operation hands the lease to C1.
        }

        let calls = await observedInboundApplier.snapshot()
        let pendingInbound = try await inboundJournal.pendingInboundAssetIDs()
        let retryPreparation = try await repository.prepareInboundApply(
            id: retryID,
            forAccountIdentity: "opaque-account-a"
        )
        guard case let .prepared(retryLease) = retryPreparation else {
            return XCTFail("Exact stale cancellation must leave the repository reusable.")
        }
        await repository.cancelInboundApply(retryLease)

        XCTAssertEqual(newerOutcome, .deferred(.temporarilyUnavailable))
        XCTAssertEqual(calls.prepareAssetIDs, [inboundID])
        XCTAssertTrue(calls.commitLeaseAssetIDs.isEmpty)
        XCTAssertEqual(calls.cancelLeaseAssetIDs, [inboundID])
        XCTAssertTrue(pendingInbound.isEmpty)
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)
        XCTAssertTrue(assetStore.cloudAssets.isEmpty)
    }

    func testInboundPreparationLeaseRejectsABAAndReleasesAfterCancellation() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000094"
        let cancelledID = "00000000-0000-0000-0000-000000000095"
        let retryID = "00000000-0000-0000-0000-000000000096"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileJournal = FileCloudPhotoAssetInboundJournal(
            fileURL: directory.appendingPathComponent("cloud-inbound.json")
        )
        let inboundJournal = CancellingSecondRecordInboundJournal(backing: fileJournal)
        let assetStore = ProgressPhotoAssetStoreFake()
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            inboundAssetJournal: inboundJournal,
            inboundAssetStore: assetStore
        )

        let firstPreparation = try await repository.prepareInboundApply(
            id: assetID,
            forAccountIdentity: "opaque-account-a"
        )
        guard case let .prepared(firstLease) = firstPreparation else {
            return XCTFail("The first exact lease must be prepared.")
        }
        await repository.cancelInboundApply(firstLease)
        let secondPreparation = try await repository.prepareInboundApply(
            id: assetID,
            forAccountIdentity: "opaque-account-a"
        )
        guard case let .prepared(secondLease) = secondPreparation else {
            return XCTFail("The replacement exact lease must be prepared.")
        }
        await repository.cancelInboundApply(firstLease)
        try await repository.commitInboundApply(secondLease, bytes: Data([9, 4]))
        await repository.cancelInboundApply(secondLease)

        let cancellationPreparation = try await repository.prepareInboundApply(
            id: cancelledID,
            forAccountIdentity: "opaque-account-a"
        )
        guard case let .prepared(cancellationLease) = cancellationPreparation else {
            return XCTFail("The cancellation path must receive an exact lease.")
        }
        do {
            try await repository.commitInboundApply(
                cancellationLease,
                bytes: Data([9, 5])
            )
            XCTFail("The injected cancellation must escape commit.")
        } catch is CancellationError {
            // Expected: commit must release its exact repository operation on cancellation.
        }
        let retryPreparation = try await repository.prepareInboundApply(
            id: retryID,
            forAccountIdentity: "opaque-account-a"
        )
        guard case let .prepared(retryLease) = retryPreparation else {
            return XCTFail("A cancelled commit must release for a later lease.")
        }
        await repository.cancelInboundApply(retryLease)

        let pendingInbound = try await fileJournal.pendingInboundAssetIDs()
        XCTAssertEqual(assetStore.cloudAssets[assetID], Data([9, 4]))
        XCTAssertNil(assetStore.cloudAssets[cancelledID])
        XCTAssertEqual(pendingInbound, [assetID])
    }

    func testDuplicateImageReferenceFailsClosedBeforeEitherOwnerCanDelete() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000064"
        let timestamp = Date(timeIntervalSince1970: 640)
        let firstID = UUID()
        for id in [firstID, UUID()] {
            context.insert(
                ProgressPhoto(
                    id: id,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    date: timestamp,
                    imageRef: assetID,
                    pose: .front,
                    note: nil
                )
            )
        }
        try context.save()
        let assetStore = ProgressPhotoAssetStoreFake(localAssetIDs: [assetID])
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )

        do {
            try await repository.deletePhoto(
                id: firstID,
                expectedUpdatedAt: timestamp
            )
            XCTFail("Shared asset ownership must fail closed before deletion.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryIntegrityError,
                .duplicateImageRefs(assetID: assetID, count: 2)
            )
        }

        XCTAssertTrue(assetStore.deleteRequests.isEmpty)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ProgressPhoto>()).count,
            2
        )
    }

    func testReconciliationSerializesAConcurrentImportAcrossSuspension() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000065"
        let assetStore = InterleavingProgressPhotoAssetStore(assetID: assetID)
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )
        let input = try ProgressPhotoInput(
            date: Date(timeIntervalSince1970: 650),
            pose: .side,
            note: nil
        )

        let fetchTask = Task { try await repository.fetchPhotos() }
        await waitForInventoryCallCount(1, in: assetStore)

        let importStarted = expectation(description: "import task entered")
        let importTask = Task {
            importStarted.fulfill()
            return try await repository.importPhoto(input, bytes: Data([1]))
        }
        await fulfillment(of: [importStarted], timeout: 2)
        let suspendedCounts = await assetStore.callCounts()
        XCTAssertEqual(suspendedCounts.inventory, 1)
        XCTAssertEqual(suspendedCounts.imports, 0)

        await assetStore.resumeInventory(with: [])
        _ = try await fetchTask.value
        let imported = try await importTask.value

        XCTAssertEqual(imported.imageRef, assetID)
        let finalCounts = await assetStore.callCounts()
        XCTAssertEqual(finalCounts.imports, 1)
        XCTAssertTrue(finalCounts.deletes.isEmpty)
    }

    func testAssetDeleteFailureRestoresMetadataForExactRetry() async throws {
        let context = try makeContext()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000072")!
        let assetID = "00000000-0000-0000-0000-000000000040"
        let timestamp = Date(timeIntervalSince1970: 300)
        let model = ProgressPhoto(
            id: id,
            createdAt: timestamp,
            updatedAt: timestamp,
            date: timestamp,
            imageRef: assetID,
            pose: .front,
            note: nil
        )
        context.insert(model)
        try context.save()
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [
                .failure(.protectedDataUnavailable),
                .success(()),
            ]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )

        do {
            try await repository.deletePhoto(id: id, expectedUpdatedAt: timestamp)
            XCTFail("File cleanup failure must compensate the metadata deletion.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryOperationError,
                .protectedDataUnavailable
            )
        }
        let restored = try await repository.fetchPhotos()
        XCTAssertEqual(restored.map(\.id), [id])

        try await repository.deletePhoto(id: id, expectedUpdatedAt: timestamp)
        try await repository.deletePhoto(id: id, expectedUpdatedAt: timestamp)
        let deleted = try await repository.fetchPhotos()
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertEqual(assetStore.deleteRequests, [assetID, assetID])
    }

    func testThumbnailPassesThroughAvailableMissingAndCorruptFallbacks() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000041"
        let assetStore = ProgressPhotoAssetStoreFake(
            loadResults: [
                .success(.available(Data([1]))),
                .success(.missing),
                .success(.corrupt),
            ]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )

        let available = try await repository.thumbnail(assetID: assetID)
        let missing = try await repository.thumbnail(assetID: assetID)
        let corrupt = try await repository.thumbnail(assetID: assetID)
        XCTAssertEqual(available, .available(Data([1])))
        XCTAssertEqual(missing, .missing)
        XCTAssertEqual(corrupt, .corrupt)
        XCTAssertEqual(
            assetStore.loadRequests,
            [
                .init(id: assetID, variant: .thumbnail),
                .init(id: assetID, variant: .thumbnail),
                .init(id: assetID, variant: .thumbnail),
            ]
        )
    }

    func testAbsoluteOrMalformedPersistedImageRefFailsClosed() async throws {
        let context = try makeContext()
        context.insert(
            ProgressPhoto(
                id: UUID(),
                imageRef: "/private/var/mobile/photo.jpg",
                pose: .front
            )
        )
        try context.save()
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: ProgressPhotoAssetStoreFake(),
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )

        do {
            _ = try await repository.fetchPhotos()
            XCTFail("Absolute paths must never cross the repository boundary.")
        } catch {
            guard let integrityError = error as? ProgressPhotoRepositoryIntegrityError,
                  case .invalidImageRef = integrityError else {
                return XCTFail("Expected an invalid opaque image reference, got \(error)")
            }
        }
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ProgressPhoto.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    private func waitForInventoryCallCount(
        _ expectedCount: Int,
        in store: InterleavingProgressPhotoAssetStore
    ) async {
        for _ in 0..<1_000 {
            if await store.callCounts().inventory >= expectedCount {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for the suspended inventory request.")
    }
}

private enum FixtureError: Error, Equatable, Sendable {
    case save
    case restoreCrash
    case restoreBeforeInboundIntent
    case inboundRead
}

private enum CloudDeletionOperation: Equatable {
    case persistedPhotoIDs([UUID])
    case intentRecorded
    case localDeleteAttempted
    case intentClearStarted
    case intentCleared
}

private final class CloudDeletionOperationTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [CloudDeletionOperation] = []

    func append(_ operation: CloudDeletionOperation) {
        lock.lock()
        operations.append(operation)
        lock.unlock()
    }

    func snapshot() -> [CloudDeletionOperation] {
        lock.lock()
        defer { lock.unlock() }
        return operations
    }
}

private actor CloudDeletionCompletionProbe {
    private(set) var isFinished = false

    func markFinished() {
        isFinished = true
    }
}

private actor CloudInboundRestoreGate {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var restoreContinuation: CheckedContinuation<Void, Never>?

    func suspendRestore() async {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            restoreContinuation = continuation
        }
    }

    func waitUntilRestoreStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeRestore() {
        let continuation = restoreContinuation
        restoreContinuation = nil
        continuation?.resume()
    }
}

private actor ObservedCloudPhotoAssetInboundApplier:
    CloudPhotoAssetInboundApplying {
    struct Snapshot: Sendable {
        let prepareAssetIDs: [String]
        let commitLeaseAssetIDs: [String]
        let cancelLeaseAssetIDs: [String]
    }

    private let backing: any CloudPhotoAssetInboundApplying
    private var prepareAssetIDs: [String] = []
    private var commitLeaseAssetIDs: [String] = []
    private var cancelLeaseAssetIDs: [String] = []
    private var prepareWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(backing: any CloudPhotoAssetInboundApplying) {
        self.backing = backing
    }

    func prepareInboundApply(
        id assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws -> CloudPhotoAssetInboundApplyPreparation {
        prepareAssetIDs.append(assetID)
        let ready = prepareWaiters.filter { prepareAssetIDs.count >= $0.0 }
        prepareWaiters.removeAll { prepareAssetIDs.count >= $0.0 }
        for (_, waiter) in ready { waiter.resume() }
        return try await backing.prepareInboundApply(
            id: assetID,
            forAccountIdentity: accountIdentity
        )
    }

    func commitInboundApply(
        _ lease: CloudPhotoAssetInboundApplyLease,
        bytes: Data
    ) async throws {
        commitLeaseAssetIDs.append(lease.assetID)
        try await backing.commitInboundApply(lease, bytes: bytes)
    }

    func cancelInboundApply(_ lease: CloudPhotoAssetInboundApplyLease) async {
        cancelLeaseAssetIDs.append(lease.assetID)
        await backing.cancelInboundApply(lease)
    }

    func waitForPrepareCall(_ expectedCount: Int) async {
        guard prepareAssetIDs.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            prepareWaiters.append((expectedCount, continuation))
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            prepareAssetIDs: prepareAssetIDs,
            commitLeaseAssetIDs: commitLeaseAssetIDs,
            cancelLeaseAssetIDs: cancelLeaseAssetIDs
        )
    }
}

private actor CancellingSecondRecordInboundJournal:
    CloudPhotoAssetInboundJournaling {
    private let backing: FileCloudPhotoAssetInboundJournal
    private var recordCallCount = 0

    init(backing: FileCloudPhotoAssetInboundJournal) {
        self.backing = backing
    }

    func pendingInboundAssetIDs() async throws -> Set<String> {
        try await backing.pendingInboundAssetIDs()
    }

    func acquireCleanupLease(
        for assetID: String
    ) async throws -> CloudPhotoAssetInboundCleanupLease? {
        try await backing.acquireCleanupLease(for: assetID)
    }

    func releaseCleanupLease(_ lease: CloudPhotoAssetInboundCleanupLease) async {
        await backing.releaseCleanupLease(lease)
    }

    func recordInboundAssetID(_ assetID: String) async throws {
        recordCallCount += 1
        if recordCallCount == 2 { throw CancellationError() }
        try await backing.recordInboundAssetID(assetID)
    }

    func clearInboundAssetID(_ assetID: String) async throws {
        try await backing.clearInboundAssetID(assetID)
    }
}

private actor RecordingCloudPhotoAssetDeletionIntentStore:
    CloudPhotoAssetDeletionIntentStoring {
    struct Calls: Equatable, Sendable {
        let recordCalls: [String]
        let clearCalls: [String]
        let accountClearCalls: [String]
    }

    private let backing: FileCloudPhotoAssetDeletionIntentStore
    private var recordCalls: [String] = []
    private var clearCalls: [String] = []
    private var accountClearCalls: [String] = []

    init(backing: FileCloudPhotoAssetDeletionIntentStore) {
        self.backing = backing
    }

    func beginAccountResolution() async -> CloudPhotoAssetAccountResolution {
        await backing.beginAccountResolution()
    }

    func activateAccountIdentity(
        _ accountIdentity: String,
        resolution: CloudPhotoAssetAccountResolution
    ) async throws -> CloudPhotoAssetAccountAuthorization {
        try await backing.activateAccountIdentity(
            accountIdentity,
            resolution: resolution
        )
    }

    func suspendAccountAuthorization(
        _ authorization: CloudPhotoAssetAccountAuthorization
    ) async {
        await backing.suspendAccountAuthorization(authorization)
    }

    func pendingDeletionIntents(
        forAccountIdentity accountIdentity: String
    ) async throws -> [CloudPhotoAssetDeletionIntentReceipt] {
        try await backing.pendingDeletionIntents(
            forAccountIdentity: accountIdentity
        )
    }

    func pendingDeletionAssetIDs(
        forAccountIdentity accountIdentity: String
    ) async throws -> Set<String> {
        try await backing.pendingDeletionAssetIDs(
            forAccountIdentity: accountIdentity
        )
    }

    func unresolvedDeletionAssetIDs() async throws -> Set<String> {
        try await backing.unresolvedDeletionAssetIDs()
    }

    func hasCommittedLocalDeletionIntent(assetID: String) async throws -> Bool {
        try await backing.hasCommittedLocalDeletionIntent(assetID: assetID)
    }

    func recordCommittedDeletion(
        assetID: String
    ) async throws -> CloudPhotoAssetDeletionIntentReceipt {
        recordCalls.append(assetID)
        return try await backing.recordCommittedDeletion(assetID: assetID)
    }

    func clearCommittedDeletion(
        _ intent: CloudPhotoAssetDeletionIntentReceipt
    ) async throws {
        clearCalls.append(intent.assetID)
        try await backing.clearCommittedDeletion(intent)
    }

    func clearCommittedDeletion(
        assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws {
        accountClearCalls.append(assetID)
        try await backing.clearCommittedDeletion(
            assetID: assetID,
            forAccountIdentity: accountIdentity
        )
    }

    func calls() -> Calls {
        Calls(
            recordCalls: recordCalls,
            clearCalls: clearCalls,
            accountClearCalls: accountClearCalls
        )
    }
}

private actor BlockingCloudPhotoAssetDeletionIntentStore:
    CloudPhotoAssetDeletionIntentStoring {
    private let backing: RecordingCloudPhotoAssetDeletionIntentStore
    private let trace: CloudDeletionOperationTrace
    private var clearWasAttempted = false
    private var clearContinuation: CheckedContinuation<Void, Never>?

    init(
        backing: RecordingCloudPhotoAssetDeletionIntentStore,
        trace: CloudDeletionOperationTrace
    ) {
        self.backing = backing
        self.trace = trace
    }

    func beginAccountResolution() async -> CloudPhotoAssetAccountResolution {
        await backing.beginAccountResolution()
    }

    func activateAccountIdentity(
        _ accountIdentity: String,
        resolution: CloudPhotoAssetAccountResolution
    ) async throws -> CloudPhotoAssetAccountAuthorization {
        try await backing.activateAccountIdentity(
            accountIdentity,
            resolution: resolution
        )
    }

    func suspendAccountAuthorization(
        _ authorization: CloudPhotoAssetAccountAuthorization
    ) async {
        await backing.suspendAccountAuthorization(authorization)
    }

    func pendingDeletionIntents(
        forAccountIdentity accountIdentity: String
    ) async throws -> [CloudPhotoAssetDeletionIntentReceipt] {
        try await backing.pendingDeletionIntents(
            forAccountIdentity: accountIdentity
        )
    }

    func pendingDeletionAssetIDs(
        forAccountIdentity accountIdentity: String
    ) async throws -> Set<String> {
        try await backing.pendingDeletionAssetIDs(
            forAccountIdentity: accountIdentity
        )
    }

    func unresolvedDeletionAssetIDs() async throws -> Set<String> {
        try await backing.unresolvedDeletionAssetIDs()
    }

    func hasCommittedLocalDeletionIntent(assetID: String) async throws -> Bool {
        try await backing.hasCommittedLocalDeletionIntent(assetID: assetID)
    }

    func recordCommittedDeletion(
        assetID: String
    ) async throws -> CloudPhotoAssetDeletionIntentReceipt {
        let intent = try await backing.recordCommittedDeletion(assetID: assetID)
        trace.append(.intentRecorded)
        return intent
    }

    func clearCommittedDeletion(
        _ intent: CloudPhotoAssetDeletionIntentReceipt
    ) async throws {
        trace.append(.intentClearStarted)
        clearWasAttempted = true
        await withCheckedContinuation { continuation in
            clearContinuation = continuation
        }
        try await backing.clearCommittedDeletion(intent)
        trace.append(.intentCleared)
    }

    func clearCommittedDeletion(
        assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws {
        try await backing.clearCommittedDeletion(
            assetID: assetID,
            forAccountIdentity: accountIdentity
        )
    }

    func waitUntilClearAttempted() async -> Bool {
        for _ in 0..<10_000 {
            if clearWasAttempted { return true }
            await Task.yield()
        }
        return false
    }

    func resumeClear() {
        let continuation = clearContinuation
        clearContinuation = nil
        continuation?.resume()
    }
}

private actor PausingBeforeRecordCloudPhotoAssetDeletionIntentStore:
    CloudPhotoAssetDeletionIntentStoring {
    private let backing: FileCloudPhotoAssetDeletionIntentStore
    private var attemptedAssetID: String?
    private var attemptWaiters: [CheckedContinuation<String, Never>] = []
    private var recordContinuation: CheckedContinuation<Void, Never>?
    private var storedReceipt: CloudPhotoAssetDeletionIntentReceipt?

    init(backing: FileCloudPhotoAssetDeletionIntentStore) {
        self.backing = backing
    }

    func beginAccountResolution() async -> CloudPhotoAssetAccountResolution {
        await backing.beginAccountResolution()
    }

    func activateAccountIdentity(
        _ accountIdentity: String,
        resolution: CloudPhotoAssetAccountResolution
    ) async throws -> CloudPhotoAssetAccountAuthorization {
        try await backing.activateAccountIdentity(
            accountIdentity,
            resolution: resolution
        )
    }

    func suspendAccountAuthorization(
        _ authorization: CloudPhotoAssetAccountAuthorization
    ) async {
        await backing.suspendAccountAuthorization(authorization)
    }

    func pendingDeletionIntents(
        forAccountIdentity accountIdentity: String
    ) async throws -> [CloudPhotoAssetDeletionIntentReceipt] {
        try await backing.pendingDeletionIntents(
            forAccountIdentity: accountIdentity
        )
    }

    func pendingDeletionAssetIDs(
        forAccountIdentity accountIdentity: String
    ) async throws -> Set<String> {
        try await backing.pendingDeletionAssetIDs(
            forAccountIdentity: accountIdentity
        )
    }

    func unresolvedDeletionAssetIDs() async throws -> Set<String> {
        try await backing.unresolvedDeletionAssetIDs()
    }

    func hasCommittedLocalDeletionIntent(assetID: String) async throws -> Bool {
        try await backing.hasCommittedLocalDeletionIntent(assetID: assetID)
    }

    func recordCommittedDeletion(
        assetID: String
    ) async throws -> CloudPhotoAssetDeletionIntentReceipt {
        attemptedAssetID = assetID
        let observers = attemptWaiters
        attemptWaiters.removeAll()
        for observer in observers { observer.resume(returning: assetID) }
        await withCheckedContinuation { continuation in
            recordContinuation = continuation
        }
        let receipt = try await backing.recordCommittedDeletion(assetID: assetID)
        storedReceipt = receipt
        return receipt
    }

    func clearCommittedDeletion(
        _ intent: CloudPhotoAssetDeletionIntentReceipt
    ) async throws {
        try await backing.clearCommittedDeletion(intent)
    }

    func clearCommittedDeletion(
        assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws {
        try await backing.clearCommittedDeletion(
            assetID: assetID,
            forAccountIdentity: accountIdentity
        )
    }

    func waitForRecordAttempt() async -> String {
        if let attemptedAssetID { return attemptedAssetID }
        return await withCheckedContinuation { continuation in
            attemptWaiters.append(continuation)
        }
    }

    func resumeRecord() {
        let continuation = recordContinuation
        recordContinuation = nil
        continuation?.resume()
    }

    func recordedReceipt() -> CloudPhotoAssetDeletionIntentReceipt? {
        storedReceipt
    }
}

private actor PausingAfterRecordCloudPhotoAssetDeletionIntentStore:
    CloudPhotoAssetDeletionIntentStoring {
    private let backing: FileCloudPhotoAssetDeletionIntentStore
    private var pausedReceipt: CloudPhotoAssetDeletionIntentReceipt?
    private var receiptObservers: [
        CheckedContinuation<CloudPhotoAssetDeletionIntentReceipt, Never>
    ] = []
    private var recordContinuation: CheckedContinuation<Void, Never>?

    init(backing: FileCloudPhotoAssetDeletionIntentStore) {
        self.backing = backing
    }

    func beginAccountResolution() async -> CloudPhotoAssetAccountResolution {
        await backing.beginAccountResolution()
    }

    func activateAccountIdentity(
        _ accountIdentity: String,
        resolution: CloudPhotoAssetAccountResolution
    ) async throws -> CloudPhotoAssetAccountAuthorization {
        try await backing.activateAccountIdentity(
            accountIdentity,
            resolution: resolution
        )
    }

    func suspendAccountAuthorization(
        _ authorization: CloudPhotoAssetAccountAuthorization
    ) async {
        await backing.suspendAccountAuthorization(authorization)
    }

    func pendingDeletionIntents(
        forAccountIdentity accountIdentity: String
    ) async throws -> [CloudPhotoAssetDeletionIntentReceipt] {
        try await backing.pendingDeletionIntents(
            forAccountIdentity: accountIdentity
        )
    }

    func pendingDeletionAssetIDs(
        forAccountIdentity accountIdentity: String
    ) async throws -> Set<String> {
        try await backing.pendingDeletionAssetIDs(
            forAccountIdentity: accountIdentity
        )
    }

    func unresolvedDeletionAssetIDs() async throws -> Set<String> {
        try await backing.unresolvedDeletionAssetIDs()
    }

    func hasCommittedLocalDeletionIntent(assetID: String) async throws -> Bool {
        try await backing.hasCommittedLocalDeletionIntent(assetID: assetID)
    }

    func recordCommittedDeletion(
        assetID: String
    ) async throws -> CloudPhotoAssetDeletionIntentReceipt {
        let receipt = try await backing.recordCommittedDeletion(assetID: assetID)
        pausedReceipt = receipt
        let observers = receiptObservers
        receiptObservers.removeAll()
        for observer in observers { observer.resume(returning: receipt) }
        await withCheckedContinuation { continuation in
            recordContinuation = continuation
        }
        return receipt
    }

    func clearCommittedDeletion(
        _ intent: CloudPhotoAssetDeletionIntentReceipt
    ) async throws {
        try await backing.clearCommittedDeletion(intent)
    }

    func clearCommittedDeletion(
        assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws {
        try await backing.clearCommittedDeletion(
            assetID: assetID,
            forAccountIdentity: accountIdentity
        )
    }

    func waitForPausedReceipt() async -> CloudPhotoAssetDeletionIntentReceipt {
        if let pausedReceipt { return pausedReceipt }
        return await withCheckedContinuation { continuation in
            receiptObservers.append(continuation)
        }
    }

    func resumeRecord() {
        let continuation = recordContinuation
        recordContinuation = nil
        continuation?.resume()
    }
}

private final class ProgressPhotoAssetStoreFake:
    PhotoAssetStoring,
    CloudPhotoAssetLocalStoring,
    @unchecked Sendable {
    struct LoadRequest: Equatable {
        let id: String
        let variant: PhotoAssetVariant
    }

    var importResults: [Result<PhotoAssetReference, PhotoAssetStoreError>]
    var loadResults: [Result<PhotoAssetLoadResult, PhotoAssetStoreError>]
    var deleteResults: [Result<Void, PhotoAssetStoreError>]
    var localAssetIDs: Set<String>
    var cloudAssets: [String: Data]
    var restoreErrorAfterWrite: Error?
    let requiredInboundJournal: FileCloudPhotoAssetInboundJournal?
    let restoreGate: CloudInboundRestoreGate?
    let deleteObserver: @Sendable (String) -> Void
    private(set) var importRequests: [Data] = []
    private(set) var loadRequests: [LoadRequest] = []
    private(set) var deleteRequests: [String] = []

    init(
        importResults: [Result<PhotoAssetReference, PhotoAssetStoreError>] = [],
        loadResults: [Result<PhotoAssetLoadResult, PhotoAssetStoreError>] = [],
        deleteResults: [Result<Void, PhotoAssetStoreError>] = [],
        localAssetIDs: Set<String> = [],
        cloudAssets: [String: Data] = [:],
        restoreErrorAfterWrite: Error? = nil,
        requiredInboundJournal: FileCloudPhotoAssetInboundJournal? = nil,
        restoreGate: CloudInboundRestoreGate? = nil,
        deleteObserver: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.importResults = importResults
        self.loadResults = loadResults
        self.deleteResults = deleteResults
        self.localAssetIDs = localAssetIDs
        self.cloudAssets = cloudAssets
        self.restoreErrorAfterWrite = restoreErrorAfterWrite
        self.requiredInboundJournal = requiredInboundJournal
        self.restoreGate = restoreGate
        self.deleteObserver = deleteObserver
    }

    func importAsset(_ bytes: Data) async throws -> PhotoAssetReference {
        importRequests.append(bytes)
        guard !importResults.isEmpty else { throw PhotoAssetStoreError.corruptInput }
        let reference = try importResults.removeFirst().get()
        localAssetIDs.insert(reference.assetID)
        cloudAssets[reference.assetID] = bytes
        return reference
    }

    func loadAsset(
        id: String,
        variant: PhotoAssetVariant
    ) async throws -> PhotoAssetLoadResult {
        loadRequests.append(.init(id: id, variant: variant))
        guard !loadResults.isEmpty else { return .missing }
        return try loadResults.removeFirst().get()
    }

    func deleteAsset(id: String) async throws {
        deleteRequests.append(id)
        deleteObserver(id)
        if !deleteResults.isEmpty {
            try deleteResults.removeFirst().get()
        }
        localAssetIDs.remove(id)
        cloudAssets.removeValue(forKey: id)
    }

    func storedAssetIDs() async throws -> Set<String> { localAssetIDs }

    func usableCloudAssetIDs() async throws -> Set<String> {
        Set(cloudAssets.keys)
    }

    func cloudAssetBytes(id: String) async throws -> Data? {
        cloudAssets[id]
    }

    func restoreCloudAsset(id: String, bytes: Data) async throws {
        if let requiredInboundJournal {
            let pending = try await requiredInboundJournal.pendingInboundAssetIDs()
            guard pending.contains(id) else {
                throw FixtureError.restoreBeforeInboundIntent
            }
        }
        await restoreGate?.suspendRestore()
        localAssetIDs.insert(id)
        cloudAssets[id] = bytes
        if let restoreErrorAfterWrite { throw restoreErrorAfterWrite }
    }

    func deleteCloudAsset(id: String) async throws {
        try await deleteAsset(id: id)
    }
}

private actor PersistenceCloudPhotoReferenceProvider:
    CloudPhotoAssetReferenceSnapshotProviding {
    private let referencedAssetIDs: Set<String>

    init(referencedAssetIDs: Set<String> = []) {
        self.referencedAssetIDs = referencedAssetIDs
    }

    func snapshot() async throws -> CloudPhotoAssetReferenceSnapshot {
        CloudPhotoAssetReferenceSnapshot(
            referencedAssetIDs: referencedAssetIDs
        )
    }
}

private actor PersistenceCloudPhotoAssetDatabaseFake:
    PrivateCloudPhotoAssetDatabase {
    private var deleteResults: [Result<Void, CloudPhotoAssetDatabaseError>]
    private let changePage: CloudPhotoAssetChangePage?
    private var accountStatuses: [CloudPhotoAccountStatus]
    private let suspendedAccountStatusCalls: Set<Int>
    private var accountStatusCallCount = 0
    private var accountStatusContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var accountStatusCallWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]
    private let suspendedFetchCalls: Set<Int>
    private var fetchCallCount = 0
    private var fetchContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var fetchCallWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var deleteRequests: [String] = []

    init(
        deleteResults: [Result<Void, CloudPhotoAssetDatabaseError>] = [],
        changePage: CloudPhotoAssetChangePage? = nil,
        accountStatus: CloudPhotoAccountStatus = .available,
        accountStatuses: [CloudPhotoAccountStatus]? = nil,
        suspendedAccountStatusCalls: Set<Int> = [],
        suspendedFetchCalls: Set<Int> = []
    ) {
        self.deleteResults = deleteResults
        self.changePage = changePage
        self.accountStatuses = accountStatuses ?? [accountStatus]
        self.suspendedAccountStatusCalls = suspendedAccountStatusCalls
        self.suspendedFetchCalls = suspendedFetchCalls
    }

    func accountStatus() async throws -> CloudPhotoAccountStatus {
        accountStatusCallCount += 1
        let call = accountStatusCallCount
        let waiters = accountStatusCallWaiters.removeValue(forKey: call) ?? []
        for waiter in waiters { waiter.resume() }
        let status = accountStatuses.count > 1
            ? accountStatuses.removeFirst()
            : (accountStatuses.first ?? .temporarilyUnavailable)
        if suspendedAccountStatusCalls.contains(call) {
            await withCheckedContinuation { continuation in
                accountStatusContinuations[call] = continuation
            }
        }
        return status
    }
    func accountIdentity() async throws -> String { "opaque-account-a" }
    func ensureZone(named zoneName: String) async throws { _ = zoneName }

    func record(
        named recordName: String,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata? {
        _ = recordName
        _ = zoneName
        return nil
    }

    func save(
        _ request: CloudPhotoAssetUploadRequest,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata {
        _ = zoneName
        return try CloudPhotoAssetRecordMetadata(
            recordName: request.recordName,
            assetID: request.assetID,
            checksum: request.checksum,
            byteCount: request.byteCount
        )
    }

    func deleteRecord(
        named recordName: String,
        inZone zoneName: String
    ) async throws {
        _ = zoneName
        deleteRequests.append(recordName)
        if !deleteResults.isEmpty {
            try deleteResults.removeFirst().get()
        }
    }

    func fetchChanges(
        inZone zoneName: String,
        previousToken: Data?
    ) async throws -> CloudPhotoAssetChangePage {
        _ = zoneName
        fetchCallCount += 1
        let call = fetchCallCount
        let waiters = fetchCallWaiters.removeValue(forKey: call) ?? []
        for waiter in waiters { waiter.resume() }
        if suspendedFetchCalls.contains(call) {
            await withCheckedContinuation { continuation in
                fetchContinuations[call] = continuation
            }
        }
        return changePage ?? .init(
            changes: [],
            changeToken: previousToken ?? Data([0]),
            moreComing: false
        )
    }

    func waitForFetchCall(_ call: Int) async {
        if fetchCallCount >= call { return }
        await withCheckedContinuation { continuation in
            fetchCallWaiters[call, default: []].append(continuation)
        }
    }

    func resumeFetchCall(_ call: Int) {
        let continuation = fetchContinuations.removeValue(forKey: call)
        continuation?.resume()
    }

    func waitForAccountStatusCall(_ call: Int) async {
        if accountStatusCallCount >= call { return }
        await withCheckedContinuation { continuation in
            accountStatusCallWaiters[call, default: []].append(continuation)
        }
    }

    func resumeAccountStatusCall(_ call: Int) {
        let continuation = accountStatusContinuations.removeValue(forKey: call)
        continuation?.resume()
    }
}

private actor InterleavingProgressPhotoAssetStore: PhotoAssetStoring {
    private let assetID: String
    private var inventoryContinuations: [
        CheckedContinuation<Set<String>, Never>
    ] = []
    private var inventoryCalls = 0
    private var importCalls = 0
    private var deleteCalls: [String] = []

    init(assetID: String) {
        self.assetID = assetID
    }

    func importAsset(_ bytes: Data) async throws -> PhotoAssetReference {
        _ = bytes
        importCalls += 1
        return PhotoAssetReference(assetID: assetID)
    }

    func loadAsset(
        id: String,
        variant: PhotoAssetVariant
    ) async throws -> PhotoAssetLoadResult {
        _ = id
        _ = variant
        return .missing
    }

    func deleteAsset(id: String) async throws {
        deleteCalls.append(id)
    }

    func storedAssetIDs() async throws -> Set<String> {
        inventoryCalls += 1
        return await withCheckedContinuation { continuation in
            inventoryContinuations.append(continuation)
        }
    }

    func callCounts() -> (inventory: Int, imports: Int, deletes: [String]) {
        (inventoryCalls, importCalls, deleteCalls)
    }

    func resumeInventory(with ids: Set<String>) {
        let continuations = inventoryContinuations
        inventoryContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: ids)
        }
    }
}

private actor CleanupLeaseInterleavingAssetStore: PhotoAssetStoring {
    struct Snapshot: Sendable {
        let assets: [String: Data]
        let deleteRequests: [String]
    }

    private var assets: [String: Data]
    private var initialDeleteFailures: [String: Int]
    private var deleteRequests: [String] = []
    private var suspendedAssetID: String?
    private var suspendedDeleteAssetIDs = Set<String>()
    private var deleteContinuations: [String: CheckedContinuation<Void, Never>] = [:]

    init(
        assets: [String: Data],
        initialDeleteFailures: [String: Int]
    ) {
        self.assets = assets
        self.initialDeleteFailures = initialDeleteFailures
    }

    func importAsset(_ bytes: Data) async throws -> PhotoAssetReference {
        _ = bytes
        throw PhotoAssetStoreError.corruptInput
    }

    func loadAsset(
        id: String,
        variant: PhotoAssetVariant
    ) async throws -> PhotoAssetLoadResult {
        _ = id
        _ = variant
        return .missing
    }

    func deleteAsset(id: String) async throws {
        deleteRequests.append(id)
        if let remaining = initialDeleteFailures[id], remaining > 0 {
            initialDeleteFailures[id] = remaining - 1
            throw PhotoAssetStoreError.protectedDataUnavailable
        }
        if suspendedAssetID == id {
            suspendedAssetID = nil
            suspendedDeleteAssetIDs.insert(id)
            await withCheckedContinuation { continuation in
                deleteContinuations[id] = continuation
            }
            suspendedDeleteAssetIDs.remove(id)
        }
        assets.removeValue(forKey: id)
    }

    func storedAssetIDs() async throws -> Set<String> {
        Set(assets.keys)
    }

    func suspendNextDelete(of assetID: String) {
        suspendedAssetID = assetID
    }

    func waitUntilDeleteIsSuspended(_ assetID: String) async -> Bool {
        for _ in 0..<5_000 {
            if suspendedDeleteAssetIDs.contains(assetID) { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return suspendedDeleteAssetIDs.contains(assetID)
    }

    func resumeSuspendedDelete(of assetID: String) {
        if suspendedAssetID == assetID {
            suspendedAssetID = nil
        }
        let continuation = deleteContinuations.removeValue(forKey: assetID)
        continuation?.resume()
    }

    func restoreAsset(id: String, bytes: Data) {
        assets[id] = bytes
    }

    func snapshot() -> Snapshot {
        Snapshot(assets: assets, deleteRequests: deleteRequests)
    }
}

private actor SequencedCloudPhotoAssetInboundJournal:
    CloudPhotoAssetInboundJournaling {
    private var pendingResults: [Result<Set<String>, FixtureError>]
    private var pendingAssetIDs = Set<String>()

    init(pendingResults: [Result<Set<String>, FixtureError>]) {
        self.pendingResults = pendingResults
    }

    func pendingInboundAssetIDs() async throws -> Set<String> {
        guard !pendingResults.isEmpty else { return pendingAssetIDs }
        let result = try pendingResults.removeFirst().get()
        pendingAssetIDs = result
        return result
    }

    func acquireCleanupLease(
        for assetID: String
    ) async throws -> CloudPhotoAssetInboundCleanupLease? {
        guard !(try await pendingInboundAssetIDs()).contains(assetID) else {
            return nil
        }
        return CloudPhotoAssetInboundCleanupLease(assetID: assetID)
    }

    func releaseCleanupLease(
        _ lease: CloudPhotoAssetInboundCleanupLease
    ) async {
        _ = lease
    }

    func recordInboundAssetID(_ assetID: String) async throws {
        pendingAssetIDs.insert(assetID)
    }

    func clearInboundAssetID(_ assetID: String) async throws {
        pendingAssetIDs.remove(assetID)
    }
}

private final class PhotoAssetCleanupJournalFake:
    PhotoAssetCleanupJournaling,
    @unchecked Sendable {
    private var pendingAssetIDs: Set<String>
    var addError: Error?

    init(
        pendingAssetIDs: Set<String> = [],
        addError: Error? = nil
    ) {
        self.pendingAssetIDs = pendingAssetIDs
        self.addError = addError
    }

    func loadPendingAssetIDs() async throws -> Set<String> {
        pendingAssetIDs
    }

    func addPendingAssetID(_ assetID: String) async throws {
        if let addError { throw addError }
        pendingAssetIDs.insert(assetID)
    }

    func removePendingAssetID(_ assetID: String) async throws {
        pendingAssetIDs.remove(assetID)
    }
}
