@testable import ProgressPhotosKit
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
                            systemFileURL: systemURL
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

        let page = try await adapter.fetchChanges(
            inZone: CloudPhotoAssetRecordContract.zoneName,
            previousToken: nil
        )
        try FileManager.default.removeItem(at: systemURL)
        let changed = try XCTUnwrap(page.changes.first)
        guard case let .changed(record) = changed else {
            return XCTFail("Expected one changed cloud asset record.")
        }

        XCTAssertNotEqual(record.stagedFileURL, systemURL)
        XCTAssertTrue(
            record.stagedFileURL.path.hasPrefix(transferDirectory.path + "/")
        )
        XCTAssertEqual(try store.readFile(at: record.stagedFileURL), bytes)
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
            inboundAssetJournal: inboundJournal,
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

private actor CloudPhotoAssetSystemDatabaseFake:
    CloudPhotoAssetSystemDatabase {
    private let page: CloudPhotoAssetSystemChangePage

    init(page: CloudPhotoAssetSystemChangePage) {
        self.page = page
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
        _ = recordName
        _ = zoneName
    }

    func fetchSystemChanges(
        inZone zoneName: String,
        previousToken: Data?
    ) async throws -> CloudPhotoAssetSystemChangePage {
        _ = zoneName
        _ = previousToken
        return page
    }
}

private actor CloudPhotoAssetIntegrationLocalStoreFake:
    CloudPhotoAssetLocalStoring {
    private var assets: [String: Data] = [:]

    func storedAssetIDs() async throws -> Set<String> {
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
    func snapshot() async throws -> CloudPhotoAssetReferenceSnapshot {
        CloudPhotoAssetReferenceSnapshot(referencedAssetIDs: [])
    }
}

private actor CloudPhotoAssetIntegrationDeletionIntentStoreFake:
    CloudPhotoAssetDeletionIntentStoring {
    func pendingDeletionAssetIDs() async throws -> Set<String> { [] }
    func recordCommittedDeletion(assetID: String) async throws { _ = assetID }
    func clearCommittedDeletion(assetID: String) async throws { _ = assetID }
    func clearAllCommittedDeletions() async throws {}
}

private actor CloudPhotoAssetIntegrationInboundJournalFake:
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
