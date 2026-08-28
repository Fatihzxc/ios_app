import Foundation
import ProgressPhotosKit
import XCTest

@MainActor
final class CloudPhotoAssetCoordinatorTests: XCTestCase {
    func testEveryUnavailableAccountStateDefersWithoutTouchingLocalAssetsOrQueue() async throws {
        let assetID = "00000000-0000-0000-0000-000000000911"
        let originalState = CloudPhotoAssetSyncState(
            pendingUploadAssetIDs: [assetID]
        )
        let unavailableStates: [CloudPhotoAccountStatus] = [
            .restricted,
            .noAccount,
            .temporarilyUnavailable,
            .couldNotDetermine,
        ]

        for status in unavailableStates {
            let database = CloudPhotoAssetDatabaseFake(accountStatus: status)
            let local = CloudPhotoAssetLocalStoreFake(assets: [assetID: Data([1])])
            let stateStore = CloudPhotoAssetSyncStateStoreFake(state: originalState)
            let coordinator = try makeCoordinator(
                database: database,
                local: local,
                stateStore: stateStore
            )

            let outcome = try await coordinator.synchronize()
            let databaseSnapshot = await database.snapshot()
            let localSnapshot = await local.snapshot()
            let persistedState = try await stateStore.load()

            XCTAssertEqual(outcome, .deferred(status))
            XCTAssertTrue(databaseSnapshot.ensuredZones.isEmpty)
            XCTAssertTrue(databaseSnapshot.saveRequests.isEmpty)
            XCTAssertEqual(localSnapshot.assets, [assetID: Data([1])])
            XCTAssertEqual(persistedState, originalState)
        }
    }

    func testBackfillWaitsForServerResponseUsesPrivateZoneAndCleansUploadFile() async throws {
        let assetID = "00000000-0000-0000-0000-000000000912"
        let bytes = Data([1, 2, 3, 4])
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            suspendedSaveCalls: [1]
        )
        let local = CloudPhotoAssetLocalStoreFake(assets: [assetID: bytes])
        let stateStore = CloudPhotoAssetSyncStateStoreFake()
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            referencedAssetIDs: [assetID]
        )

        let synchronization = Task { try await coordinator.synchronize() }
        await database.waitForSaveCall(1)

        let suspendedDatabase = await database.snapshot()
        let upload = try XCTUnwrap(suspendedDatabase.saveRequests.first)
        let pendingState = try await stateStore.load()
        XCTAssertEqual(
            suspendedDatabase.ensuredZones,
            [CloudPhotoAssetRecordContract.zoneName]
        )
        XCTAssertEqual(upload.zoneName, CloudPhotoAssetRecordContract.zoneName)
        XCTAssertEqual(upload.request.assetID, assetID)
        XCTAssertEqual(
            upload.request.recordName,
            "progress-photo-asset-\(assetID)"
        )
        XCTAssertEqual(upload.request.byteCount, bytes.count)
        XCTAssertEqual(
            upload.request.checksum,
            CloudPhotoAssetChecksum.sha256Hex(bytes)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: upload.request.fileURL.path))
        XCTAssertEqual(pendingState.pendingUploadAssetIDs, [assetID])
        XCTAssertTrue(pendingState.uploadedAssetIDs.isEmpty)

        await database.resumeSave(call: 1)
        let outcome = try await synchronization.value
        let finalState = try await stateStore.load()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertFalse(FileManager.default.fileExists(atPath: upload.request.fileURL.path))
        XCTAssertTrue(finalState.pendingUploadAssetIDs.isEmpty)
        XCTAssertEqual(finalState.uploadedAssetIDs, [assetID])
    }

    func testMatchingExistingRecordIsIdempotentAndSkipsAssetSave() async throws {
        let assetID = "00000000-0000-0000-0000-000000000913"
        let bytes = Data([9, 1, 3])
        let metadata = try metadata(assetID: assetID, bytes: bytes)
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            records: [metadata.recordName: metadata]
        )
        let local = CloudPhotoAssetLocalStoreFake(assets: [assetID: bytes])
        let stateStore = CloudPhotoAssetSyncStateStoreFake()
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            referencedAssetIDs: [assetID]
        )

        let outcome = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(databaseSnapshot.recordRequests, [metadata.recordName])
        XCTAssertTrue(databaseSnapshot.saveRequests.isEmpty)
        XCTAssertTrue(state.pendingUploadAssetIDs.isEmpty)
        XCTAssertEqual(state.uploadedAssetIDs, [assetID])
    }

    func testRetryableSaveUsesInjectedExponentialBackoffThenCommits() async throws {
        let assetID = "00000000-0000-0000-0000-000000000914"
        let bytes = Data([9, 1, 4])
        let expectedMetadata = try metadata(assetID: assetID, bytes: bytes)
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            saveResults: [
                .failure(.retryable(retryAfter: nil)),
                .failure(.retryable(retryAfter: nil)),
                .success(expectedMetadata),
            ]
        )
        let local = CloudPhotoAssetLocalStoreFake(assets: [assetID: bytes])
        let stateStore = CloudPhotoAssetSyncStateStoreFake()
        let sleeper = CloudPhotoAssetSleeperFake()
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            referencedAssetIDs: [assetID],
            retryPolicy: .init(
                maximumAttempts: 3,
                baseDelay: 1,
                maximumDelay: 8
            ),
            sleeper: sleeper
        )

        let outcome = try await coordinator.synchronize()
        let delays = await sleeper.delays
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(delays, [1, 2])
        XCTAssertEqual(databaseSnapshot.saveRequests.count, 3)
        XCTAssertEqual(state.uploadedAssetIDs, [assetID])
    }

    func testPaginatedChangesPersistOpaqueTokenRebuildDownloadAndApplyDeletion() async throws {
        let downloadedID = "00000000-0000-0000-0000-000000000915"
        let deletedID = "00000000-0000-0000-0000-000000000916"
        let downloadedBytes = Data([9, 1, 5])
        let temporaryDirectory = try makeTemporaryDirectory()
        let ownedDirectory = temporaryDirectory.appendingPathComponent(
            "owned",
            isDirectory: true
        )
        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: ownedDirectory
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: downloadedBytes)
        let download = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: downloadedID),
            assetID: downloadedID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(downloadedBytes),
            byteCount: downloadedBytes.count,
            stagedFileURL: stagedURL
        )
        let firstToken = Data([1])
        let secondToken = Data([2])
        let finalToken = Data([3])
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            changeResults: [
                .success(
                    .init(
                        changes: [.changed(download)],
                        changeToken: secondToken,
                        moreComing: true
                    )
                ),
                .success(
                    .init(
                        changes: [
                            .deleted(
                                recordName: try CloudPhotoAssetRecordContract
                                    .recordName(for: deletedID)
                            ),
                        ],
                        changeToken: finalToken,
                        moreComing: false
                    )
                ),
            ]
        )
        let local = CloudPhotoAssetLocalStoreFake(
            assets: [deletedID: Data([1])]
        )
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(
                uploadedAssetIDs: [deletedID],
                changeToken: firstToken
            )
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: local,
            stateStore: stateStore,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: local
            ),
            temporaryStore: temporaryStore
        )

        let outcome = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let localSnapshot = await local.snapshot()
        let state = try await stateStore.load()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(databaseSnapshot.changeTokens, [firstToken, secondToken])
        XCTAssertEqual(localSnapshot.restoredAssets, [downloadedID: downloadedBytes])
        XCTAssertEqual(localSnapshot.deletedAssetIDs, [deletedID])
        XCTAssertEqual(state.changeToken, finalToken)
        XCTAssertEqual(state.uploadedAssetIDs, [downloadedID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
        let ownedFiles = try FileManager.default.contentsOfDirectory(
            at: ownedDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(ownedFiles.isEmpty)
    }

    func testExpiredChangeTokenClearsPersistedTokenAndRestartsFromNil() async throws {
        let expiredToken = Data([7])
        let freshToken = Data([8])
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            changeResults: [
                .failure(.changeTokenExpired),
                .success(
                    .init(
                        changes: [],
                        changeToken: freshToken,
                        moreComing: false
                    )
                ),
            ]
        )
        let local = CloudPhotoAssetLocalStoreFake()
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(changeToken: expiredToken)
        )
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore
        )

        _ = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()

        XCTAssertEqual(databaseSnapshot.changeTokens, [expiredToken, nil])
        XCTAssertEqual(state.changeToken, freshToken)
    }

    func testInvalidDownloadDoesNotAdvanceTokenOrMutateLocalStore() async throws {
        let assetID = "00000000-0000-0000-0000-000000000917"
        let oldToken = Data([4])
        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: try makeTemporaryDirectory().appendingPathComponent(
                "owned",
                isDirectory: true
            )
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: Data([1, 2, 3]))
        let download = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: String(repeating: "0", count: 64),
            byteCount: 3,
            stagedFileURL: stagedURL
        )
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            changeResults: [
                .success(
                    .init(
                        changes: [.changed(download)],
                        changeToken: Data([5]),
                        moreComing: false
                    )
                ),
            ]
        )
        let local = CloudPhotoAssetLocalStoreFake()
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(changeToken: oldToken)
        )
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            referencedAssetIDs: [assetID],
            temporaryStore: temporaryStore
        )

        do {
            _ = try await coordinator.synchronize()
            XCTFail("A corrupt remote asset must fail closed.")
        } catch {
            XCTAssertEqual(
                error as? CloudPhotoAssetValidationError,
                .checksumMismatch
            )
        }
        let state = try await stateStore.load()
        let localSnapshot = await local.snapshot()
        XCTAssertEqual(state.changeToken, oldToken)
        XCTAssertTrue(localSnapshot.restoredAssets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
    }

    func testDeletionQueueTreatsMissingServerRecordAsIdempotentSuccess() async throws {
        let assetID = "00000000-0000-0000-0000-000000000918"
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            deleteResults: [.failure(.recordNotFound)]
        )
        let local = CloudPhotoAssetLocalStoreFake()
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(
                pendingDeletionAssetIDs: [assetID],
                uploadedAssetIDs: [assetID]
            )
        )
        let deletionIntents = CloudPhotoAssetDeletionIntentStoreFake(
            pendingAssetIDs: [assetID]
        )
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            deletionIntentStore: deletionIntents
        )

        let outcome = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(
            databaseSnapshot.deleteRequests,
            ["progress-photo-asset-\(assetID)"]
        )
        XCTAssertTrue(state.pendingDeletionAssetIDs.isEmpty)
        XCTAssertTrue(state.uploadedAssetIDs.isEmpty)
    }

    func testStateOnlyDeletionQueueCannotAuthorizeServerDeletion() async throws {
        let assetID = "00000000-0000-0000-0000-000000000927"
        let database = CloudPhotoAssetDatabaseFake(accountStatus: .available)
        let local = CloudPhotoAssetLocalStoreFake()
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(
                accountIdentity: "opaque-account-a",
                pendingDeletionAssetIDs: [assetID],
                uploadedAssetIDs: [assetID]
            )
        )
        let deletionIntents = CloudPhotoAssetDeletionIntentStoreFake()
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            deletionIntentStore: deletionIntents
        )

        let outcome = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()
        let pendingIntents = try await deletionIntents.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertTrue(databaseSnapshot.deleteRequests.isEmpty)
        XCTAssertTrue(state.pendingDeletionAssetIDs.isEmpty)
        XCTAssertEqual(state.uploadedAssetIDs, [assetID])
        XCTAssertTrue(pendingIntents.isEmpty)
    }

    func testReferencedMissingAssetRestoresFromCloudWithoutInferringDeletion() async throws {
        let assetID = "00000000-0000-0000-0000-000000000920"
        let bytes = Data([9, 2, 0])
        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: try makeTemporaryDirectory().appendingPathComponent(
                "owned",
                isDirectory: true
            )
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: bytes)
        let download = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            stagedFileURL: stagedURL
        )
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            changeResults: [
                .success(
                    .init(
                        changes: [.changed(download)],
                        changeToken: Data([2, 0]),
                        moreComing: false
                    )
                ),
            ]
        )
        let local = CloudPhotoAssetLocalStoreFake()
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(uploadedAssetIDs: [assetID])
        )
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            referencedAssetIDs: [assetID],
            temporaryStore: temporaryStore
        )

        let outcome = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let localSnapshot = await local.snapshot()
        let state = try await stateStore.load()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertTrue(databaseSnapshot.deleteRequests.isEmpty)
        XCTAssertEqual(localSnapshot.restoredAssets, [assetID: bytes])
        XCTAssertEqual(state.uploadedAssetIDs, [assetID])
        XCTAssertTrue(state.pendingDeletionAssetIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
    }

    func testOnlyExplicitCommittedMetadataDeletionQueuesServerDeletion() async throws {
        let assetID = "00000000-0000-0000-0000-000000000921"
        let database = CloudPhotoAssetDatabaseFake(accountStatus: .available)
        let local = CloudPhotoAssetLocalStoreFake()
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(uploadedAssetIDs: [assetID])
        )
        let deletionIntents = CloudPhotoAssetDeletionIntentStoreFake()
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            deletionIntentStore: deletionIntents
        )

        _ = try await coordinator.synchronize()
        let beforeCommittedDeletion = await database.snapshot()
        XCTAssertTrue(beforeCommittedDeletion.deleteRequests.isEmpty)

        _ = try await deletionIntents.recordCommittedDeletion(assetID: assetID)
        _ = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()
        let pendingIntents = try await deletionIntents.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )

        XCTAssertEqual(
            databaseSnapshot.deleteRequests,
            ["progress-photo-asset-\(assetID)"]
        )
        XCTAssertTrue(state.pendingDeletionAssetIDs.isEmpty)
        XCTAssertTrue(state.uploadedAssetIDs.isEmpty)
        XCTAssertTrue(pendingIntents.isEmpty)
    }

    func testReferencedMetadataNeutralizesStaleDeletionIntentWithoutDeletingCloudAsset() async throws {
        let assetID = "00000000-0000-0000-0000-000000000926"
        let bytes = Data([9, 2, 6])
        let database = CloudPhotoAssetDatabaseFake(accountStatus: .available)
        let local = CloudPhotoAssetLocalStoreFake(assets: [assetID: bytes])
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(
                accountIdentity: "opaque-account-a",
                pendingDeletionAssetIDs: [assetID],
                uploadedAssetIDs: [assetID]
            )
        )
        let deletionIntents = CloudPhotoAssetDeletionIntentStoreFake(
            pendingAssetIDs: [assetID]
        )
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            referencedAssetIDs: [assetID],
            deletionIntentStore: deletionIntents
        )

        let outcome = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()
        let pendingIntents = try await deletionIntents.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertTrue(databaseSnapshot.deleteRequests.isEmpty)
        XCTAssertEqual(databaseSnapshot.recordRequests, [
            "progress-photo-asset-\(assetID)",
        ])
        XCTAssertEqual(
            databaseSnapshot.saveRequests.map(\.request.assetID),
            [assetID]
        )
        XCTAssertTrue(state.pendingDeletionAssetIDs.isEmpty)
        XCTAssertTrue(state.pendingUploadAssetIDs.isEmpty)
        XCTAssertEqual(state.uploadedAssetIDs, [assetID])
        XCTAssertTrue(pendingIntents.isEmpty)
    }

    func testReferencedSnapshotNeutralizesOnlyObservedIntentAcrossSameAssetABA() async throws {
        let assetID = "00000000-0000-0000-0000-000000000946"
        let accountIdentity = "opaque-account-a"
        let bytes = Data([9, 4, 6])
        let directory = try makeTemporaryDirectory()
        let deletionIntents = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: directory.appendingPathComponent("cloud-deletions.json")
        )
        let initialResolution = await deletionIntents.beginAccountResolution()
        let initialAuthorization = try await deletionIntents.activateAccountIdentity(
            accountIdentity,
            resolution: initialResolution
        )
        let observedStaleIntent = try await deletionIntents.recordCommittedDeletion(
            assetID: assetID
        )
        await deletionIntents.suspendAccountAuthorization(initialAuthorization)
        let database = CloudPhotoAssetDatabaseFake(accountStatus: .available)
        let stateStore = FileCloudPhotoAssetSyncStateStore(
            fileURL: directory.appendingPathComponent("cloud-state.json")
        )
        try await stateStore.save(
            .init(
                accountIdentity: accountIdentity,
                pendingDeletionAssetIDs: [assetID],
                uploadedAssetIDs: [assetID]
            )
        )
        let referenceProvider = CloudPhotoAssetReferenceSnapshotProviderFake(
            referencedAssetIDs: [assetID],
            suspendedSnapshotCalls: [1]
        )
        let localStore = CloudPhotoAssetLocalStoreFake(assets: [assetID: bytes])
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: localStore,
            stateStore: stateStore,
            referenceSnapshotProvider: referenceProvider,
            deletionIntentStore: deletionIntents,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: localStore
            ),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("owned", isDirectory: true)
            ),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: 0, maximumDelay: 0),
            sleep: { _ in }
        )

        let synchronization = Task {
            try await coordinator.synchronize()
        }
        await referenceProvider.waitForSnapshotCall(1)
        let replacementIntent = try await deletionIntents.recordCommittedDeletion(
            assetID: assetID
        )
        await referenceProvider.resumeSnapshot(call: 1)

        let outcome = try await synchronization.value
        let remainingIntents = try await deletionIntents.pendingDeletionIntents(
            forAccountIdentity: accountIdentity
        )
        let databaseSnapshot = await database.snapshot()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertNotEqual(observedStaleIntent.intentID, replacementIntent.intentID)
        XCTAssertEqual(remainingIntents.map(\.intentID), [replacementIntent.intentID])
        XCTAssertTrue(databaseSnapshot.deleteRequests.isEmpty)

        let retryDatabase = CloudPhotoAssetDatabaseFake(accountStatus: .available)
        let retryCoordinator = CloudPhotoAssetCoordinator(
            database: retryDatabase,
            localStore: localStore,
            stateStore: stateStore,
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: []
            ),
            deletionIntentStore: deletionIntents,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: localStore
            ),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent(
                    "retry-owned",
                    isDirectory: true
                )
            ),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: 0, maximumDelay: 0),
            sleep: { _ in }
        )

        let retryOutcome = try await retryCoordinator.synchronize()
        let retrySnapshot = await retryDatabase.snapshot()
        let intentsAfterRetry = try await deletionIntents.pendingDeletionIntents(
            forAccountIdentity: accountIdentity
        )
        let stateAfterRetry = try await stateStore.load()

        XCTAssertEqual(retryOutcome, .synchronized)
        XCTAssertEqual(
            retrySnapshot.deleteRequests,
            ["progress-photo-asset-\(assetID)"]
        )
        XCTAssertTrue(intentsAfterRetry.isEmpty)
        XCTAssertTrue(stateAfterRetry.pendingDeletionAssetIDs.isEmpty)
    }

    func testAccountIdentityChangeResetsStateAndBackfillsNewAccount() async throws {
        let assetID = "00000000-0000-0000-0000-000000000922"
        let deletedID = "00000000-0000-0000-0000-000000000923"
        let bytes = Data([9, 2, 2])
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            accountIdentity: "opaque-account-b"
        )
        let local = CloudPhotoAssetLocalStoreFake(assets: [assetID: bytes])
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(
                accountIdentity: "opaque-account-a",
                pendingDeletionAssetIDs: [deletedID],
                uploadedAssetIDs: [assetID, deletedID],
                changeToken: Data([0xa])
            )
        )
        let deletionIntents = CloudPhotoAssetDeletionIntentStoreFake(
            pendingAssetIDs: [deletedID]
        )
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            referencedAssetIDs: [assetID],
            deletionIntentStore: deletionIntents
        )

        let outcome = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()
        let pendingIntents = try await deletionIntents.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(databaseSnapshot.saveRequests.map(\.request.assetID), [assetID])
        XCTAssertTrue(databaseSnapshot.deleteRequests.isEmpty)
        XCTAssertEqual(databaseSnapshot.changeTokens, [nil])
        XCTAssertEqual(state.accountIdentity, "opaque-account-b")
        XCTAssertEqual(state.uploadedAssetIDs, [assetID])
        XCTAssertTrue(state.pendingDeletionAssetIDs.isEmpty)
        XCTAssertNotEqual(state.changeToken, Data([0xa]))
        XCTAssertEqual(pendingIntents, [deletedID])
    }

    func testAccountResetLoadsCurrentScopeAndPreservesOldAccountQueue() async throws {
        let oldAccountAssetID = "00000000-0000-0000-0000-000000000930"
        let currentAccountAssetID = "00000000-0000-0000-0000-000000000931"
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            accountIdentity: "opaque-account-b"
        )
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(
                accountIdentity: "opaque-account-a",
                pendingDeletionAssetIDs: [oldAccountAssetID],
                uploadedAssetIDs: [oldAccountAssetID]
            )
        )
        let deletionIntents = CloudPhotoAssetDeletionIntentStoreFake(
            pendingAssetIDsByAccount: [
                "opaque-account-a": [oldAccountAssetID],
                "opaque-account-b": [currentAccountAssetID],
            ]
        )
        let coordinator = try makeCoordinator(
            database: database,
            local: CloudPhotoAssetLocalStoreFake(),
            stateStore: stateStore,
            deletionIntentStore: deletionIntents
        )

        let outcome = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()
        let oldAccountIntents = try await deletionIntents.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )
        let pendingIntents = try await deletionIntents.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-b"
        )

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(
            databaseSnapshot.deleteRequests,
            ["progress-photo-asset-\(currentAccountAssetID)"]
        )
        XCTAssertFalse(
            databaseSnapshot.deleteRequests.contains(
                "progress-photo-asset-\(oldAccountAssetID)"
            )
        )
        XCTAssertEqual(state.accountIdentity, "opaque-account-b")
        XCTAssertTrue(state.pendingDeletionAssetIDs.isEmpty)
        XCTAssertTrue(pendingIntents.isEmpty)
        XCTAssertEqual(oldAccountIntents, [oldAccountAssetID])
    }

    func testAccountTransitionProcessesOnlyCurrentScopeAndPreservesOldAndUnresolvedIntents() async throws {
        let oldAccountAssetID = "00000000-0000-0000-0000-000000000938"
        let currentAccountAssetID = "00000000-0000-0000-0000-000000000939"
        let unresolvedAssetID = "00000000-0000-0000-0000-00000000093a"
        let directory = try makeTemporaryDirectory()
        let deletionURL = directory.appendingPathComponent("cloud-deletions.json")
        let deletionIntents = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        )
        _ = try await deletionIntents.recordCommittedDeletion(
            assetID: unresolvedAssetID
        )
        let accountAResolution = await deletionIntents.beginAccountResolution()
        _ = try await deletionIntents.activateAccountIdentity(
            "opaque-account-a",
            resolution: accountAResolution
        )
        _ = try await deletionIntents.recordCommittedDeletion(
            assetID: oldAccountAssetID
        )
        let accountBResolution = await deletionIntents.beginAccountResolution()
        _ = try await deletionIntents.activateAccountIdentity(
            "opaque-account-b",
            resolution: accountBResolution
        )
        _ = try await deletionIntents.recordCommittedDeletion(
            assetID: currentAccountAssetID
        )
        let recreatedBeforeIdentityResolution = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: deletionURL
        )
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            accountIdentity: "opaque-account-b"
        )
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(
                accountIdentity: "opaque-account-a",
                pendingDeletionAssetIDs: [oldAccountAssetID],
                uploadedAssetIDs: [oldAccountAssetID]
            )
        )
        let localStore = CloudPhotoAssetLocalStoreFake()
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: localStore,
            stateStore: stateStore,
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: []
            ),
            deletionIntentStore: recreatedBeforeIdentityResolution,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: localStore
            ),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("transfers", isDirectory: true)
            )
        )

        let outcome = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()
        let oldAccountIDs = try await recreatedBeforeIdentityResolution
            .pendingDeletionAssetIDs(forAccountIdentity: "opaque-account-a")
        let currentAccountIDs = try await recreatedBeforeIdentityResolution
            .pendingDeletionAssetIDs(forAccountIdentity: "opaque-account-b")
        let unresolvedIDs = try await recreatedBeforeIdentityResolution
            .unresolvedDeletionAssetIDs()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(
            databaseSnapshot.deleteRequests,
            ["progress-photo-asset-\(currentAccountAssetID)"]
        )
        XCTAssertFalse(
            databaseSnapshot.deleteRequests.contains(
                "progress-photo-asset-\(oldAccountAssetID)"
            )
        )
        XCTAssertFalse(
            databaseSnapshot.deleteRequests.contains(
                "progress-photo-asset-\(unresolvedAssetID)"
            )
        )
        XCTAssertEqual(oldAccountIDs, [oldAccountAssetID])
        XCTAssertTrue(currentAccountIDs.isEmpty)
        XCTAssertEqual(unresolvedIDs, [unresolvedAssetID])
        XCTAssertEqual(state.accountIdentity, "opaque-account-b")
        XCTAssertTrue(state.pendingDeletionAssetIDs.isEmpty)
    }

    func testLegacyUnscopedFileStateResetsFailClosedAndBackfillsCurrentAccount() async throws {
        let assetID = "00000000-0000-0000-0000-000000000924"
        let staleDeletedID = "00000000-0000-0000-0000-000000000925"
        let bytes = Data([9, 2, 4])
        let directory = try makeTemporaryDirectory()
        let stateURL = directory.appendingPathComponent("state.json")
        let legacyJSON = """
        {"changeToken":"Cg==","pendingDeletionAssetIDs":["\(staleDeletedID)"],"pendingUploadAssetIDs":[],"uploadedAssetIDs":["\(assetID)","\(staleDeletedID)"]}
        """
        try Data(legacyJSON.utf8).write(to: stateURL)
        let stateStore = FileCloudPhotoAssetSyncStateStore(fileURL: stateURL)
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            accountIdentity: "opaque-account-current"
        )
        let local = CloudPhotoAssetLocalStoreFake(assets: [assetID: bytes])
        let deletionIntents = CloudPhotoAssetDeletionIntentStoreFake(
            unresolvedAssetIDs: [staleDeletedID]
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: local,
            stateStore: stateStore,
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: [assetID]
            ),
            deletionIntentStore: deletionIntents,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: local
            ),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("transfers", isDirectory: true)
            )
        )

        _ = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let recreatedState = try await FileCloudPhotoAssetSyncStateStore(
            fileURL: stateURL
        ).load()
        let remainingIntents = try await deletionIntents.unresolvedDeletionAssetIDs()

        XCTAssertEqual(databaseSnapshot.saveRequests.map(\.request.assetID), [assetID])
        XCTAssertTrue(databaseSnapshot.deleteRequests.isEmpty)
        XCTAssertEqual(databaseSnapshot.changeTokens, [nil])
        XCTAssertEqual(recreatedState.accountIdentity, "opaque-account-current")
        XCTAssertEqual(recreatedState.uploadedAssetIDs, [assetID])
        XCTAssertTrue(recreatedState.pendingDeletionAssetIDs.isEmpty)
        XCTAssertEqual(remainingIntents, [staleDeletedID])
    }

    func testVerifiedAccountOfflineDeletionSurvivesFailureAndRelaunchRetry() async throws {
        let assetID = "00000000-0000-0000-0000-00000000093e"
        let postFailureAssetID = "00000000-0000-0000-0000-00000000093f"
        let directory = try makeTemporaryDirectory()
        let deletionURL = directory.appendingPathComponent("deletions.json")
        let stateStore = CloudPhotoAssetSyncStateStoreFake()
        let localStore = CloudPhotoAssetLocalStoreFake()
        let firstStore = FileCloudPhotoAssetDeletionIntentStore(fileURL: deletionURL)
        let firstCoordinator = CloudPhotoAssetCoordinator(
            database: CloudPhotoAssetDatabaseFake(accountStatus: .available),
            localStore: localStore,
            stateStore: stateStore,
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: []
            ),
            deletionIntentStore: firstStore,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: localStore
            ),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("first-transfers")
            )
        )
        let firstOutcome = try await firstCoordinator.synchronize()
        XCTAssertEqual(firstOutcome, .synchronized)

        let offlineStore = FileCloudPhotoAssetDeletionIntentStore(fileURL: deletionURL)
        let offlineReceipt = try await offlineStore.recordCommittedDeletion(
            assetID: assetID
        )
        XCTAssertNil(offlineReceipt.accountIdentity)
        XCTAssertEqual(offlineReceipt.quarantineIdentityHint, "opaque-account-a")

        let failingDatabase = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            deleteResults: [.failure(.permanent)]
        )
        let failingStore = FileCloudPhotoAssetDeletionIntentStore(fileURL: deletionURL)
        let failingCoordinator = CloudPhotoAssetCoordinator(
            database: failingDatabase,
            localStore: localStore,
            stateStore: stateStore,
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: []
            ),
            deletionIntentStore: failingStore,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: localStore
            ),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("failing-transfers")
            ),
            retryPolicy: .init(maximumAttempts: 1, baseDelay: 0, maximumDelay: 0)
        )
        do {
            _ = try await failingCoordinator.synchronize()
            XCTFail("The first same-account cloud deletion must remain durable on failure.")
        } catch {
            XCTAssertEqual(error as? CloudPhotoAssetDatabaseError, .permanent)
        }

        let postFailureReceipt = try await failingStore.recordCommittedDeletion(
            assetID: postFailureAssetID
        )
        XCTAssertNil(postFailureReceipt.accountIdentity)
        XCTAssertEqual(
            postFailureReceipt.quarantineIdentityHint,
            "opaque-account-a",
            "A failed sync must close its account authorization before returning."
        )
        try await failingStore.clearCommittedDeletion(postFailureReceipt)
        let pendingAfterFailure = try await failingStore.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )
        let quarantineAfterExactClear = try await failingStore
            .unresolvedDeletionAssetIDs()
        XCTAssertEqual(pendingAfterFailure, [assetID])
        XCTAssertTrue(quarantineAfterExactClear.isEmpty)

        let retryDatabase = CloudPhotoAssetDatabaseFake(accountStatus: .available)
        let retryStore = FileCloudPhotoAssetDeletionIntentStore(fileURL: deletionURL)
        let retryCoordinator = CloudPhotoAssetCoordinator(
            database: retryDatabase,
            localStore: localStore,
            stateStore: stateStore,
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: []
            ),
            deletionIntentStore: retryStore,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: localStore
            ),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("retry-transfers")
            )
        )
        let retryOutcome = try await retryCoordinator.synchronize()
        XCTAssertEqual(retryOutcome, .synchronized)
        let retrySnapshot = await retryDatabase.snapshot()
        let pendingAfterRetry = try await retryStore.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )
        XCTAssertEqual(
            retrySnapshot.deleteRequests,
            ["progress-photo-asset-\(assetID)"]
        )
        XCTAssertTrue(pendingAfterRetry.isEmpty)
    }

    func testDeferredAccountTransitionQuarantinesOldHintUntilMatchingAccountReturns() async throws {
        let assetID = "00000000-0000-0000-0000-000000000940"
        let directory = try makeTemporaryDirectory()
        let deletionStore = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: directory.appendingPathComponent("deletions.json")
        )
        let stateStore = CloudPhotoAssetSyncStateStoreFake()
        let localStore = CloudPhotoAssetLocalStoreFake()

        func coordinator(database: CloudPhotoAssetDatabaseFake) -> CloudPhotoAssetCoordinator {
            CloudPhotoAssetCoordinator(
                database: database,
                localStore: localStore,
                stateStore: stateStore,
                referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                    referencedAssetIDs: []
                ),
                deletionIntentStore: deletionStore,
                inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                    inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                    localStore: localStore
                ),
                temporaryStore: FileCloudPhotoAssetTemporaryStore(
                    directory: directory.appendingPathComponent(UUID().uuidString)
                )
            )
        }

        let initialA = CloudPhotoAssetDatabaseFake(accountStatus: .available)
        _ = try await coordinator(database: initialA).synchronize()
        let deferredB = CloudPhotoAssetDatabaseFake(
            accountStatus: .temporarilyUnavailable,
            accountIdentity: "opaque-account-b"
        )
        let deferredOutcome = try await coordinator(database: deferredB).synchronize()
        XCTAssertEqual(deferredOutcome, .deferred(.temporarilyUnavailable))

        let quarantinedReceipt = try await deletionStore.recordCommittedDeletion(
            assetID: assetID
        )
        XCTAssertNil(quarantinedReceipt.accountIdentity)
        XCTAssertEqual(quarantinedReceipt.quarantineIdentityHint, "opaque-account-a")

        let availableB = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            accountIdentity: "opaque-account-b"
        )
        _ = try await coordinator(database: availableB).synchronize()
        let bSnapshot = await availableB.snapshot()
        let quarantinedUnderB = try await deletionStore.unresolvedDeletionAssetIDs()
        XCTAssertTrue(bSnapshot.deleteRequests.isEmpty)
        XCTAssertEqual(quarantinedUnderB, [assetID])

        let returningA = CloudPhotoAssetDatabaseFake(accountStatus: .available)
        _ = try await coordinator(database: returningA).synchronize()
        let aSnapshot = await returningA.snapshot()
        let quarantineAfterA = try await deletionStore.unresolvedDeletionAssetIDs()
        XCTAssertEqual(
            aSnapshot.deleteRequests,
            ["progress-photo-asset-\(assetID)"]
        )
        XCTAssertTrue(quarantineAfterA.isEmpty)
    }

    func testNewerSynchronizationWinsWhenOlderUploadCompletesLate() async throws {
        let assetID = "00000000-0000-0000-0000-000000000919"
        let bytes = Data([9, 1, 9])
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            suspendedSaveCalls: [1]
        )
        let local = CloudPhotoAssetLocalStoreFake(assets: [assetID: bytes])
        let stateStore = CloudPhotoAssetSyncStateStoreFake()
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            referencedAssetIDs: [assetID]
        )

        let older = Task { try await coordinator.synchronize() }
        await database.waitForSaveCall(1)
        let newerOutcome = try await coordinator.synchronize()
        await database.resumeSave(call: 1)

        do {
            _ = try await older.value
            XCTFail("The stale synchronization must be cancelled.")
        } catch is CancellationError {
            // Expected: only the newer generation can commit queue state.
        }
        let state = try await stateStore.load()
        let databaseSnapshot = await database.snapshot()
        XCTAssertEqual(newerOutcome, .synchronized)
        XCTAssertEqual(databaseSnapshot.saveRequests.count, 2)
        XCTAssertTrue(state.pendingUploadAssetIDs.isEmpty)
        XCTAssertEqual(state.uploadedAssetIDs, [assetID])
    }

    func testCancelledSynchronizationCleansOwnedPageDiscardedAfterSuspendedFetch() async throws {
        let assetID = "00000000-0000-0000-0000-000000000928"
        let bytes = Data([9, 2, 8])
        let directory = try makeTemporaryDirectory()
        let ownedDirectory = directory.appendingPathComponent(
            "owned",
            isDirectory: true
        )
        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: ownedDirectory
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: bytes)
        let record = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            stagedFileURL: stagedURL
        )
        let database = CloudPhotoAssetDatabaseFake(
            accountStatus: .available,
            changeResults: [
                .success(
                    .init(
                        changes: [.changed(record)],
                        changeToken: Data([9, 2, 8]),
                        moreComing: false
                    )
                ),
            ],
            suspendedChangeCalls: [1]
        )
        let deletionIntents = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: directory.appendingPathComponent("deletions.json")
        )
        let localStore = CloudPhotoAssetLocalStoreFake()
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: localStore,
            stateStore: CloudPhotoAssetSyncStateStoreFake(
                state: .init(accountIdentity: "opaque-account-a")
            ),
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: []
            ),
            deletionIntentStore: deletionIntents,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: localStore
            ),
            temporaryStore: temporaryStore
        )

        let synchronization = Task { try await coordinator.synchronize() }
        await database.waitForChangeCall(1)
        synchronization.cancel()
        await database.resumeChange(call: 1)

        do {
            _ = try await synchronization.value
            XCTFail("A cancelled fetch result must not reach local apply.")
        } catch is CancellationError {
            // Expected after the database returns its already-owned page.
        }
        let ownedFiles = try FileManager.default.contentsOfDirectory(
            at: ownedDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
        XCTAssertTrue(ownedFiles.isEmpty)
        let postCancellationAssetID = "00000000-0000-0000-0000-000000000941"
        let postCancellationReceipt = try await deletionIntents.recordCommittedDeletion(
            assetID: postCancellationAssetID
        )
        XCTAssertNil(postCancellationReceipt.accountIdentity)
        XCTAssertEqual(
            postCancellationReceipt.quarantineIdentityHint,
            "opaque-account-a",
            "Cancellation must close the bounded account authorization."
        )
        let postCancellationQuarantine = try await deletionIntents
            .unresolvedDeletionAssetIDs()
        XCTAssertEqual(postCancellationQuarantine, [postCancellationAssetID])
    }

    func testIntentCommittedAfterReadIsNotClearedAgainstOlderReferenceSnapshot() async throws {
        let assetID = "00000000-0000-0000-0000-000000000929"
        let bytes = Data([9, 2, 9])
        let database = CloudPhotoAssetDatabaseFake(accountStatus: .available)
        let local = CloudPhotoAssetLocalStoreFake(assets: [assetID: bytes])
        let stateStore = CloudPhotoAssetSyncStateStoreFake(
            state: .init(
                accountIdentity: "opaque-account-a",
                uploadedAssetIDs: [assetID]
            )
        )
        let deletionIntents = CloudPhotoAssetDeletionIntentStoreFake()
        let referenceProvider = CloudPhotoAssetReferenceSnapshotProviderFake(
            referencedAssetIDs: [assetID],
            suspendedSnapshotCalls: [1]
        )
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore,
            referenceSnapshotProvider: referenceProvider,
            deletionIntentStore: deletionIntents
        )

        let firstSynchronization = Task {
            try await coordinator.synchronize()
        }
        await referenceProvider.waitForSnapshotCall(1)
        _ = try await deletionIntents.recordCommittedDeletion(assetID: assetID)
        await referenceProvider.setReferencedAssetIDs([])
        await referenceProvider.resumeSnapshot(call: 1)

        let firstOutcome = try await firstSynchronization.value
        let afterFirstDatabase = await database.snapshot()
        let pendingAfterFirst = try await deletionIntents.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )

        XCTAssertEqual(firstOutcome, .synchronized)
        XCTAssertTrue(afterFirstDatabase.deleteRequests.isEmpty)
        XCTAssertEqual(pendingAfterFirst, [assetID])

        let secondOutcome = try await coordinator.synchronize()
        let afterSecondDatabase = await database.snapshot()
        let pendingAfterSecond = try await deletionIntents.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )

        XCTAssertEqual(secondOutcome, .synchronized)
        XCTAssertEqual(
            afterSecondDatabase.deleteRequests,
            ["progress-photo-asset-\(assetID)"]
        )
        XCTAssertTrue(pendingAfterSecond.isEmpty)
    }

    func testCorruptFullVariantWithPhysicalDirectoryReplaysNilTokenAndRepairsWithoutUpload() async throws {
        let assetID = "00000000-0000-0000-0000-000000000946"
        let cloudBytes = Data([0x46])
        let staleChangeToken = Data([0x46, 0x01])
        let repairedChangeToken = Data([0x46, 0x02])
        let directory = try makeTemporaryDirectory()
        let processor = CloudRepairPhotoImageProcessor()
        let localStore = LocalPhotoAssetStore(
            policy: .init(
                maximumInputBytes: 64,
                maximumPixelCount: 64,
                fullMaximumDimension: 8,
                thumbnailMaximumDimension: 4,
                encodingQuality: 0.7
            ),
            processor: processor,
            fileSystem: CloudRepairPhotoAssetFileSystem(
                applicationSupportDirectory: directory
            )
        )
        try await localStore.restoreCloudAsset(id: assetID, bytes: Data([0x01]))
        let assetDirectory = directory
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent(assetID, isDirectory: true)
        let fullURL = assetDirectory.appendingPathComponent("full.jpg")
        try Data([0xff]).write(to: fullURL, options: .atomic)

        let physicalBeforeRepair = try await localStore.storedAssetIDs()
        let usableBeforeRepair = try await localStore.usableCloudAssetIDs()
        XCTAssertEqual(physicalBeforeRepair, [assetID])
        XCTAssertTrue(usableBeforeRepair.isEmpty)

        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: directory.appendingPathComponent("transfers", isDirectory: true)
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: cloudBytes)
        let repairRecord = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(cloudBytes),
            byteCount: cloudBytes.count,
            stagedFileURL: stagedURL
        )
        let database = NilTokenOnlyRepairCloudPhotoAssetDatabase(
            repairRecord: repairRecord,
            repairedChangeToken: repairedChangeToken
        )
        let stateStore = FileCloudPhotoAssetSyncStateStore(
            fileURL: directory.appendingPathComponent("sync-state.json")
        )
        try await stateStore.save(
            .init(
                accountIdentity: "opaque-account-a",
                pendingUploadAssetIDs: [assetID],
                uploadedAssetIDs: [assetID],
                changeToken: staleChangeToken
            )
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: localStore,
            stateStore: stateStore,
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: [assetID]
            ),
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: localStore
            ),
            temporaryStore: temporaryStore
        )

        let firstOutcome = try await coordinator.synchronize()
        let firstState = try await stateStore.load()
        let secondOutcome = try await coordinator.synchronize()
        let finalState = try await stateStore.load()
        let databaseSnapshot = await database.snapshot()
        let repairedFull = try await localStore.loadAsset(id: assetID, variant: .full)
        let repairedThumbnail = try await localStore.loadAsset(
            id: assetID,
            variant: .thumbnail
        )
        let physicalAfterRepair = try await localStore.storedAssetIDs()
        let usableAfterRepair = try await localStore.usableCloudAssetIDs()

        XCTAssertEqual(firstOutcome, .synchronized)
        XCTAssertEqual(secondOutcome, .synchronized)
        XCTAssertEqual(databaseSnapshot.changeTokens, [nil, repairedChangeToken])
        XCTAssertEqual(databaseSnapshot.nilTokenRepairResponseCount, 1)
        XCTAssertTrue(databaseSnapshot.recordRequests.isEmpty)
        XCTAssertTrue(databaseSnapshot.saveRequests.isEmpty)
        XCTAssertTrue(databaseSnapshot.deleteRequests.isEmpty)
        XCTAssertEqual(repairedFull, .available(Data([0x10])))
        XCTAssertEqual(repairedThumbnail, .available(Data([0x20])))
        XCTAssertEqual(physicalAfterRepair, [assetID])
        XCTAssertEqual(usableAfterRepair, [assetID])
        XCTAssertEqual(firstState, finalState)
        XCTAssertEqual(finalState.uploadedAssetIDs, [assetID])
        XCTAssertTrue(finalState.pendingUploadAssetIDs.isEmpty)
        XCTAssertTrue(finalState.pendingDeletionAssetIDs.isEmpty)
        XCTAssertEqual(finalState.changeToken, repairedChangeToken)
    }

    func testMissingThumbnailWithPhysicalDirectoryReplaysNilTokenAndRepairsWithoutUpload() async throws {
        let assetID = "00000000-0000-0000-0000-000000000947"
        let cloudBytes = Data([0x47])
        let staleChangeToken = Data([0x47, 0x01])
        let repairedChangeToken = Data([0x47, 0x02])
        let directory = try makeTemporaryDirectory()
        let localStore = LocalPhotoAssetStore(
            policy: .init(
                maximumInputBytes: 64,
                maximumPixelCount: 64,
                fullMaximumDimension: 8,
                thumbnailMaximumDimension: 4,
                encodingQuality: 0.7
            ),
            processor: CloudRepairPhotoImageProcessor(),
            fileSystem: CloudRepairPhotoAssetFileSystem(
                applicationSupportDirectory: directory
            )
        )
        try await localStore.restoreCloudAsset(id: assetID, bytes: Data([0x01]))
        let assetDirectory = directory
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent(assetID, isDirectory: true)
        let thumbnailURL = assetDirectory.appendingPathComponent("thumbnail.jpg")
        try FileManager.default.removeItem(at: thumbnailURL)

        let physicalBeforeRepair = try await localStore.storedAssetIDs()
        let usableBeforeRepair = try await localStore.usableCloudAssetIDs()
        XCTAssertEqual(physicalBeforeRepair, [assetID])
        XCTAssertTrue(usableBeforeRepair.isEmpty)

        let temporaryStore = FileCloudPhotoAssetTemporaryStore(
            directory: directory.appendingPathComponent("transfers", isDirectory: true)
        )
        let stagedURL = try temporaryStore.createUploadFile(bytes: cloudBytes)
        let repairRecord = try CloudPhotoAssetDownloadRecord(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(cloudBytes),
            byteCount: cloudBytes.count,
            stagedFileURL: stagedURL
        )
        let database = NilTokenOnlyRepairCloudPhotoAssetDatabase(
            repairRecord: repairRecord,
            repairedChangeToken: repairedChangeToken
        )
        let stateStore = FileCloudPhotoAssetSyncStateStore(
            fileURL: directory.appendingPathComponent("sync-state.json")
        )
        try await stateStore.save(
            .init(
                accountIdentity: "opaque-account-a",
                pendingUploadAssetIDs: [assetID],
                uploadedAssetIDs: [assetID],
                changeToken: staleChangeToken
            )
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: localStore,
            stateStore: stateStore,
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: [assetID]
            ),
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
                localStore: localStore
            ),
            temporaryStore: temporaryStore
        )

        let firstOutcome = try await coordinator.synchronize()
        let firstState = try await stateStore.load()
        let secondOutcome = try await coordinator.synchronize()
        let finalState = try await stateStore.load()
        let databaseSnapshot = await database.snapshot()
        let repairedFull = try await localStore.loadAsset(id: assetID, variant: .full)
        let repairedThumbnail = try await localStore.loadAsset(
            id: assetID,
            variant: .thumbnail
        )
        let physicalAfterRepair = try await localStore.storedAssetIDs()
        let usableAfterRepair = try await localStore.usableCloudAssetIDs()

        XCTAssertEqual(firstOutcome, .synchronized)
        XCTAssertEqual(secondOutcome, .synchronized)
        XCTAssertEqual(databaseSnapshot.changeTokens, [nil, repairedChangeToken])
        XCTAssertEqual(databaseSnapshot.nilTokenRepairResponseCount, 1)
        XCTAssertTrue(databaseSnapshot.recordRequests.isEmpty)
        XCTAssertTrue(databaseSnapshot.saveRequests.isEmpty)
        XCTAssertTrue(databaseSnapshot.deleteRequests.isEmpty)
        XCTAssertEqual(repairedFull, .available(Data([0x10])))
        XCTAssertEqual(repairedThumbnail, .available(Data([0x20])))
        XCTAssertEqual(physicalAfterRepair, [assetID])
        XCTAssertEqual(usableAfterRepair, [assetID])
        XCTAssertEqual(firstState, finalState)
        XCTAssertEqual(finalState.uploadedAssetIDs, [assetID])
        XCTAssertTrue(finalState.pendingUploadAssetIDs.isEmpty)
        XCTAssertTrue(finalState.pendingDeletionAssetIDs.isEmpty)
        XCTAssertEqual(finalState.changeToken, repairedChangeToken)
    }

    private func makeCoordinator(
        database: CloudPhotoAssetDatabaseFake,
        local: CloudPhotoAssetLocalStoreFake,
        stateStore: CloudPhotoAssetSyncStateStoreFake,
        referencedAssetIDs: Set<String> = [],
        referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake? = nil,
        deletionIntentStore: CloudPhotoAssetDeletionIntentStoreFake = .init(),
        inboundJournal: CloudPhotoAssetInboundJournalFake = .init(),
        temporaryStore: FileCloudPhotoAssetTemporaryStore? = nil,
        retryPolicy: CloudPhotoAssetRetryPolicy = .init(
            maximumAttempts: 1,
            baseDelay: 0,
            maximumDelay: 0
        ),
        sleeper: CloudPhotoAssetSleeperFake = CloudPhotoAssetSleeperFake()
    ) throws -> CloudPhotoAssetCoordinator {
        let resolvedTemporaryStore: FileCloudPhotoAssetTemporaryStore
        if let temporaryStore {
            resolvedTemporaryStore = temporaryStore
        } else {
            let directory = try makeTemporaryDirectory()
            resolvedTemporaryStore = FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("owned", isDirectory: true)
            )
        }
        return CloudPhotoAssetCoordinator(
            database: database,
            localStore: local,
            stateStore: stateStore,
            referenceSnapshotProvider: referenceSnapshotProvider
                ?? CloudPhotoAssetReferenceSnapshotProviderFake(
                    referencedAssetIDs: referencedAssetIDs
                ),
            deletionIntentStore: deletionIntentStore,
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: inboundJournal,
                localStore: local
            ),
            temporaryStore: resolvedTemporaryStore,
            retryPolicy: retryPolicy,
            sleep: { delay in try await sleeper.sleep(delay) }
        )
    }

    private func metadata(
        assetID: String,
        bytes: Data
    ) throws -> CloudPhotoAssetRecordMetadata {
        try CloudPhotoAssetRecordMetadata(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private final class CloudRepairPhotoImageProcessor:
    PhotoImageProcessing,
    @unchecked Sendable {
    func inspect(_ bytes: Data) throws -> PhotoImageMetadata {
        guard bytes != Data([0xff]) else {
            throw PhotoImageProcessingError.corruptInput
        }
        return PhotoImageMetadata(
            pixelWidth: 2,
            pixelHeight: 2,
            orientation: .up
        )
    }

    func normalize(
        _ bytes: Data,
        metadata: PhotoImageMetadata,
        policy: PhotoAssetPolicy
    ) throws -> PhotoNormalizedAsset {
        _ = bytes
        _ = metadata
        _ = policy
        return PhotoNormalizedAsset(
            full: .init(
                bytes: Data([0x10]),
                pixelWidth: 2,
                pixelHeight: 2,
                orientation: .up,
                containsMetadata: false
            ),
            thumbnail: .init(
                bytes: Data([0x20]),
                pixelWidth: 1,
                pixelHeight: 1,
                orientation: .up,
                containsMetadata: false
            )
        )
    }
}

private final class CloudRepairPhotoAssetFileSystem:
    PhotoAssetFileSystem,
    @unchecked Sendable {
    private let root: URL
    private let fileManager = FileManager.default

    init(applicationSupportDirectory: URL) {
        root = applicationSupportDirectory
    }

    func applicationSupportDirectory() throws -> URL { root }

    func createProtectedDirectory(at url: URL) throws {
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            throw PhotoAssetFileSystemError.operationFailed
        }
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func writeProtectedAtomically(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PhotoAssetFileSystemError.operationFailed
        }
    }

    func moveItem(at source: URL, to destination: URL) throws {
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw PhotoAssetFileSystemError.operationFailed
        }
    }

    func replaceItem(at destination: URL, withItemAt source: URL) throws {
        do {
            try fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw PhotoAssetFileSystemError.operationFailed
        }
    }

    func data(at url: URL) throws -> Data {
        guard fileExists(at: url) else {
            throw PhotoAssetFileSystemError.notFound
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw PhotoAssetFileSystemError.operationFailed
        }
    }

    func removeItemIfExists(at url: URL) throws {
        guard fileExists(at: url) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw PhotoAssetFileSystemError.operationFailed
        }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        guard fileExists(at: url) else { return [] }
        do {
            return try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw PhotoAssetFileSystemError.operationFailed
        }
    }
}

private actor NilTokenOnlyRepairCloudPhotoAssetDatabase:
    PrivateCloudPhotoAssetDatabase {
    struct Snapshot: Sendable {
        let recordRequests: [String]
        let saveRequests: [String]
        let deleteRequests: [String]
        let changeTokens: [Data?]
        let nilTokenRepairResponseCount: Int
    }

    private let repairRecord: CloudPhotoAssetDownloadRecord
    private let repairedChangeToken: Data
    private var recordRequests: [String] = []
    private var saveRequests: [String] = []
    private var deleteRequests: [String] = []
    private var changeTokens: [Data?] = []
    private var nilTokenRepairResponseCount = 0

    init(
        repairRecord: CloudPhotoAssetDownloadRecord,
        repairedChangeToken: Data
    ) {
        self.repairRecord = repairRecord
        self.repairedChangeToken = repairedChangeToken
    }

    func accountStatus() async throws -> CloudPhotoAccountStatus { .available }

    func accountIdentity() async throws -> String { "opaque-account-a" }

    func ensureZone(named zoneName: String) async throws {
        _ = zoneName
    }

    func record(
        named recordName: String,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata? {
        _ = zoneName
        recordRequests.append(recordName)
        return nil
    }

    func save(
        _ request: CloudPhotoAssetUploadRequest,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata {
        _ = zoneName
        saveRequests.append(request.assetID)
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
    }

    func fetchChanges(
        inZone zoneName: String,
        previousToken: Data?
    ) async throws -> CloudPhotoAssetChangePage {
        _ = zoneName
        changeTokens.append(previousToken)
        guard previousToken == nil else {
            return CloudPhotoAssetChangePage(
                changes: [],
                changeToken: previousToken ?? repairedChangeToken,
                moreComing: false
            )
        }
        nilTokenRepairResponseCount += 1
        return CloudPhotoAssetChangePage(
            changes: [.changed(repairRecord)],
            changeToken: repairedChangeToken,
            moreComing: false
        )
    }

    func snapshot() -> Snapshot {
        Snapshot(
            recordRequests: recordRequests,
            saveRequests: saveRequests,
            deleteRequests: deleteRequests,
            changeTokens: changeTokens,
            nilTokenRepairResponseCount: nilTokenRepairResponseCount
        )
    }
}

private actor CloudPhotoAssetSleeperFake {
    private(set) var delays: [TimeInterval] = []

    func sleep(_ delay: TimeInterval) async throws {
        delays.append(delay)
    }
}

private actor CloudPhotoAssetReferenceSnapshotProviderFake:
    CloudPhotoAssetReferenceSnapshotProviding {
    private var referencedAssetIDs: Set<String>
    private let suspendedSnapshotCalls: Set<Int>
    private var snapshotCallCount = 0
    private var snapshotContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var snapshotWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        referencedAssetIDs: Set<String>,
        suspendedSnapshotCalls: Set<Int> = []
    ) {
        self.referencedAssetIDs = referencedAssetIDs
        self.suspendedSnapshotCalls = suspendedSnapshotCalls
    }

    func snapshot() async throws -> CloudPhotoAssetReferenceSnapshot {
        snapshotCallCount += 1
        let call = snapshotCallCount
        let capturedAssetIDs = referencedAssetIDs
        notifySnapshotWaiters()
        if suspendedSnapshotCalls.contains(call) {
            await withCheckedContinuation { continuation in
                snapshotContinuations[call] = continuation
            }
        }
        return CloudPhotoAssetReferenceSnapshot(
            referencedAssetIDs: capturedAssetIDs
        )
    }

    func setReferencedAssetIDs(_ assetIDs: Set<String>) {
        referencedAssetIDs = assetIDs
    }

    func waitForSnapshotCall(_ expectedCount: Int) async {
        guard snapshotCallCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            snapshotWaiters.append((expectedCount, continuation))
        }
    }

    func resumeSnapshot(call: Int) {
        snapshotContinuations.removeValue(forKey: call)?.resume()
    }

    private func notifySnapshotWaiters() {
        let ready = snapshotWaiters.filter { snapshotCallCount >= $0.0 }
        snapshotWaiters.removeAll { snapshotCallCount >= $0.0 }
        for (_, continuation) in ready { continuation.resume() }
    }
}

private actor CloudPhotoAssetDeletionIntentStoreFake:
    CloudPhotoAssetDeletionIntentStoring {
    private var pendingAssetIDsByAccount: [String: Set<String>]
    private var unresolvedAssetIDs: Set<String>
    private var quarantinedAssetIDsByAccountHint: [String: Set<String>] = [:]
    private var lastVerifiedAccountIdentity: String?
    private var activeAccountResolution: CloudPhotoAssetAccountResolution?
    private var activeAuthorization: CloudPhotoAssetAccountAuthorization?

    init(
        pendingAssetIDs: Set<String> = [],
        pendingAssetIDsByAccount: [String: Set<String>]? = nil,
        unresolvedAssetIDs: Set<String> = []
    ) {
        self.pendingAssetIDsByAccount = pendingAssetIDsByAccount
            ?? (pendingAssetIDs.isEmpty
                ? [:]
                : ["opaque-account-a": pendingAssetIDs])
        self.unresolvedAssetIDs = unresolvedAssetIDs
    }

    func beginAccountResolution() async -> CloudPhotoAssetAccountResolution {
        let resolution = CloudPhotoAssetAccountResolution()
        activeAuthorization = nil
        activeAccountResolution = resolution
        return resolution
    }

    func activateAccountIdentity(
        _ accountIdentity: String,
        resolution: CloudPhotoAssetAccountResolution
    ) async throws -> CloudPhotoAssetAccountAuthorization {
        guard activeAccountResolution == resolution else {
            throw CancellationError()
        }
        activeAccountResolution = nil
        pendingAssetIDsByAccount[accountIdentity, default: []].formUnion(
            quarantinedAssetIDsByAccountHint.removeValue(forKey: accountIdentity) ?? []
        )
        lastVerifiedAccountIdentity = accountIdentity
        let authorization = CloudPhotoAssetAccountAuthorization(
            accountIdentity: accountIdentity
        )
        activeAuthorization = authorization
        return authorization
    }

    func suspendAccountAuthorization(
        _ authorization: CloudPhotoAssetAccountAuthorization
    ) async {
        guard activeAuthorization == authorization else { return }
        activeAuthorization = nil
    }

    func pendingDeletionIntents(
        forAccountIdentity accountIdentity: String
    ) async throws -> [CloudPhotoAssetDeletionIntentReceipt] {
        try (pendingAssetIDsByAccount[accountIdentity] ?? []).sorted().map {
            assetID in
            guard let intentID = UUID(uuidString: assetID) else {
                throw CloudPhotoAssetContractError.invalidAssetID
            }
            return CloudPhotoAssetDeletionIntentReceipt(
                assetID: assetID,
                accountIdentity: accountIdentity,
                intentID: intentID
            )
        }
    }

    func pendingDeletionAssetIDs(
        forAccountIdentity accountIdentity: String
    ) async throws -> Set<String> {
        pendingAssetIDsByAccount[accountIdentity] ?? []
    }

    func unresolvedDeletionAssetIDs() async throws -> Set<String> {
        quarantinedAssetIDsByAccountHint.values.reduce(unresolvedAssetIDs) {
            $0.union($1)
        }
    }

    func hasCommittedLocalDeletionIntent(assetID: String) async throws -> Bool {
        pendingAssetIDsByAccount.values.contains { $0.contains(assetID) }
            || unresolvedAssetIDs.contains(assetID)
            || quarantinedAssetIDsByAccountHint.values.contains {
                $0.contains(assetID)
            }
    }

    func recordCommittedDeletion(
        assetID: String
    ) async throws -> CloudPhotoAssetDeletionIntentReceipt {
        if let activeAccountIdentity = activeAuthorization?.accountIdentity {
            pendingAssetIDsByAccount[activeAccountIdentity, default: []]
                .insert(assetID)
        } else if let lastVerifiedAccountIdentity {
            quarantinedAssetIDsByAccountHint[lastVerifiedAccountIdentity, default: []]
                .insert(assetID)
        } else {
            unresolvedAssetIDs.insert(assetID)
        }
        return CloudPhotoAssetDeletionIntentReceipt(
            assetID: assetID,
            accountIdentity: activeAuthorization?.accountIdentity,
            quarantineIdentityHint: activeAuthorization == nil
                ? lastVerifiedAccountIdentity
                : nil
        )
    }

    func clearCommittedDeletion(
        _ intent: CloudPhotoAssetDeletionIntentReceipt
    ) async throws {
        if let accountIdentity = intent.accountIdentity {
            pendingAssetIDsByAccount[accountIdentity]?.remove(intent.assetID)
        } else if let accountIdentityHint = intent.quarantineIdentityHint {
            quarantinedAssetIDsByAccountHint[accountIdentityHint]?
                .remove(intent.assetID)
        } else {
            unresolvedAssetIDs.remove(intent.assetID)
        }
    }

    func clearCommittedDeletion(
        assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws {
        pendingAssetIDsByAccount[accountIdentity]?.remove(assetID)
    }
}

private actor CloudPhotoAssetInboundJournalFake:
    CloudPhotoAssetInboundJournaling {
    private var pendingAssetIDs: Set<String> = []

    func pendingInboundAssetIDs() async throws -> Set<String> {
        pendingAssetIDs
    }

    func acquireCleanupLease(
        for assetID: String
    ) async throws -> CloudPhotoAssetInboundCleanupLease? {
        guard !pendingAssetIDs.contains(assetID) else { return nil }
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

private actor CloudPhotoAssetSyncStateStoreFake: CloudPhotoAssetSyncStateStoring {
    private var state: CloudPhotoAssetSyncState
    private(set) var savedStates: [CloudPhotoAssetSyncState] = []

    init(state: CloudPhotoAssetSyncState = .empty) {
        self.state = state
    }

    func load() async throws -> CloudPhotoAssetSyncState { state }

    func save(_ state: CloudPhotoAssetSyncState) async throws {
        self.state = state
        savedStates.append(state)
    }
}

private actor CloudPhotoAssetLocalStoreFake: CloudPhotoAssetLocalStoring {
    struct Snapshot: Sendable {
        let assets: [String: Data]
        let restoredAssets: [String: Data]
        let deletedAssetIDs: [String]
    }

    private var assets: [String: Data]
    private var restoredAssets: [String: Data] = [:]
    private var deletedAssetIDs: [String] = []

    init(assets: [String: Data] = [:]) {
        self.assets = assets
    }

    func storedAssetIDs() async throws -> Set<String> {
        Set(assets.keys)
    }

    func usableCloudAssetIDs() async throws -> Set<String> {
        Set(assets.keys)
    }

    func cloudAssetBytes(id: String) async throws -> Data? {
        assets[id]
    }

    func restoreCloudAsset(id: String, bytes: Data) async throws {
        assets[id] = bytes
        restoredAssets[id] = bytes
    }

    func deleteCloudAsset(id: String) async throws {
        assets.removeValue(forKey: id)
        deletedAssetIDs.append(id)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            assets: assets,
            restoredAssets: restoredAssets,
            deletedAssetIDs: deletedAssetIDs
        )
    }
}

private actor CloudPhotoAssetDatabaseFake: PrivateCloudPhotoAssetDatabase {
    struct SaveRequest: Sendable {
        let request: CloudPhotoAssetUploadRequest
        let zoneName: String
    }

    struct Snapshot: Sendable {
        let ensuredZones: [String]
        let recordRequests: [String]
        let saveRequests: [SaveRequest]
        let deleteRequests: [String]
        let changeTokens: [Data?]
    }

    private let resolvedAccountStatus: CloudPhotoAccountStatus
    private let resolvedAccountIdentity: String
    private var records: [String: CloudPhotoAssetRecordMetadata]
    private var saveResults: [Result<CloudPhotoAssetRecordMetadata, CloudPhotoAssetDatabaseError>]
    private var deleteResults: [Result<Void, CloudPhotoAssetDatabaseError>]
    private var changeResults: [Result<CloudPhotoAssetChangePage, CloudPhotoAssetDatabaseError>]
    private let suspendedSaveCalls: Set<Int>
    private var saveContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var saveWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private let suspendedChangeCalls: Set<Int>
    private var changeContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var changeWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var ensuredZones: [String] = []
    private var recordRequests: [String] = []
    private var saveRequests: [SaveRequest] = []
    private var deleteRequests: [String] = []
    private var changeTokens: [Data?] = []

    init(
        accountStatus: CloudPhotoAccountStatus,
        accountIdentity: String = "opaque-account-a",
        records: [String: CloudPhotoAssetRecordMetadata] = [:],
        saveResults: [
            Result<CloudPhotoAssetRecordMetadata, CloudPhotoAssetDatabaseError>
        ] = [],
        deleteResults: [Result<Void, CloudPhotoAssetDatabaseError>] = [],
        changeResults: [
            Result<CloudPhotoAssetChangePage, CloudPhotoAssetDatabaseError>
        ] = [],
        suspendedSaveCalls: Set<Int> = [],
        suspendedChangeCalls: Set<Int> = []
    ) {
        resolvedAccountStatus = accountStatus
        resolvedAccountIdentity = accountIdentity
        self.records = records
        self.saveResults = saveResults
        self.deleteResults = deleteResults
        self.changeResults = changeResults
        self.suspendedSaveCalls = suspendedSaveCalls
        self.suspendedChangeCalls = suspendedChangeCalls
    }

    func accountStatus() async throws -> CloudPhotoAccountStatus {
        resolvedAccountStatus
    }

    func accountIdentity() async throws -> String {
        resolvedAccountIdentity
    }

    func ensureZone(named zoneName: String) async throws {
        ensuredZones.append(zoneName)
    }

    func record(
        named recordName: String,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata? {
        _ = zoneName
        recordRequests.append(recordName)
        return records[recordName]
    }

    func save(
        _ request: CloudPhotoAssetUploadRequest,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata {
        saveRequests.append(.init(request: request, zoneName: zoneName))
        let call = saveRequests.count
        notifySaveWaiters()
        if suspendedSaveCalls.contains(call) {
            await withCheckedContinuation { continuation in
                saveContinuations[call] = continuation
            }
        }
        guard FileManager.default.fileExists(atPath: request.fileURL.path) else {
            throw CloudPhotoAssetDatabaseError.permanent
        }
        let result: CloudPhotoAssetRecordMetadata
        if saveResults.isEmpty {
            result = try CloudPhotoAssetRecordMetadata(
                recordName: request.recordName,
                assetID: request.assetID,
                checksum: request.checksum,
                byteCount: request.byteCount
            )
        } else {
            result = try saveResults.removeFirst().get()
        }
        records[result.recordName] = result
        return result
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
        records.removeValue(forKey: recordName)
    }

    func fetchChanges(
        inZone zoneName: String,
        previousToken: Data?
    ) async throws -> CloudPhotoAssetChangePage {
        _ = zoneName
        changeTokens.append(previousToken)
        let call = changeTokens.count
        let result = changeResults.isEmpty ? nil : changeResults.removeFirst()
        notifyChangeWaiters()
        if suspendedChangeCalls.contains(call) {
            await withCheckedContinuation { continuation in
                changeContinuations[call] = continuation
            }
        }
        guard let result else {
            return .init(
                changes: [],
                changeToken: previousToken ?? Data([0]),
                moreComing: false
            )
        }
        return try result.get()
    }

    func waitForSaveCall(_ expectedCount: Int) async {
        guard saveRequests.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            saveWaiters.append((expectedCount, continuation))
        }
    }

    func resumeSave(call: Int) {
        saveContinuations.removeValue(forKey: call)?.resume()
    }

    func waitForChangeCall(_ expectedCount: Int) async {
        guard changeTokens.count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            changeWaiters.append((expectedCount, continuation))
        }
    }

    func resumeChange(call: Int) {
        changeContinuations.removeValue(forKey: call)?.resume()
    }

    func snapshot() -> Snapshot {
        Snapshot(
            ensuredZones: ensuredZones,
            recordRequests: recordRequests,
            saveRequests: saveRequests,
            deleteRequests: deleteRequests,
            changeTokens: changeTokens
        )
    }

    private func notifySaveWaiters() {
        let ready = saveWaiters.filter { saveRequests.count >= $0.0 }
        saveWaiters.removeAll { saveRequests.count >= $0.0 }
        for (_, continuation) in ready { continuation.resume() }
    }

    private func notifyChangeWaiters() {
        let ready = changeWaiters.filter { changeTokens.count >= $0.0 }
        changeWaiters.removeAll { changeTokens.count >= $0.0 }
        for (_, continuation) in ready { continuation.resume() }
    }
}
