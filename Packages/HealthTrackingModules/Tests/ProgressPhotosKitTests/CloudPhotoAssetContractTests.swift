import Foundation
import ProgressPhotosKit
import XCTest

final class CloudPhotoAssetContractTests: XCTestCase {
    func testRecordContractUsesDeterministicOpaqueNameAndPrivacyAllowlist() throws {
        let assetID = "00000000-0000-0000-0000-000000000901"

        XCTAssertEqual(
            try CloudPhotoAssetRecordContract.recordName(
                for: assetID.uppercased()
            ),
            "progress-photo-asset-\(assetID)"
        )
        XCTAssertEqual(
            Set(CloudPhotoAssetRecordContract.fieldNames),
            Set(["assetID", "asset", "checksum", "byteCount"])
        )
        XCTAssertEqual(
            CloudPhotoAssetRecordContract.zoneName,
            "ProgressPhotoAssetsZone"
        )
        XCTAssertEqual(
            CloudPhotoAssetRecordContract.recordType,
            "ProgressPhotoAsset"
        )

        let serializedContract = CloudPhotoAssetRecordContract.fieldNames.joined(
            separator: " "
        )
        for forbidden in ["date", "pose", "note", "path", "tracker", "health"] {
            XCTAssertFalse(serializedContract.localizedCaseInsensitiveContains(forbidden))
        }
        XCTAssertThrowsError(
            try CloudPhotoAssetRecordContract.recordName(for: "../private/photo.jpg")
        ) { error in
            XCTAssertEqual(
                error as? CloudPhotoAssetContractError,
                .invalidAssetID
            )
        }
    }

    func testChecksumIsStableAndValidationRejectsSizeOrDigestMismatch() throws {
        let bytes = Data("abc".utf8)
        let checksum = CloudPhotoAssetChecksum.sha256Hex(bytes)

        XCTAssertEqual(
            checksum,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertNoThrow(
            try CloudPhotoAssetChecksum.validate(
                bytes,
                expectedChecksum: checksum,
                expectedByteCount: 3,
                maximumBytes: 10
            )
        )
        XCTAssertThrowsError(
            try CloudPhotoAssetChecksum.validate(
                bytes,
                expectedChecksum: checksum,
                expectedByteCount: 2,
                maximumBytes: 10
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudPhotoAssetValidationError,
                .byteCountMismatch(expected: 2, actual: 3)
            )
        }
        XCTAssertThrowsError(
            try CloudPhotoAssetChecksum.validate(
                bytes,
                expectedChecksum: String(repeating: "0", count: 64),
                expectedByteCount: 3,
                maximumBytes: 10
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudPhotoAssetValidationError,
                .checksumMismatch
            )
        }
    }

    func testOpaqueSyncStatePersistsQueuesKnownIDsAndChangeToken() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("cloud-photo-state.json")
        let first = FileCloudPhotoAssetSyncStateStore(fileURL: fileURL)
        let state = CloudPhotoAssetSyncState(
            accountIdentity: "opaque-account-a",
            pendingUploadAssetIDs: [
                "00000000-0000-0000-0000-000000000902",
            ],
            pendingDeletionAssetIDs: [
                "00000000-0000-0000-0000-000000000903",
            ],
            uploadedAssetIDs: [
                "00000000-0000-0000-0000-000000000904",
            ],
            changeToken: Data([9, 0, 4])
        )

        let initialState = try await first.load()
        XCTAssertEqual(initialState, .empty)
        try await first.save(state)

        let recreated = FileCloudPhotoAssetSyncStateStore(fileURL: fileURL)
        let recreatedState = try await recreated.load()
        XCTAssertEqual(recreatedState, state)
        XCTAssertEqual(recreatedState.accountIdentity, "opaque-account-a")
        let persisted = try Data(contentsOf: fileURL)
        let payload = String(decoding: persisted, as: UTF8.self)
        XCTAssertFalse(payload.contains("pose"))
        XCTAssertFalse(payload.contains("note"))
        XCTAssertFalse(payload.contains("file://"))
        XCTAssertFalse(payload.contains("/private/"))
    }

    func testLegacyUnscopedSyncStateRecreatesWithNilAccountIdentity() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("legacy-cloud-photo-state.json")
        let legacyJSON = """
        {"changeToken":"CQ==","pendingDeletionAssetIDs":[],"pendingUploadAssetIDs":[],"uploadedAssetIDs":["00000000-0000-0000-0000-000000000904"]}
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let recreated = FileCloudPhotoAssetSyncStateStore(fileURL: fileURL)
        let state = try await recreated.load()

        XCTAssertNil(state.accountIdentity)
        XCTAssertEqual(
            state.uploadedAssetIDs,
            ["00000000-0000-0000-0000-000000000904"]
        )
        XCTAssertEqual(state.changeToken, Data([9]))
    }

    func testTemporaryStoreOwnsUploadAndDownloadCopiesUntilExplicitCleanup() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("system-staged-download.jpg")
        try Data([4, 5, 6]).write(to: source)
        let ownedDirectory = directory.appendingPathComponent("owned", isDirectory: true)
        let identifiers = DeterministicUUIDSequence([
            UUID(uuidString: "00000000-0000-0000-0000-000000000905")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000906")!,
        ])
        let store = FileCloudPhotoAssetTemporaryStore(
            directory: ownedDirectory,
            makeID: { identifiers.next() }
        )

        let upload = try store.createUploadFile(bytes: Data([1, 2, 3]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: upload.path))
        XCTAssertTrue(upload.path.hasPrefix(ownedDirectory.path))
        let unrelatedAsset = ownedDirectory.appendingPathComponent("keep.asset")
        try Data([7]).write(to: unrelatedAsset)
        XCTAssertThrowsError(try store.readFile(at: source)) { error in
            XCTAssertEqual(
                (error as NSError).code,
                CocoaError.Code.fileReadNoPermission.rawValue
            )
        }
        XCTAssertThrowsError(try store.readFile(at: unrelatedAsset)) { error in
            XCTAssertEqual(
                (error as NSError).code,
                CocoaError.Code.fileReadNoPermission.rawValue
            )
        }
        store.removeFile(at: unrelatedAsset)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedAsset.path))

        let download = try store.copyDownloadedFile(from: source)
        XCTAssertNotEqual(upload, download)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try store.readFile(at: download), Data([4, 5, 6]))

        store.removeFile(at: upload)
        store.removeFile(at: download)
        XCTAssertFalse(FileManager.default.fileExists(atPath: upload.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: download.path))
    }

    func testAdapterStagesDownloadIntoOwnedStorageBeforeSystemSourceDisappears() throws {
        let assetID = "00000000-0000-0000-0000-000000000907"
        let bytes = Data([4, 5, 6, 7])
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("cloudkit-system-owned.asset")
        try bytes.write(to: source)
        let ownedDirectory = directory.appendingPathComponent("owned", isDirectory: true)
        let store = FileCloudPhotoAssetTemporaryStore(directory: ownedDirectory)

        let record = try store.stageDownload(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            systemFileURL: source,
            maximumBytes: 16
        )
        try FileManager.default.removeItem(at: source)

        XCTAssertTrue(record.stagedFileURL.path.hasPrefix(ownedDirectory.path + "/"))
        XCTAssertEqual(try store.readFile(at: record.stagedFileURL), bytes)
    }

    func testDownloadStagingRejectsOversizedMetadataBeforeOpeningSource() throws {
        let assetID = "00000000-0000-0000-0000-000000000908"
        let directory = try makeTemporaryDirectory()
        let missingSource = directory.appendingPathComponent("already-reclaimed.asset")
        let ownedDirectory = directory.appendingPathComponent("owned", isDirectory: true)
        let store = FileCloudPhotoAssetTemporaryStore(directory: ownedDirectory)

        XCTAssertThrowsError(
            try store.stageDownload(
                recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
                assetID: assetID,
                checksum: String(repeating: "0", count: 64),
                byteCount: 5,
                systemFileURL: missingSource,
                maximumBytes: 4
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudPhotoAssetValidationError,
                .exceedsMaximumBytes(maximumBytes: 4)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownedDirectory.path))
    }

    func testDownloadStagingBoundsActualBytesAndRejectsMetadataMismatch() throws {
        let assetID = "00000000-0000-0000-0000-000000000909"
        let directory = try makeTemporaryDirectory()
        let ownedDirectory = directory.appendingPathComponent("owned", isDirectory: true)
        let store = FileCloudPhotoAssetTemporaryStore(directory: ownedDirectory)

        let oversizedSource = directory.appendingPathComponent("oversized.asset")
        try Data([1, 2, 3, 4, 5]).write(to: oversizedSource)
        XCTAssertThrowsError(
            try store.stageDownload(
                recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
                assetID: assetID,
                checksum: CloudPhotoAssetChecksum.sha256Hex(Data([1, 2, 3, 4])),
                byteCount: 4,
                systemFileURL: oversizedSource,
                maximumBytes: 4
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudPhotoAssetValidationError,
                .exceedsMaximumBytes(maximumBytes: 4)
            )
        }

        let mismatchedSource = directory.appendingPathComponent("mismatched.asset")
        try Data([1, 2, 3]).write(to: mismatchedSource)
        XCTAssertThrowsError(
            try store.stageDownload(
                recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
                assetID: assetID,
                checksum: CloudPhotoAssetChecksum.sha256Hex(Data([1, 2])),
                byteCount: 2,
                systemFileURL: mismatchedSource,
                maximumBytes: 4
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudPhotoAssetValidationError,
                .byteCountMismatch(expected: 2, actual: 3)
            )
        }

        let ownedFiles = (try? FileManager.default.contentsOfDirectory(
            at: ownedDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(ownedFiles.isEmpty)
    }

    func testRealBoundedStagerLimitsReadRequestsAndNeverWritesMaximumPlusOneByte() throws {
        let assetID = "00000000-0000-0000-0000-00000000090a"
        let directory = try makeTemporaryDirectory()
        let ownedDirectory = directory.appendingPathComponent("owned", isDirectory: true)
        let sourceURL = directory.appendingPathComponent("system.asset")
        let handles = CloudPhotoAssetFileHandleProbe(
            sourceBytes: Data([1, 2, 3, 4, 5]),
            maximumReadChunkSize: 2
        )
        let store = FileCloudPhotoAssetTemporaryStore(
            directory: ownedDirectory,
            fileHandleFactory: handles
        )

        XCTAssertThrowsError(
            try store.stageDownload(
                recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
                assetID: assetID,
                checksum: String(repeating: "0", count: 64),
                byteCount: 4,
                systemFileURL: sourceURL,
                maximumBytes: 4
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudPhotoAssetValidationError,
                .exceedsMaximumBytes(maximumBytes: 4)
            )
        }
        let snapshot = handles.snapshot()
        XCTAssertEqual(snapshot.sourceURLs, [sourceURL])
        XCTAssertEqual(snapshot.readRequests, [5, 3, 1])
        XCTAssertTrue(snapshot.readRequests.allSatisfy { $0 <= 5 })
        XCTAssertEqual(snapshot.destinationBytes, Data([1, 2, 3, 4]))
        XCTAssertEqual(snapshot.destinationBytes.count, 4)
        XCTAssertEqual(snapshot.destinationURLs.count, 1)
        XCTAssertTrue(
            snapshot.destinationURLs[0].path.hasPrefix(ownedDirectory.path + "/")
        )
        let ownedFiles = (try? FileManager.default.contentsOfDirectory(
            at: ownedDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(ownedFiles.isEmpty)
    }

    func testDownloadStagingDeletesOutputAndClosesReaderWhenWriterCloseFails() throws {
        let assetID = "00000000-0000-0000-0000-00000000090b"
        let bytes = Data([1, 2, 3])
        let directory = try makeTemporaryDirectory()
        let ownedDirectory = directory.appendingPathComponent("owned", isDirectory: true)
        let handles = CloudPhotoAssetFileHandleProbe(
            sourceBytes: bytes,
            maximumReadChunkSize: 2,
            failWriterClose: true
        )
        let store = FileCloudPhotoAssetTemporaryStore(
            directory: ownedDirectory,
            fileHandleFactory: handles
        )

        XCTAssertThrowsError(
            try store.stageDownload(
                recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
                assetID: assetID,
                checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
                byteCount: bytes.count,
                systemFileURL: directory.appendingPathComponent("system.asset"),
                maximumBytes: 4
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudPhotoAssetFileHandleProbeError,
                .writerClose
            )
        }
        let snapshot = handles.snapshot()
        let ownedFiles = (try? FileManager.default.contentsOfDirectory(
            at: ownedDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        XCTAssertEqual(snapshot.closeCallCount, 2)
        XCTAssertTrue(ownedFiles.isEmpty)
    }

    func testTemporaryStoreRecreationSweepsStaleTransferFiles() throws {
        let directory = try makeTemporaryDirectory()
        let ownedDirectory = directory.appendingPathComponent("owned", isDirectory: true)
        try FileManager.default.createDirectory(
            at: ownedDirectory,
            withIntermediateDirectories: true
        )
        let stale = ownedDirectory.appendingPathComponent(
            "00000000-0000-0000-0000-000000000910.asset"
        )
        let unrelated = ownedDirectory.appendingPathComponent("keep.txt")
        let unrelatedAsset = ownedDirectory.appendingPathComponent("keep.asset")
        let unrelatedDirectory = ownedDirectory.appendingPathComponent(
            "keep-directory.asset",
            isDirectory: true
        )
        let nestedUnrelated = unrelatedDirectory.appendingPathComponent(
            "00000000-0000-0000-0000-000000000911.asset"
        )
        let symlinkTarget = directory.appendingPathComponent("symlink-target.asset")
        let symlink = ownedDirectory.appendingPathComponent(
            "00000000-0000-0000-0000-000000000912.asset"
        )
        try FileManager.default.createDirectory(
            at: unrelatedDirectory,
            withIntermediateDirectories: true
        )
        try Data([1]).write(to: stale)
        try Data([2]).write(to: unrelated)
        try Data([3]).write(to: unrelatedAsset)
        try Data([3]).write(to: nestedUnrelated)
        try Data([4]).write(to: symlinkTarget)
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL: symlinkTarget
        )

        _ = FileCloudPhotoAssetTemporaryStore(directory: ownedDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedAsset.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedUnrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlink.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkTarget.path))
    }

    func testDeletionIntentStoreSerializesAccountTransitionAndPersistsEveryScope() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("cloud-deletions.json")
        let accountA = "opaque-account-a"
        let accountB = "opaque-account-b"
        let assetA = "00000000-0000-0000-0000-000000000933"
        let racedAsset = "00000000-0000-0000-0000-000000000934"
        let assetB = "00000000-0000-0000-0000-000000000935"
        let unresolvedAsset = "00000000-0000-0000-0000-000000000936"
        let store = FileCloudPhotoAssetDeletionIntentStore(fileURL: fileURL)

        let accountAResolution = await store.beginAccountResolution()
        _ = try await store.activateAccountIdentity(
            accountA,
            resolution: accountAResolution
        )
        let accountAReceipt = try await store.recordCommittedDeletion(assetID: assetA)
        let accountBResolution = await store.beginAccountResolution()
        async let transition: CloudPhotoAssetAccountAuthorization = store
            .activateAccountIdentity(accountB, resolution: accountBResolution)
        async let racedReceipt = store.recordCommittedDeletion(assetID: racedAsset)
        let (_, serializedRaceReceipt) = try await (transition, racedReceipt)
        let accountBReceipt = try await store.recordCommittedDeletion(assetID: assetB)
        let racedAccountIdentity = try XCTUnwrap(
            serializedRaceReceipt.accountIdentity
                ?? serializedRaceReceipt.quarantineIdentityHint
        )

        XCTAssertEqual(accountAReceipt.accountIdentity, accountA)
        XCTAssertTrue(
            [accountA, accountB].contains(racedAccountIdentity),
            "The actor must serialize a racing record entirely before or after transition."
        )
        XCTAssertEqual(accountBReceipt.accountIdentity, accountB)

        let recreatedBeforeResolution = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: fileURL
        )
        let unresolvedReceipt = try await recreatedBeforeResolution
            .recordCommittedDeletion(assetID: unresolvedAsset)
        XCTAssertNil(unresolvedReceipt.accountIdentity)
        let recreatedBResolution = await recreatedBeforeResolution
            .beginAccountResolution()
        _ = try await recreatedBeforeResolution.activateAccountIdentity(
            accountB,
            resolution: recreatedBResolution
        )

        let accountAIDs = try await recreatedBeforeResolution
            .pendingDeletionAssetIDs(forAccountIdentity: accountA)
        let accountBIDs = try await recreatedBeforeResolution
            .pendingDeletionAssetIDs(forAccountIdentity: accountB)
        let unresolvedIDs = try await recreatedBeforeResolution
            .unresolvedDeletionAssetIDs()
        let durableUnion = accountAIDs.union(accountBIDs).union(unresolvedIDs)

        XCTAssertEqual(durableUnion, [assetA, racedAsset, assetB, unresolvedAsset])
        XCTAssertTrue(accountAIDs.contains(assetA))
        XCTAssertTrue(accountBIDs.contains(assetB))
        XCTAssertTrue(accountBIDs.contains(unresolvedAsset))
        if serializedRaceReceipt.accountIdentity == accountB {
            XCTAssertTrue(accountBIDs.contains(racedAsset))
        } else {
            XCTAssertEqual(serializedRaceReceipt.quarantineIdentityHint, accountA)
            XCTAssertTrue(unresolvedIDs.contains(racedAsset))
        }

        try await recreatedBeforeResolution.clearCommittedDeletion(
            assetID: assetB,
            forAccountIdentity: accountB
        )
        let finalStore = FileCloudPhotoAssetDeletionIntentStore(fileURL: fileURL)
        let finalAccountAIDs = try await finalStore.pendingDeletionAssetIDs(
            forAccountIdentity: accountA
        )
        let finalAccountBIDs = try await finalStore.pendingDeletionAssetIDs(
            forAccountIdentity: accountB
        )
        let finalUnresolvedIDs = try await finalStore.unresolvedDeletionAssetIDs()

        XCTAssertEqual(finalAccountAIDs, accountAIDs)
        XCTAssertEqual(finalAccountBIDs, accountBIDs.subtracting([assetB]))
        XCTAssertEqual(finalUnresolvedIDs, unresolvedIDs)
    }

    func testLegacyDeletionIntentSetMovesToQuarantineWithoutAuthorizingCurrentAccount() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("legacy-cloud-deletions.json")
        let legacyAssetID = "00000000-0000-0000-0000-000000000937"
        try JSONEncoder().encode([legacyAssetID]).write(to: fileURL)
        let store = FileCloudPhotoAssetDeletionIntentStore(fileURL: fileURL)

        let resolution = await store.beginAccountResolution()
        _ = try await store.activateAccountIdentity(
            "opaque-account-current",
            resolution: resolution
        )
        let currentIDs = try await store.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-current"
        )
        let quarantinedIDs = try await store.unresolvedDeletionAssetIDs()

        XCTAssertTrue(currentIDs.isEmpty)
        XCTAssertEqual(quarantinedIDs, [legacyAssetID])
        let migratedJSON = String(
            decoding: try Data(contentsOf: fileURL),
            as: UTF8.self
        )
        XCTAssertTrue(migratedJSON.contains("intents"))
        XCTAssertTrue(migratedJSON.contains("intentID"))
    }

    func testDeletionIntentStoreRecreationPromotesOnlyMatchingVerifiedAccountHint() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("scoped-cloud-deletions.json")
        let accountA = "opaque-account-a"
        let accountB = "opaque-account-b"
        let offlineAssetID = "00000000-0000-0000-0000-00000000093b"
        let first = FileCloudPhotoAssetDeletionIntentStore(fileURL: fileURL)

        let resolutionA = await first.beginAccountResolution()
        let authorizationA = try await first.activateAccountIdentity(
            accountA,
            resolution: resolutionA
        )
        await first.suspendAccountAuthorization(authorizationA)
        let recreatedOffline = FileCloudPhotoAssetDeletionIntentStore(fileURL: fileURL)
        let offlineReceipt = try await recreatedOffline.recordCommittedDeletion(
            assetID: offlineAssetID
        )

        XCTAssertNil(offlineReceipt.accountIdentity)
        XCTAssertEqual(offlineReceipt.quarantineIdentityHint, accountA)

        let resolutionB = await recreatedOffline.beginAccountResolution()
        let authorizationB = try await recreatedOffline.activateAccountIdentity(
            accountB,
            resolution: resolutionB
        )
        let accountBIDs = try await recreatedOffline.pendingDeletionAssetIDs(
            forAccountIdentity: accountB
        )
        let quarantinedUnderB = try await recreatedOffline.unresolvedDeletionAssetIDs()
        XCTAssertTrue(accountBIDs.isEmpty)
        XCTAssertEqual(quarantinedUnderB, [offlineAssetID])
        await recreatedOffline.suspendAccountAuthorization(authorizationB)

        let recreatedForA = FileCloudPhotoAssetDeletionIntentStore(fileURL: fileURL)
        let secondResolutionA = await recreatedForA.beginAccountResolution()
        let secondAuthorizationA = try await recreatedForA.activateAccountIdentity(
            accountA,
            resolution: secondResolutionA
        )
        let promotedAIDs = try await recreatedForA.pendingDeletionAssetIDs(
            forAccountIdentity: accountA
        )
        let quarantineAfterA = try await recreatedForA.unresolvedDeletionAssetIDs()
        await recreatedForA.suspendAccountAuthorization(secondAuthorizationA)

        XCTAssertEqual(promotedAIDs, [offlineAssetID])
        XCTAssertTrue(quarantineAfterA.isEmpty)
        let persistedJSON = String(
            decoding: try Data(contentsOf: fileURL),
            as: UTF8.self
        )
        XCTAssertTrue(persistedJSON.contains("lastVerifiedAccountIdentity"))
        XCTAssertTrue(persistedJSON.contains("intents"))
        XCTAssertTrue(persistedJSON.contains("intentID"))
    }

    func testExactIntentReceiptSurvivesPromotionAndDoesNotClearSameAssetABA() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("exact-cloud-deletions.json")
        let accountA = "opaque-account-a"
        let assetID = "00000000-0000-0000-0000-000000000942"
        let first = FileCloudPhotoAssetDeletionIntentStore(fileURL: fileURL)
        let initialResolution = await first.beginAccountResolution()
        let initialAuthorization = try await first.activateAccountIdentity(
            accountA,
            resolution: initialResolution
        )
        await first.suspendAccountAuthorization(initialAuthorization)
        let receipt1 = try await first.recordCommittedDeletion(assetID: assetID)

        let recreated = FileCloudPhotoAssetDeletionIntentStore(fileURL: fileURL)
        let promotionResolution = await recreated.beginAccountResolution()
        let promotedAuthorization = try await recreated.activateAccountIdentity(
            accountA,
            resolution: promotionResolution
        )
        let receipt2 = try await recreated.recordCommittedDeletion(assetID: assetID)
        let persistedBeforeClear = String(
            decoding: try Data(contentsOf: fileURL),
            as: UTF8.self
        )
        let pendingBeforeClear = try await recreated.pendingDeletionAssetIDs(
            forAccountIdentity: accountA
        )

        XCTAssertNotEqual(receipt1.intentID, receipt2.intentID)
        XCTAssertTrue(persistedBeforeClear.contains(receipt1.intentID.uuidString))
        XCTAssertTrue(persistedBeforeClear.contains(receipt2.intentID.uuidString))
        XCTAssertEqual(pendingBeforeClear, [assetID])

        try await recreated.clearCommittedDeletion(receipt1)
        let pendingAfterFirstClear = try await recreated.pendingDeletionAssetIDs(
            forAccountIdentity: accountA
        )
        XCTAssertEqual(
            pendingAfterFirstClear,
            [assetID],
            "Clearing promoted intent1 must retain newer same-asset intent2."
        )

        try await recreated.clearCommittedDeletion(receipt2)
        let pendingAfterSecondClear = try await recreated.pendingDeletionAssetIDs(
            forAccountIdentity: accountA
        )
        await recreated.suspendAccountAuthorization(promotedAuthorization)
        XCTAssertTrue(pendingAfterSecondClear.isEmpty)
    }

    func testStaleAccountResolutionCannotAuthorizeAfterNewerEpochBegins() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FileCloudPhotoAssetDeletionIntentStore(
            fileURL: directory.appendingPathComponent("resolution-cloud-deletions.json")
        )
        let accountA = "opaque-account-a"
        let accountB = "opaque-account-b"
        let assetID = "00000000-0000-0000-0000-000000000943"
        let reuseAssetID = "00000000-0000-0000-0000-000000000944"
        let initialResolution = await store.beginAccountResolution()
        let initialAuthorization = try await store.activateAccountIdentity(
            accountA,
            resolution: initialResolution
        )
        await store.suspendAccountAuthorization(initialAuthorization)

        let staleResolution = await store.beginAccountResolution()
        let newerResolution = await store.beginAccountResolution()
        do {
            _ = try await store.activateAccountIdentity(
                accountA,
                resolution: staleResolution
            )
            XCTFail("An older resolution epoch must never reopen account A.")
        } catch is CancellationError {
            // Expected stale compare-and-swap rejection.
        }

        let staleReceipt = try await store.recordCommittedDeletion(assetID: assetID)
        let accountAAfterStaleActivation = try await store.pendingDeletionAssetIDs(
            forAccountIdentity: accountA
        )
        let quarantineAfterStaleActivation = try await store
            .unresolvedDeletionAssetIDs()
        XCTAssertNil(staleReceipt.accountIdentity)
        XCTAssertEqual(staleReceipt.quarantineIdentityHint, accountA)
        XCTAssertTrue(accountAAfterStaleActivation.isEmpty)
        XCTAssertEqual(quarantineAfterStaleActivation, [assetID])

        let accountBAuthorization = try await store.activateAccountIdentity(
            accountB,
            resolution: newerResolution
        )
        do {
            _ = try await store.activateAccountIdentity(
                accountA,
                resolution: newerResolution
            )
            XCTFail("A consumed resolution epoch must never authorize a second account.")
        } catch is CancellationError {
            // Expected single-use compare-and-swap rejection.
        }
        let receiptAfterResolutionReuse = try await store.recordCommittedDeletion(
            assetID: reuseAssetID
        )
        let accountBAfterActivation = try await store.pendingDeletionAssetIDs(
            forAccountIdentity: accountB
        )
        let quarantineUnderB = try await store.unresolvedDeletionAssetIDs()
        XCTAssertEqual(accountBAfterActivation, [reuseAssetID])
        XCTAssertEqual(quarantineUnderB, [assetID])
        XCTAssertEqual(receiptAfterResolutionReuse.accountIdentity, accountB)
        await store.suspendAccountAuthorization(accountBAuthorization)

        let returningAResolution = await store.beginAccountResolution()
        let returningAAuthorization = try await store.activateAccountIdentity(
            accountA,
            resolution: returningAResolution
        )
        let promotedOnlyUnderA = try await store.pendingDeletionAssetIDs(
            forAccountIdentity: accountA
        )
        let finalQuarantine = try await store.unresolvedDeletionAssetIDs()
        await store.suspendAccountAuthorization(returningAAuthorization)
        XCTAssertEqual(promotedOnlyUnderA, [assetID])
        XCTAssertTrue(finalQuarantine.isEmpty)
    }

    func testDeletionIntentStoreMigratesV1AndRejectsUnknownSchemaFailClosed() async throws {
        let directory = try makeTemporaryDirectory()
        let migratedURL = directory.appendingPathComponent("v1-cloud-deletions.json")
        let accountAssetID = "00000000-0000-0000-0000-00000000093c"
        let legacyUnscopedID = "00000000-0000-0000-0000-00000000093d"
        let v1JSON = """
        {"schemaVersion":1,"accountAssetIDs":{"opaque-account-a":["\(accountAssetID)"]},"unresolvedAssetIDs":["\(legacyUnscopedID)"]}
        """
        try Data(v1JSON.utf8).write(to: migratedURL)
        let migrated = FileCloudPhotoAssetDeletionIntentStore(fileURL: migratedURL)

        let migrationResolution = await migrated.beginAccountResolution()
        let authorization = try await migrated.activateAccountIdentity(
            "opaque-account-a",
            resolution: migrationResolution
        )
        let accountIDs = try await migrated.pendingDeletionAssetIDs(
            forAccountIdentity: "opaque-account-a"
        )
        let quarantine = try await migrated.unresolvedDeletionAssetIDs()
        await migrated.suspendAccountAuthorization(authorization)

        XCTAssertEqual(accountIDs, [accountAssetID])
        XCTAssertEqual(
            quarantine,
            [legacyUnscopedID],
            "Legacy nil provenance must never auto-promote into an account scope."
        )

        let corruptURL = directory.appendingPathComponent("unknown-schema.json")
        let corruptBytes = Data(
            "{\"schemaVersion\":99,\"accountAssetIDs\":{},\"quarantinedIntents\":[]}".utf8
        )
        try corruptBytes.write(to: corruptURL)
        let corrupt = FileCloudPhotoAssetDeletionIntentStore(fileURL: corruptURL)
        let corruptResolution = await corrupt.beginAccountResolution()
        do {
            _ = try await corrupt.activateAccountIdentity(
                "opaque-account-a",
                resolution: corruptResolution
            )
            XCTFail("Unknown deletion-intent schema must not activate any account.")
        } catch {
            XCTAssertEqual(
                error as? CloudPhotoAssetContractError,
                .invalidAssetID
            )
        }
        XCTAssertEqual(try Data(contentsOf: corruptURL), corruptBytes)
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

private final class DeterministicUUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [UUID]

    init(_ identifiers: [UUID]) {
        precondition(!identifiers.isEmpty)
        self.identifiers = identifiers
    }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        precondition(!identifiers.isEmpty)
        return identifiers.removeFirst()
    }
}

private final class CloudPhotoAssetFileHandleProbe:
    CloudPhotoAssetFileHandleOpening,
    CloudPhotoAssetReadHandling,
    CloudPhotoAssetWriteHandling,
    @unchecked Sendable {
    struct Snapshot {
        let sourceURLs: [URL]
        let destinationURLs: [URL]
        let readRequests: [Int]
        let destinationBytes: Data
        let closeCallCount: Int
    }

    private let lock = NSLock()
    private let sourceBytes: Data
    private let maximumReadChunkSize: Int
    private let failWriterClose: Bool
    private var offset = 0
    private var sourceURLs: [URL] = []
    private var destinationURLs: [URL] = []
    private var readRequests: [Int] = []
    private var destinationBytes = Data()
    private var closeCallCount = 0

    init(
        sourceBytes: Data,
        maximumReadChunkSize: Int,
        failWriterClose: Bool = false
    ) {
        precondition(maximumReadChunkSize > 0)
        self.sourceBytes = sourceBytes
        self.maximumReadChunkSize = maximumReadChunkSize
        self.failWriterClose = failWriterClose
    }

    func openForReading(
        at sourceURL: URL
    ) throws -> any CloudPhotoAssetReadHandling {
        lock.lock()
        sourceURLs.append(sourceURL)
        lock.unlock()
        return self
    }

    func openForWriting(
        at destinationURL: URL
    ) throws -> any CloudPhotoAssetWriteHandling {
        lock.lock()
        destinationURLs.append(destinationURL)
        lock.unlock()
        return self
    }

    func read(upToCount count: Int) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        readRequests.append(count)
        guard offset < sourceBytes.count else { return Data() }
        let byteCount = min(
            count,
            maximumReadChunkSize,
            sourceBytes.count - offset
        )
        let upperBound = offset + byteCount
        let chunk = sourceBytes[offset..<upperBound]
        offset = upperBound
        return Data(chunk)
    }

    func write(contentsOf data: Data) throws {
        lock.lock()
        destinationBytes.append(data)
        lock.unlock()
    }

    func close() throws {
        lock.lock()
        closeCallCount += 1
        let mustFail = failWriterClose && closeCallCount == 1
        lock.unlock()
        if mustFail {
            throw CloudPhotoAssetFileHandleProbeError.writerClose
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            sourceURLs: sourceURLs,
            destinationURLs: destinationURLs,
            readRequests: readRequests,
            destinationBytes: destinationBytes,
            closeCallCount: closeCallCount
        )
    }
}

private enum CloudPhotoAssetFileHandleProbeError: Error, Equatable {
    case writerClose
}
