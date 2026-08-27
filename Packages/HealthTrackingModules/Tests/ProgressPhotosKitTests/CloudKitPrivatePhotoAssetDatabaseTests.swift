@testable import ProgressPhotosKit
@preconcurrency import CloudKit
import Foundation
import XCTest

@MainActor
final class CloudKitPrivatePhotoAssetDatabaseTests: XCTestCase {
    func testActualAdapterOwnsDownloadBeforeSystemURLDisappearsAtReturnBoundary() async throws {
        let assetID = "00000000-0000-0000-0000-000000000930"
        let bytes = Data([9, 3, 0])
        let directory = try makeTemporaryDirectory()
        let systemURL = directory.appendingPathComponent("cloudkit-system.asset")
        try bytes.write(to: systemURL)
        let transferDirectory = directory.appendingPathComponent(
            "owned-transfers",
            isDirectory: true
        )
        var lifetimeOwner: CloudPhotoAssetSystemURLLifetimeOwner? = .init(
            fileURL: systemURL
        )
        let systemDatabase = CloudPhotoAssetSystemDatabaseFake(
            page: CloudPhotoAssetSystemChangePage(
                changes: [
                    .changed(
                        try CloudPhotoAssetSystemDownloadRecord(
                            recordName: CloudPhotoAssetRecordContract.recordName(
                                for: assetID
                            ),
                            assetID: assetID,
                            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
                            byteCount: bytes.count,
                            systemFileURL: systemURL,
                            lifetimeOwner: try XCTUnwrap(lifetimeOwner)
                        )
                    ),
                ],
                changeToken: Data([9, 3]),
                moreComing: false
            )
        )
        let store = FileCloudPhotoAssetTemporaryStore(directory: transferDirectory)
        let adapter = CloudKitPrivatePhotoAssetDatabase(
            containerIdentifier: nil,
            systemDatabase: systemDatabase,
            accountIdentityProvider: CloudPhotoAccountIdentityProviderFake(
                identities: ["opaque-account-a"]
            ),
            downloadStore: store,
            maximumAssetBytes: 8
        )
        lifetimeOwner = nil

        let page = try await adapter.fetchChanges(
            inZone: CloudPhotoAssetRecordContract.zoneName,
            previousToken: nil
        )
        let changed = try XCTUnwrap(page.changes.first)
        guard case let .changed(record) = changed else {
            return XCTFail("Expected one changed cloud asset record.")
        }

        XCTAssertNotEqual(record.stagedFileURL, systemURL)
        XCTAssertTrue(
            record.stagedFileURL.path.hasPrefix(transferDirectory.path + "/")
        )
        XCTAssertEqual(try store.readFile(at: record.stagedFileURL), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: systemURL.path))
    }

    func testActualAdapterReturnsChangingOpaqueAccountIdentity() async throws {
        let identityProvider = CloudPhotoAccountIdentityProviderFake(
            identities: ["opaque-account-a", "opaque-account-b"]
        )
        let adapter = CloudKitPrivatePhotoAssetDatabase(
            containerIdentifier: nil,
            systemDatabase: CloudPhotoAssetSystemDatabaseFake(
                page: .init(changes: [], changeToken: Data([0]), moreComing: false)
            ),
            accountIdentityProvider: identityProvider,
            downloadStore: FileCloudPhotoAssetTemporaryStore(
                directory: try makeTemporaryDirectory()
            ),
            maximumAssetBytes: 8
        )

        let first = try await adapter.accountIdentity()
        let second = try await adapter.accountIdentity()

        XCTAssertEqual(first, "opaque-account-a")
        XCTAssertEqual(second, "opaque-account-b")
        XCTAssertNotEqual(first, second)
    }

    func testActualAdapterAndCoordinatorConsumeAndRemoveOneSharedOwnedTransfer() async throws {
        let assetID = "00000000-0000-0000-0000-000000000931"
        let bytes = Data([9, 3, 1])
        let directory = try makeTemporaryDirectory()
        let systemURL = directory.appendingPathComponent("cloudkit-system.asset")
        try bytes.write(to: systemURL)
        let transferDirectory = directory.appendingPathComponent(
            "owned-transfers",
            isDirectory: true
        )
        let transferStore = FileCloudPhotoAssetTemporaryStore(
            directory: transferDirectory
        )
        let systemDatabase = CloudPhotoAssetSystemDatabaseFake(
            page: CloudPhotoAssetSystemChangePage(
                changes: [
                    .changed(
                        try CloudPhotoAssetSystemDownloadRecord(
                            recordName: "progress-photo-asset-\(assetID)",
                            assetID: assetID,
                            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
                            byteCount: 3,
                            systemFileURL: systemURL
                        )
                    ),
                ],
                changeToken: Data([9, 3, 1]),
                moreComing: false
            )
        )
        let adapter = CloudKitPrivatePhotoAssetDatabase(
            containerIdentifier: nil,
            systemDatabase: systemDatabase,
            accountIdentityProvider: CloudPhotoAccountIdentityProviderFake(
                identities: ["opaque-account-a"]
            ),
            downloadStore: transferStore,
            maximumAssetBytes: 8
        )
        let localStore = CloudPhotoAssetIntegrationLocalStoreFake()
        let inboundJournal = CloudPhotoAssetIntegrationInboundJournalFake()
        let coordinator = CloudPhotoAssetCoordinator(
            database: adapter,
            localStore: localStore,
            stateStore: FileCloudPhotoAssetSyncStateStore(
                fileURL: directory.appendingPathComponent("state.json")
            ),
            referenceSnapshotProvider: CloudPhotoAssetIntegrationReferenceProviderFake(),
            deletionIntentStore: CloudPhotoAssetIntegrationDeletionIntentStoreFake(),
            inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                inboundAssetJournal: inboundJournal,
                localStore: localStore
            ),
            temporaryStore: transferStore,
            maximumAssetBytes: 8
        )

        let outcome = try await coordinator.synchronize()
        let restoredBytes = await localStore.bytes(for: assetID)
        let pendingInbound = try await inboundJournal.pendingInboundAssetIDs()
        let ownedTransfers = (try? FileManager.default.contentsOfDirectory(
            at: transferDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(restoredBytes, bytes)
        XCTAssertEqual(pendingInbound, [assetID])
        XCTAssertTrue(ownedTransfers.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: systemURL.path))
    }

    func testActualAdapterRepairsMatchingMetadataWithoutUsableBinaryAndKeepsValidAssetIdempotent() async throws {
        func synchronize(
            assetID: String,
            bytes: Data,
            hasUsableBinaryAsset: Bool
        ) async throws -> CloudPhotoAssetSystemDatabaseFake.Snapshot {
            let directory = try makeTemporaryDirectory()
            let metadata = try CloudPhotoAssetRecordMetadata(
                recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
                assetID: assetID,
                checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
                byteCount: bytes.count
            )
            let systemDatabase = CloudPhotoAssetSystemDatabaseFake(
                page: .init(changes: [], changeToken: Data([9, 3, 2]), moreComing: false),
                recordResult: CloudPhotoAssetSystemRecord(
                    metadata: metadata,
                    hasUsableBinaryAsset: hasUsableBinaryAsset
                )
            )
            let transferStore = FileCloudPhotoAssetTemporaryStore(
                directory: directory.appendingPathComponent("transfers", isDirectory: true)
            )
            let adapter = CloudKitPrivatePhotoAssetDatabase(
                containerIdentifier: nil,
                systemDatabase: systemDatabase,
                accountIdentityProvider: CloudPhotoAccountIdentityProviderFake(
                    identities: ["opaque-account-a"]
                ),
                downloadStore: transferStore,
                maximumAssetBytes: 8
            )
            let localStore = CloudPhotoAssetIntegrationLocalStoreFake(
                assets: [assetID: bytes]
            )
            let inboundJournal = CloudPhotoAssetIntegrationInboundJournalFake()
            let coordinator = CloudPhotoAssetCoordinator(
                database: adapter,
                localStore: localStore,
                stateStore: FileCloudPhotoAssetSyncStateStore(
                    fileURL: directory.appendingPathComponent("state.json")
                ),
                referenceSnapshotProvider: CloudPhotoAssetIntegrationReferenceProviderFake(
                    referencedAssetIDs: [assetID]
                ),
                deletionIntentStore: CloudPhotoAssetIntegrationDeletionIntentStoreFake(),
                inboundAssetApplier: DirectCloudPhotoAssetInboundApplier(
                    inboundAssetJournal: inboundJournal,
                    localStore: localStore
                ),
                temporaryStore: transferStore,
                maximumAssetBytes: 8
            )

            let outcome = try await coordinator.synchronize()
            XCTAssertEqual(outcome, .synchronized)
            return await systemDatabase.snapshot()
        }

        let missingBinaryAssetID = "00000000-0000-0000-0000-000000000932"
        let validBinaryAssetID = "00000000-0000-0000-0000-000000000933"
        let missingBinary = try await synchronize(
            assetID: missingBinaryAssetID,
            bytes: Data([9, 3, 2]),
            hasUsableBinaryAsset: false
        )
        let validBinary = try await synchronize(
            assetID: validBinaryAssetID,
            bytes: Data([9, 3, 3]),
            hasUsableBinaryAsset: true
        )

        XCTAssertEqual(
            missingBinary.recordRequests,
            ["progress-photo-asset-\(missingBinaryAssetID)"]
        )
        XCTAssertEqual(
            missingBinary.saveRequests.map(\.assetID),
            [missingBinaryAssetID],
            "Matching metadata cannot suppress repair when CKAsset bytes are unavailable."
        )
        XCTAssertEqual(
            validBinary.recordRequests,
            ["progress-photo-asset-\(validBinaryAssetID)"]
        )
        XCTAssertTrue(
            validBinary.saveRequests.isEmpty,
            "Matching metadata with a usable binary remains idempotent."
        )
    }

    func testActualCKRecordMappingRequiresReadableRegularCKAssetFile() throws {
        let assetID = "00000000-0000-0000-0000-000000000934"
        let bytes = Data([9, 3, 4])
        let directory = try makeTemporaryDirectory()
        let validFile = directory.appendingPathComponent("valid.asset")
        let invalidFile = directory.appendingPathComponent("missing.asset")
        try bytes.write(to: validFile)

        func record() -> CKRecord {
            let value = CKRecord(
                recordType: CloudPhotoAssetRecordContract.recordType,
                recordID: CKRecord.ID(
                    recordName: "progress-photo-asset-\(assetID)"
                )
            )
            value["assetID"] = assetID as CKRecordValue
            value["checksum"] = CloudPhotoAssetChecksum.sha256Hex(bytes) as CKRecordValue
            value["byteCount"] = NSNumber(value: bytes.count)
            return value
        }

        let missingAsset = record()
        let wrongTypeAsset = record()
        wrongTypeAsset["asset"] = "not-a-ckasset" as CKRecordValue
        let invalidFileAsset = record()
        invalidFileAsset["asset"] = CKAsset(fileURL: invalidFile)
        let directoryAsset = record()
        directoryAsset["asset"] = CKAsset(fileURL: directory)
        let validAsset = record()
        validAsset["asset"] = CKAsset(fileURL: validFile)

        XCTAssertFalse(
            try CloudKitPhotoAssetRecordMapper.systemRecord(
                from: missingAsset
            ).hasUsableBinaryAsset
        )
        XCTAssertFalse(
            try CloudKitPhotoAssetRecordMapper.systemRecord(
                from: wrongTypeAsset
            ).hasUsableBinaryAsset
        )
        XCTAssertFalse(
            try CloudKitPhotoAssetRecordMapper.systemRecord(
                from: invalidFileAsset
            ).hasUsableBinaryAsset
        )
        XCTAssertFalse(
            try CloudKitPhotoAssetRecordMapper.systemRecord(
                from: directoryAsset
            ).hasUsableBinaryAsset
        )
        XCTAssertTrue(
            try CloudKitPhotoAssetRecordMapper.systemRecord(
                from: validAsset
            ).hasUsableBinaryAsset
        )
    }

    func testExplicitChangedKeysModifyRepairsSameIDAssetAndPreservesUnknownFields() async throws {
        let assetID = "00000000-0000-0000-0000-000000000935"
        let bytes = Data([9, 3, 5])
        let directory = try makeTemporaryDirectory()
        let uploadURL = directory.appendingPathComponent("repair.asset")
        try bytes.write(to: uploadURL)
        let zoneID = CKRecordZone.ID(
            zoneName: CloudPhotoAssetRecordContract.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let request = try CloudPhotoAssetUploadRequest(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            fileURL: uploadURL
        )
        let repairRecord = CloudKitPhotoAssetRecordMapper.uploadRecord(
            from: request,
            zoneID: zoneID
        )
        let existing = CKRecord(
            recordType: CloudPhotoAssetRecordContract.recordType,
            recordID: repairRecord.recordID
        )
        existing["assetID"] = request.assetID as CKRecordValue
        existing["checksum"] = request.checksum as CKRecordValue
        existing["byteCount"] = NSNumber(value: request.byteCount)
        existing["serverOnly"] = "preserve-me" as CKRecordValue
        let modifier = ConflictAwareCloudKitPhotoAssetRecordModifier(
            existingRecord: existing
        )

        do {
            _ = try await modifier.modifyRecords(
                saving: [repairRecord],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            XCTFail("Default same-ID replacement must model a conflict without a change tag.")
        } catch {
            XCTAssertEqual(
                error as? ConflictAwareCloudKitPhotoAssetRecordModifier.Error,
                .serverRecordChanged
            )
        }

        let saver = CloudKitPhotoAssetRecordSaver(recordModifier: modifier)
        let saved = try await saver.save(repairRecord)
        let mapped = try CloudKitPhotoAssetRecordMapper.systemRecord(from: saved)
        let snapshot = await modifier.snapshot()

        XCTAssertTrue(mapped.hasUsableBinaryAsset)
        XCTAssertEqual(mapped.metadata.assetID, assetID)
        XCTAssertEqual(saved["serverOnly"] as? String, "preserve-me")
        XCTAssertEqual(
            snapshot.savePolicyRawValues,
            [
                CKModifyRecordsOperation.RecordSavePolicy
                    .ifServerRecordUnchanged.rawValue,
                CKModifyRecordsOperation.RecordSavePolicy.changedKeys.rawValue,
            ]
        )
        XCTAssertEqual(snapshot.atomicValues, [true, true])
        XCTAssertEqual(
            snapshot.savedRecordNames,
            [request.recordName, request.recordName]
        )
    }

    func testExplicitModifySurfacesExactPerRecordFailure() async throws {
        let assetID = "00000000-0000-0000-0000-000000000936"
        let bytes = Data([9, 3, 6])
        let directory = try makeTemporaryDirectory()
        let uploadURL = directory.appendingPathComponent("failed-repair.asset")
        try bytes.write(to: uploadURL)
        let request = try CloudPhotoAssetUploadRequest(
            recordName: CloudPhotoAssetRecordContract.recordName(for: assetID),
            assetID: assetID,
            checksum: CloudPhotoAssetChecksum.sha256Hex(bytes),
            byteCount: bytes.count,
            fileURL: uploadURL
        )
        let record = CloudKitPhotoAssetRecordMapper.uploadRecord(
            from: request,
            zoneID: CKRecordZone.ID(
                zoneName: CloudPhotoAssetRecordContract.zoneName,
                ownerName: CKCurrentUserDefaultName
            )
        )
        let modifier = ConflictAwareCloudKitPhotoAssetRecordModifier(
            perRecordError: .perRecordFailure
        )
        let saver = CloudKitPhotoAssetRecordSaver(recordModifier: modifier)

        do {
            _ = try await saver.save(record)
            XCTFail("A per-record CloudKit failure must not be reported as save success.")
        } catch {
            XCTAssertEqual(
                error as? ConflictAwareCloudKitPhotoAssetRecordModifier.Error,
                .perRecordFailure
            )
        }
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

private actor ConflictAwareCloudKitPhotoAssetRecordModifier:
    CloudKitPhotoAssetRecordModifying {
    enum Error: Swift.Error, Equatable {
        case serverRecordChanged
        case perRecordFailure
    }

    struct Snapshot: Sendable {
        let savePolicyRawValues: [Int]
        let atomicValues: [Bool]
        let savedRecordNames: [String]
    }

    private var existingRecord: CKRecord?
    private let perRecordError: Error?
    private var savePolicyRawValues: [Int] = []
    private var atomicValues: [Bool] = []
    private var savedRecordNames: [String] = []

    init(
        existingRecord: CKRecord? = nil,
        perRecordError: Error? = nil
    ) {
        self.existingRecord = existingRecord
        self.perRecordError = perRecordError
    }

    func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> CloudKitPhotoAssetRecordModifyResults {
        savePolicyRawValues.append(savePolicy.rawValue)
        atomicValues.append(atomically)
        savedRecordNames.append(contentsOf: records.map(\.recordID.recordName))
        guard recordIDs.isEmpty else {
            throw CloudPhotoAssetDatabaseError.permanent
        }
        if existingRecord != nil, savePolicy != .changedKeys {
            throw Error.serverRecordChanged
        }
        guard let record = records.first, records.count == 1 else {
            throw CloudPhotoAssetDatabaseError.permanent
        }
        if let perRecordError {
            return CloudKitPhotoAssetRecordModifyResults(
                saveResults: [record.recordID: .failure(perRecordError)],
                deleteResults: [:]
            )
        }
        let saved = existingRecord ?? CKRecord(
            recordType: record.recordType,
            recordID: record.recordID
        )
        for key in CloudPhotoAssetRecordContract.fieldNames {
            saved[key] = record[key]
        }
        existingRecord = saved
        return CloudKitPhotoAssetRecordModifyResults(
            saveResults: [record.recordID: .success(saved)],
            deleteResults: [:]
        )
    }

    func snapshot() -> Snapshot {
        Snapshot(
            savePolicyRawValues: savePolicyRawValues,
            atomicValues: atomicValues,
            savedRecordNames: savedRecordNames
        )
    }
}

private actor CloudPhotoAssetSystemDatabaseFake:
    CloudPhotoAssetSystemDatabase {
    struct Snapshot: Sendable {
        let recordRequests: [String]
        let saveRequests: [CloudPhotoAssetUploadRequest]
    }

    private var page: CloudPhotoAssetSystemChangePage?
    private let recordResult: CloudPhotoAssetSystemRecord?
    private var recordRequests: [String] = []
    private var saveRequests: [CloudPhotoAssetUploadRequest] = []

    init(
        page: CloudPhotoAssetSystemChangePage,
        recordResult: CloudPhotoAssetSystemRecord? = nil
    ) {
        self.page = page
        self.recordResult = recordResult
    }

    func accountStatus() async throws -> CloudPhotoAccountStatus {
        .available
    }

    func ensureZone(named zoneName: String) async throws {
        _ = zoneName
    }

    func record(
        named recordName: String,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetSystemRecord? {
        _ = zoneName
        recordRequests.append(recordName)
        return recordResult
    }

    func save(
        _ request: CloudPhotoAssetUploadRequest,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata {
        _ = zoneName
        saveRequests.append(request)
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
        _ = recordName
        _ = zoneName
    }

    func fetchSystemChanges(
        inZone zoneName: String,
        previousToken: Data?
    ) async throws -> CloudPhotoAssetSystemChangePage {
        _ = zoneName
        _ = previousToken
        guard let page else {
            throw CloudPhotoAssetDatabaseError.permanent
        }
        self.page = nil
        return page
    }

    func snapshot() -> Snapshot {
        Snapshot(
            recordRequests: recordRequests,
            saveRequests: saveRequests
        )
    }
}

private final class CloudPhotoAssetSystemURLLifetimeOwner {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    deinit {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

private actor CloudPhotoAssetIntegrationLocalStoreFake:
    CloudPhotoAssetLocalStoring {
    private var assets: [String: Data]

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
    }

    func deleteCloudAsset(id: String) async throws {
        assets.removeValue(forKey: id)
    }

    func bytes(for assetID: String) -> Data? {
        assets[assetID]
    }
}

private actor CloudPhotoAssetIntegrationReferenceProviderFake:
    CloudPhotoAssetReferenceSnapshotProviding {
    private let referencedAssetIDs: Set<String>

    init(referencedAssetIDs: Set<String> = []) {
        self.referencedAssetIDs = referencedAssetIDs
    }

    func snapshot() async throws -> CloudPhotoAssetReferenceSnapshot {
        CloudPhotoAssetReferenceSnapshot(referencedAssetIDs: referencedAssetIDs)
    }
}

private actor CloudPhotoAssetIntegrationDeletionIntentStoreFake:
    CloudPhotoAssetDeletionIntentStoring {
    private var activeAccountResolutionID: UUID?

    func beginAccountResolution() async -> CloudPhotoAssetAccountResolution {
        let resolution = CloudPhotoAssetAccountResolution()
        activeAccountResolutionID = resolution.resolutionID
        return resolution
    }

    func activateAccountIdentity(
        _ accountIdentity: String,
        resolution: CloudPhotoAssetAccountResolution
    ) async throws -> CloudPhotoAssetAccountAuthorization {
        guard activeAccountResolutionID == resolution.resolutionID else {
            throw CancellationError()
        }
        activeAccountResolutionID = nil
        return CloudPhotoAssetAccountAuthorization(accountIdentity: accountIdentity)
    }

    func suspendAccountAuthorization(
        _ authorization: CloudPhotoAssetAccountAuthorization
    ) async {
        _ = authorization
    }

    func pendingDeletionIntents(
        forAccountIdentity accountIdentity: String
    ) async throws -> [CloudPhotoAssetDeletionIntentReceipt] {
        _ = accountIdentity
        return []
    }

    func pendingDeletionAssetIDs(
        forAccountIdentity accountIdentity: String
    ) async throws -> Set<String> {
        _ = accountIdentity
        return []
    }

    func unresolvedDeletionAssetIDs() async throws -> Set<String> { [] }

    func hasCommittedLocalDeletionIntent(assetID: String) async throws -> Bool {
        _ = assetID
        return false
    }

    func recordCommittedDeletion(
        assetID: String
    ) async throws -> CloudPhotoAssetDeletionIntentReceipt {
        CloudPhotoAssetDeletionIntentReceipt(assetID: assetID, accountIdentity: nil)
    }

    func clearCommittedDeletion(
        _ intent: CloudPhotoAssetDeletionIntentReceipt
    ) async throws {
        _ = intent
    }

    func clearCommittedDeletion(
        assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws {
        _ = assetID
        _ = accountIdentity
    }
}

private actor CloudPhotoAssetIntegrationInboundJournalFake:
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

private actor CloudPhotoAccountIdentityProviderFake:
    CloudPhotoAccountIdentityProviding {
    private var identities: [String]

    init(identities: [String]) {
        precondition(!identities.isEmpty)
        self.identities = identities
    }

    func accountIdentity() async throws -> String {
        guard identities.count > 1 else { return identities[0] }
        return identities.removeFirst()
    }
}
