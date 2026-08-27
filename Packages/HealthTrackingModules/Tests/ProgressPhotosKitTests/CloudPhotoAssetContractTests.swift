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

        XCTAssertEqual(try await first.load(), .empty)
        try await first.save(state)

        let recreated = FileCloudPhotoAssetSyncStateStore(fileURL: fileURL)
        XCTAssertEqual(try await recreated.load(), state)
        let persisted = try Data(contentsOf: fileURL)
        let payload = String(decoding: persisted, as: UTF8.self)
        XCTAssertFalse(payload.contains("pose"))
        XCTAssertFalse(payload.contains("note"))
        XCTAssertFalse(payload.contains("file://"))
        XCTAssertFalse(payload.contains("/private/"))
    }

    func testTemporaryStoreOwnsUploadAndDownloadCopiesUntilExplicitCleanup() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("system-staged-download.jpg")
        try Data([4, 5, 6]).write(to: source)
        let ownedDirectory = directory.appendingPathComponent("owned", isDirectory: true)
        let store = FileCloudPhotoAssetTemporaryStore(
            directory: ownedDirectory,
            makeID: {
                UUID(uuidString: "00000000-0000-0000-0000-000000000905")!
            }
        )

        let upload = try store.createUploadFile(bytes: Data([1, 2, 3]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: upload.path))
        XCTAssertTrue(upload.path.hasPrefix(ownedDirectory.path))

        let download = try store.copyDownloadedFile(from: source)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try store.readFile(at: download), Data([4, 5, 6]))

        store.removeFile(at: upload)
        store.removeFile(at: download)
        XCTAssertFalse(FileManager.default.fileExists(atPath: upload.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: download.path))
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
