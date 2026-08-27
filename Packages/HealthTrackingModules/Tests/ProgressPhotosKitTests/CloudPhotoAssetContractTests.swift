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
        try Data([1]).write(to: stale)
        try Data([2]).write(to: unrelated)

        _ = FileCloudPhotoAssetTemporaryStore(directory: ownedDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
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
    }

    private let lock = NSLock()
    private let sourceBytes: Data
    private let maximumReadChunkSize: Int
    private var offset = 0
    private var sourceURLs: [URL] = []
    private var destinationURLs: [URL] = []
    private var readRequests: [Int] = []
    private var destinationBytes = Data()

    init(sourceBytes: Data, maximumReadChunkSize: Int) {
        precondition(maximumReadChunkSize > 0)
        self.sourceBytes = sourceBytes
        self.maximumReadChunkSize = maximumReadChunkSize
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

    func close() throws {}

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            sourceURLs: sourceURLs,
            destinationURLs: destinationURLs,
            readRequests: readRequests,
            destinationBytes: destinationBytes
        )
    }
}
