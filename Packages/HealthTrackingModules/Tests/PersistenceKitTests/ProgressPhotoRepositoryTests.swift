import CoreModels
import Foundation
import ProgressPhotosKit
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
        ).pendingDeletionAssetIDs()

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
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL),
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
        ).pendingDeletionAssetIDs()
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
            inboundAssetJournal: FileCloudPhotoAssetInboundJournal(fileURL: inboundURL),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("retry-transfers", isDirectory: true)
            )
        )

        _ = try await retryCoordinator.synchronize()
        let retriedDeletes = await retryDatabase.deleteRequests
        let pendingAfterSuccess = try await retryDeletionStore.pendingDeletionAssetIDs()
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
        ).pendingDeletionAssetIDs()
        let intentCalls = await deletionIntentStore.calls()
        let persisted = try context.fetch(FetchDescriptor<ProgressPhoto>())

        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(intentCalls.recordCalls, [])
        XCTAssertEqual(intentCalls.clearCalls, [])
        XCTAssertEqual(intentCalls.clearAllCallCount, 0)
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
        ).pendingDeletionAssetIDs()
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
        ).pendingDeletionAssetIDs()
        let intentCalls = await recordingIntentStore.calls()
        let persisted = try context.fetch(FetchDescriptor<ProgressPhoto>())

        XCTAssertTrue(pendingAfterReturn.isEmpty)
        XCTAssertEqual(intentCalls.recordCalls, [assetID])
        XCTAssertEqual(intentCalls.clearCalls, [assetID])
        XCTAssertEqual(intentCalls.clearAllCallCount, 0)
        XCTAssertEqual(persisted.map(\.id), [photoID])
        XCTAssertEqual(assetStore.deleteRequests, [assetID])
        XCTAssertEqual(trace.snapshot().last, .intentCleared)
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
            inboundAssetJournal: inboundJournal,
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
            inboundAssetJournal: inboundJournal,
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
            inboundAssetJournal: inboundJournal,
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

private enum FixtureError: Error, Equatable {
    case save
    case restoreCrash
    case restoreBeforeInboundIntent
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

private actor RecordingCloudPhotoAssetDeletionIntentStore:
    CloudPhotoAssetDeletionIntentStoring {
    struct Calls: Equatable, Sendable {
        let recordCalls: [String]
        let clearCalls: [String]
        let clearAllCallCount: Int
    }

    private let backing: FileCloudPhotoAssetDeletionIntentStore
    private var recordCalls: [String] = []
    private var clearCalls: [String] = []
    private var clearAllCallCount = 0

    init(backing: FileCloudPhotoAssetDeletionIntentStore) {
        self.backing = backing
    }

    func pendingDeletionAssetIDs() async throws -> Set<String> {
        try await backing.pendingDeletionAssetIDs()
    }

    func recordCommittedDeletion(assetID: String) async throws {
        recordCalls.append(assetID)
        try await backing.recordCommittedDeletion(assetID: assetID)
    }

    func clearCommittedDeletion(assetID: String) async throws {
        clearCalls.append(assetID)
        try await backing.clearCommittedDeletion(assetID: assetID)
    }

    func clearAllCommittedDeletions() async throws {
        clearAllCallCount += 1
        try await backing.clearAllCommittedDeletions()
    }

    func calls() -> Calls {
        Calls(
            recordCalls: recordCalls,
            clearCalls: clearCalls,
            clearAllCallCount: clearAllCallCount
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

    func pendingDeletionAssetIDs() async throws -> Set<String> {
        try await backing.pendingDeletionAssetIDs()
    }

    func recordCommittedDeletion(assetID: String) async throws {
        try await backing.recordCommittedDeletion(assetID: assetID)
        trace.append(.intentRecorded)
    }

    func clearCommittedDeletion(assetID: String) async throws {
        trace.append(.intentClearStarted)
        clearWasAttempted = true
        await withCheckedContinuation { continuation in
            clearContinuation = continuation
        }
        try await backing.clearCommittedDeletion(assetID: assetID)
        trace.append(.intentCleared)
    }

    func clearAllCommittedDeletions() async throws {
        try await backing.clearAllCommittedDeletions()
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
        deleteObserver: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.importResults = importResults
        self.loadResults = loadResults
        self.deleteResults = deleteResults
        self.localAssetIDs = localAssetIDs
        self.cloudAssets = cloudAssets
        self.restoreErrorAfterWrite = restoreErrorAfterWrite
        self.requiredInboundJournal = requiredInboundJournal
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
    private(set) var deleteRequests: [String] = []

    init(
        deleteResults: [Result<Void, CloudPhotoAssetDatabaseError>] = [],
        changePage: CloudPhotoAssetChangePage? = nil
    ) {
        self.deleteResults = deleteResults
        self.changePage = changePage
    }

    func accountStatus() async throws -> CloudPhotoAccountStatus { .available }
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
        return changePage ?? .init(
            changes: [],
            changeToken: previousToken ?? Data([0]),
            moreComing: false
        )
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
