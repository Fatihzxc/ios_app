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
        let stagedURL = try makeStagedDownload(bytes: downloadedBytes)
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
        let temporaryDirectory = try makeTemporaryDirectory()
        let ownedDirectory = temporaryDirectory.appendingPathComponent(
            "owned",
            isDirectory: true
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: local,
            stateStore: stateStore,
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: ownedDirectory
            )
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
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
        let stagedURL = try makeStagedDownload(bytes: Data([1, 2, 3]))
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
            referencedAssetIDs: [assetID]
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
        let coordinator = try makeCoordinator(
            database: database,
            local: local,
            stateStore: stateStore
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

    func testReferencedMissingAssetRestoresFromCloudWithoutInferringDeletion() async throws {
        let assetID = "00000000-0000-0000-0000-000000000920"
        let bytes = Data([9, 2, 0])
        let stagedURL = try makeStagedDownload(bytes: bytes)
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
            referencedAssetIDs: [assetID]
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

        try await deletionIntents.recordCommittedDeletion(assetID: assetID)
        _ = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let state = try await stateStore.load()
        let pendingIntents = try await deletionIntents.pendingDeletionAssetIDs()

        XCTAssertEqual(
            databaseSnapshot.deleteRequests,
            ["progress-photo-asset-\(assetID)"]
        )
        XCTAssertTrue(state.pendingDeletionAssetIDs.isEmpty)
        XCTAssertTrue(state.uploadedAssetIDs.isEmpty)
        XCTAssertTrue(pendingIntents.isEmpty)
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
        let pendingIntents = try await deletionIntents.pendingDeletionAssetIDs()

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(databaseSnapshot.saveRequests.map(\.request.assetID), [assetID])
        XCTAssertTrue(databaseSnapshot.deleteRequests.isEmpty)
        XCTAssertEqual(databaseSnapshot.changeTokens, [nil])
        XCTAssertEqual(state.accountIdentity, "opaque-account-b")
        XCTAssertEqual(state.uploadedAssetIDs, [assetID])
        XCTAssertTrue(state.pendingDeletionAssetIDs.isEmpty)
        XCTAssertNotEqual(state.changeToken, Data([0xa]))
        XCTAssertTrue(pendingIntents.isEmpty)
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
            pendingAssetIDs: [staleDeletedID]
        )
        let coordinator = CloudPhotoAssetCoordinator(
            database: database,
            localStore: local,
            stateStore: stateStore,
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: [assetID]
            ),
            deletionIntentStore: deletionIntents,
            inboundAssetJournal: CloudPhotoAssetInboundJournalFake(),
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("transfers", isDirectory: true)
            )
        )

        _ = try await coordinator.synchronize()
        let databaseSnapshot = await database.snapshot()
        let recreatedState = try await FileCloudPhotoAssetSyncStateStore(
            fileURL: stateURL
        ).load()
        let remainingIntents = try await deletionIntents.pendingDeletionAssetIDs()

        XCTAssertEqual(databaseSnapshot.saveRequests.map(\.request.assetID), [assetID])
        XCTAssertTrue(databaseSnapshot.deleteRequests.isEmpty)
        XCTAssertEqual(databaseSnapshot.changeTokens, [nil])
        XCTAssertEqual(recreatedState.accountIdentity, "opaque-account-current")
        XCTAssertEqual(recreatedState.uploadedAssetIDs, [assetID])
        XCTAssertTrue(recreatedState.pendingDeletionAssetIDs.isEmpty)
        XCTAssertTrue(remainingIntents.isEmpty)
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

    private func makeCoordinator(
        database: CloudPhotoAssetDatabaseFake,
        local: CloudPhotoAssetLocalStoreFake,
        stateStore: CloudPhotoAssetSyncStateStoreFake,
        referencedAssetIDs: Set<String> = [],
        deletionIntentStore: CloudPhotoAssetDeletionIntentStoreFake = .init(),
        inboundJournal: CloudPhotoAssetInboundJournalFake = .init(),
        retryPolicy: CloudPhotoAssetRetryPolicy = .init(
            maximumAttempts: 1,
            baseDelay: 0,
            maximumDelay: 0
        ),
        sleeper: CloudPhotoAssetSleeperFake = CloudPhotoAssetSleeperFake()
    ) throws -> CloudPhotoAssetCoordinator {
        let directory = try makeTemporaryDirectory()
        return CloudPhotoAssetCoordinator(
            database: database,
            localStore: local,
            stateStore: stateStore,
            referenceSnapshotProvider: CloudPhotoAssetReferenceSnapshotProviderFake(
                referencedAssetIDs: referencedAssetIDs
            ),
            deletionIntentStore: deletionIntentStore,
            inboundAssetJournal: inboundJournal,
            temporaryStore: FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("owned", isDirectory: true)
            ),
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

    private func makeStagedDownload(bytes: Data) throws -> URL {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent("cloudkit-staged.jpg")
        try bytes.write(to: url)
        return url
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

private actor CloudPhotoAssetSleeperFake {
    private(set) var delays: [TimeInterval] = []

    func sleep(_ delay: TimeInterval) async throws {
        delays.append(delay)
    }
}

private actor CloudPhotoAssetReferenceSnapshotProviderFake:
    CloudPhotoAssetReferenceSnapshotProviding {
    private var referencedAssetIDs: Set<String>

    init(referencedAssetIDs: Set<String>) {
        self.referencedAssetIDs = referencedAssetIDs
    }

    func snapshot() async throws -> CloudPhotoAssetReferenceSnapshot {
        CloudPhotoAssetReferenceSnapshot(
            referencedAssetIDs: referencedAssetIDs
        )
    }
}

private actor CloudPhotoAssetDeletionIntentStoreFake:
    CloudPhotoAssetDeletionIntentStoring {
    private var pendingAssetIDs: Set<String>

    init(pendingAssetIDs: Set<String> = []) {
        self.pendingAssetIDs = pendingAssetIDs
    }

    func pendingDeletionAssetIDs() async throws -> Set<String> {
        pendingAssetIDs
    }

    func recordCommittedDeletion(assetID: String) async throws {
        pendingAssetIDs.insert(assetID)
    }

    func clearCommittedDeletion(assetID: String) async throws {
        pendingAssetIDs.remove(assetID)
    }

    func clearAllCommittedDeletions() async throws {
        pendingAssetIDs.removeAll()
    }
}

private actor CloudPhotoAssetInboundJournalFake:
    CloudPhotoAssetInboundJournaling {
    private var pendingAssetIDs: Set<String> = []

    func pendingInboundAssetIDs() async throws -> Set<String> {
        pendingAssetIDs
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
        suspendedSaveCalls: Set<Int> = []
    ) {
        resolvedAccountStatus = accountStatus
        resolvedAccountIdentity = accountIdentity
        self.records = records
        self.saveResults = saveResults
        self.deleteResults = deleteResults
        self.changeResults = changeResults
        self.suspendedSaveCalls = suspendedSaveCalls
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
        guard !changeResults.isEmpty else {
            return .init(
                changes: [],
                changeToken: previousToken ?? Data([0]),
                moreComing: false
            )
        }
        return try changeResults.removeFirst().get()
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
}
