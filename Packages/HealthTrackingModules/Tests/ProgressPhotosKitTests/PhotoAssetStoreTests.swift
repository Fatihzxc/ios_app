import Foundation
import ProgressPhotosKit
import XCTest

@MainActor
final class PhotoAssetStoreTests: XCTestCase {
    func testImportNormalizesOrientationAndMetadataIntoBoundedProtectedAtomicFiles() async throws {
        let applicationSupport = temporaryDirectory()
        let fileSystem = RecordingPhotoAssetFileSystem(applicationSupport: applicationSupport)
        let processor = PhotoImageProcessorFake(
            metadata: .init(
                pixelWidth: 12,
                pixelHeight: 8,
                orientation: .rightMirrored
            ),
            normalized: .init(
                full: .init(
                    bytes: Data([0x10, 0x11]),
                    pixelWidth: 8,
                    pixelHeight: 5,
                    orientation: .up,
                    containsMetadata: false
                ),
                thumbnail: .init(
                    bytes: Data([0x20]),
                    pixelWidth: 2,
                    pixelHeight: 1,
                    orientation: .up,
                    containsMetadata: false
                )
            )
        )
        let assetID = UUID(uuidString: "00000000-0000-0000-0000-000000000037")!
        let temporaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000038")!
        let policy = PhotoAssetPolicy(
            maximumInputBytes: 16,
            maximumPixelCount: 128,
            fullMaximumDimension: 8,
            thumbnailMaximumDimension: 2,
            encodingQuality: 0.7
        )
        let store = LocalPhotoAssetStore(
            policy: policy,
            processor: processor,
            fileSystem: fileSystem,
            makeAssetID: { assetID },
            makeTemporaryID: { temporaryID }
        )
        let original = Data([0x01, 0x02, 0x03])

        let reference = try await store.importAsset(original)

        XCTAssertEqual(reference.assetID, assetID.uuidString.lowercased())
        XCTAssertFalse(reference.assetID.contains("/"))
        XCTAssertFalse(reference.assetID.contains(applicationSupport.path))
        XCTAssertEqual(processor.inspectedBytes, [original])
        XCTAssertEqual(processor.normalizationRequests.count, 1)
        XCTAssertEqual(processor.normalizationRequests[0].metadata.orientation, .rightMirrored)
        XCTAssertEqual(processor.normalizationRequests[0].policy, policy)

        let finalDirectory = applicationSupport
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent(reference.assetID, isDirectory: true)
        XCTAssertEqual(fileSystem.moveOperations.count, 1)
        XCTAssertTrue(fileSystem.moveOperations[0].source.path.contains(".staging"))
        XCTAssertEqual(fileSystem.moveOperations[0].destination, finalDirectory)
        XCTAssertEqual(
            try Data(contentsOf: finalDirectory.appendingPathComponent("full.jpg")),
            Data([0x10, 0x11])
        )
        XCTAssertEqual(
            try Data(contentsOf: finalDirectory.appendingPathComponent("thumbnail.jpg")),
            Data([0x20])
        )
        XCTAssertEqual(fileSystem.protectedWriteURLs.count, 2)
        XCTAssertTrue(
            fileSystem.protectedWriteURLs.allSatisfy { $0.path.contains(".staging") },
            "Every byte must be created atomically with complete protection."
        )
        XCTAssertTrue(
            fileSystem.protectedDirectoryURLs.contains {
                $0.path.contains(".staging")
            },
            "The staging directory itself must have complete protection."
        )
        XCTAssertTrue(
            fileSystem.protectedWriteURLs.allSatisfy { $0.path.contains(".staging") },
            "The final directory must never expose a partially written asset."
        )
    }

    func testImportPurgesStaleStagingBeforeWritingNewProtectedAsset() async throws {
        let applicationSupport = temporaryDirectory()
        let stagingRoot = applicationSupport
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent(".staging", isDirectory: true)
        let staleDirectory = stagingRoot.appendingPathComponent(
            "stale-crash-window",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: staleDirectory,
            withIntermediateDirectories: true
        )
        try Data([0xde, 0xad]).write(
            to: staleDirectory.appendingPathComponent("plaintext.tmp")
        )
        let fileSystem = RecordingPhotoAssetFileSystem(
            applicationSupport: applicationSupport
        )
        let store = LocalPhotoAssetStore(
            policy: .testFixture,
            processor: PhotoImageProcessorFake(
                metadata: .init(pixelWidth: 2, pixelHeight: 2, orientation: .up),
                normalized: .tinyFixture
            ),
            fileSystem: fileSystem,
            makeAssetID: {
                UUID(uuidString: "00000000-0000-0000-0000-000000000064")!
            }
        )

        _ = try await store.importAsset(Data([1]))

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleDirectory.path))
        XCTAssertTrue(fileSystem.removedURLs.contains(stagingRoot))
        XCTAssertTrue(
            fileSystem.protectedWriteURLs.allSatisfy { !$0.path.contains("stale-crash-window") }
        )
    }

    func testImportRejectsEmptyOversizedCorruptAndPixelBombInputsBeforeWriting() async throws {
        let applicationSupport = temporaryDirectory()
        let fileSystem = RecordingPhotoAssetFileSystem(applicationSupport: applicationSupport)
        let processor = PhotoImageProcessorFake(
            metadata: .init(pixelWidth: 5, pixelHeight: 5, orientation: .up),
            normalized: .tinyFixture
        )
        let policy = PhotoAssetPolicy(
            maximumInputBytes: 3,
            maximumPixelCount: 16,
            fullMaximumDimension: 4,
            thumbnailMaximumDimension: 2,
            encodingQuality: 0.7
        )
        let store = LocalPhotoAssetStore(
            policy: policy,
            processor: processor,
            fileSystem: fileSystem
        )

        await assertImportError(.emptyInput) {
            try await store.importAsset(Data())
        }
        await assertImportError(.inputTooLarge(maximumBytes: 3)) {
            try await store.importAsset(Data([0, 1, 2, 3]))
        }
        await assertImportError(.pixelCountTooLarge(maximumPixels: 16)) {
            try await store.importAsset(Data([1]))
        }

        processor.inspectError = PhotoImageProcessingError.corruptInput
        await assertImportError(.corruptInput) {
            try await store.importAsset(Data([2]))
        }
        XCTAssertTrue(fileSystem.protectedWriteURLs.isEmpty)
        XCTAssertTrue(fileSystem.moveOperations.isEmpty)
    }

    func testImportRejectsProcessorOutputThatRetainsMetadataOrientationOrExceedsBounds() async {
        let applicationSupport = temporaryDirectory()
        let fileSystem = RecordingPhotoAssetFileSystem(applicationSupport: applicationSupport)
        let processor = PhotoImageProcessorFake(
            metadata: .init(pixelWidth: 4, pixelHeight: 4, orientation: .left),
            normalized: .init(
                full: .init(
                    bytes: Data([1]),
                    pixelWidth: 5,
                    pixelHeight: 2,
                    orientation: .left,
                    containsMetadata: true
                ),
                thumbnail: .init(
                    bytes: Data([2]),
                    pixelWidth: 2,
                    pixelHeight: 2,
                    orientation: .up,
                    containsMetadata: false
                )
            )
        )
        let store = LocalPhotoAssetStore(
            policy: .init(
                maximumInputBytes: 8,
                maximumPixelCount: 32,
                fullMaximumDimension: 4,
                thumbnailMaximumDimension: 2,
                encodingQuality: 0.7
            ),
            processor: processor,
            fileSystem: fileSystem
        )

        await assertImportError(.invalidNormalizedOutput) {
            try await store.importAsset(Data([1]))
        }
        XCTAssertTrue(fileSystem.protectedWriteURLs.isEmpty)
    }

    func testLoadReturnsMissingOrCorruptFallbackWithoutExposingAPath() async throws {
        let applicationSupport = temporaryDirectory()
        let fileSystem = RecordingPhotoAssetFileSystem(applicationSupport: applicationSupport)
        let processor = PhotoImageProcessorFake(
            metadata: .init(pixelWidth: 2, pixelHeight: 2, orientation: .up),
            normalized: .tinyFixture
        )
        let assetID = UUID(uuidString: "00000000-0000-0000-0000-000000000039")!
        let store = LocalPhotoAssetStore(
            policy: .testFixture,
            processor: processor,
            fileSystem: fileSystem,
            makeAssetID: { assetID }
        )
        let reference = try await store.importAsset(Data([1]))
        let thumbnailURL = applicationSupport
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent(reference.assetID, isDirectory: true)
            .appendingPathComponent("thumbnail.jpg")

        try FileManager.default.removeItem(at: thumbnailURL)
        let missing = try await store.loadAsset(
            id: reference.assetID,
            variant: .thumbnail
        )
        XCTAssertEqual(missing, .missing)

        try Data([0xff]).write(to: thumbnailURL)
        processor.corruptEncodedBytes = [Data([0xff])]
        let corrupt = try await store.loadAsset(
            id: reference.assetID,
            variant: .thumbnail
        )
        XCTAssertEqual(corrupt, .corrupt)
    }

    func testDeleteIsIdempotentAndProtectedDataFailureKeepsAssetForRetry() async throws {
        let applicationSupport = temporaryDirectory()
        let fileSystem = RecordingPhotoAssetFileSystem(applicationSupport: applicationSupport)
        let processor = PhotoImageProcessorFake(
            metadata: .init(pixelWidth: 2, pixelHeight: 2, orientation: .up),
            normalized: .tinyFixture
        )
        let assetID = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!
        let store = LocalPhotoAssetStore(
            policy: .testFixture,
            processor: processor,
            fileSystem: fileSystem,
            makeAssetID: { assetID }
        )
        let reference = try await store.importAsset(Data([1]))
        let finalDirectory = applicationSupport
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent(reference.assetID, isDirectory: true)

        fileSystem.removeError = .protectedDataUnavailable
        do {
            try await store.deleteAsset(id: reference.assetID)
            XCTFail("Protected data must remain retryable.")
        } catch {
            XCTAssertEqual(error as? PhotoAssetStoreError, .protectedDataUnavailable)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalDirectory.path))

        fileSystem.removeError = nil
        try await store.deleteAsset(id: reference.assetID)
        try await store.deleteAsset(id: reference.assetID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalDirectory.path))
    }

    func testCloudRestoreUsesExactOpaqueIDAndRebuildsBothVariantsIdempotently() async throws {
        let applicationSupport = temporaryDirectory()
        let fileSystem = RecordingPhotoAssetFileSystem(applicationSupport: applicationSupport)
        let processor = PhotoImageProcessorFake(
            metadata: .init(pixelWidth: 2, pixelHeight: 2, orientation: .up),
            normalized: .tinyFixture
        )
        let store = LocalPhotoAssetStore(
            policy: .testFixture,
            processor: processor,
            fileSystem: fileSystem
        )
        let assetID = "00000000-0000-0000-0000-000000000920"

        try await store.restoreCloudAsset(id: assetID, bytes: Data([0x09]))
        try await store.restoreCloudAsset(id: assetID, bytes: Data([0x09]))

        let cloudBytes = try await store.cloudAssetBytes(id: assetID)
        let storedAssetIDs = try await store.storedAssetIDs()
        XCTAssertEqual(cloudBytes, Data([0x10]))
        XCTAssertEqual(storedAssetIDs, [assetID])
        let finalDirectory = applicationSupport
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent(assetID, isDirectory: true)
        XCTAssertEqual(
            try Data(contentsOf: finalDirectory.appendingPathComponent("full.jpg")),
            Data([0x10])
        )
        XCTAssertEqual(
            try Data(contentsOf: finalDirectory.appendingPathComponent("thumbnail.jpg")),
            Data([0x20])
        )

        try await store.deleteCloudAsset(id: assetID)
        try await store.deleteCloudAsset(id: assetID)
        let remainingAssetIDs = try await store.storedAssetIDs()
        XCTAssertEqual(remainingAssetIDs, [])
    }

    private func assertImportError(
        _ expected: PhotoAssetStoreError,
        operation: () async throws -> PhotoAssetReference
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected import error: \(expected)")
        } catch {
            XCTAssertEqual(error as? PhotoAssetStoreError, expected)
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private final class PhotoImageProcessorFake:
    PhotoImageProcessing,
    @unchecked Sendable {
    struct NormalizationRequest: Equatable {
        let bytes: Data
        let metadata: PhotoImageMetadata
        let policy: PhotoAssetPolicy
    }

    let metadata: PhotoImageMetadata
    let normalized: PhotoNormalizedAsset
    var inspectError: Error?
    var corruptEncodedBytes: Set<Data> = []
    private(set) var inspectedBytes: [Data] = []
    private(set) var normalizationRequests: [NormalizationRequest] = []

    init(metadata: PhotoImageMetadata, normalized: PhotoNormalizedAsset) {
        self.metadata = metadata
        self.normalized = normalized
    }

    func inspect(_ bytes: Data) throws -> PhotoImageMetadata {
        inspectedBytes.append(bytes)
        if corruptEncodedBytes.contains(bytes) {
            throw PhotoImageProcessingError.corruptInput
        }
        if let inspectError { throw inspectError }
        return metadata
    }

    func normalize(
        _ bytes: Data,
        metadata: PhotoImageMetadata,
        policy: PhotoAssetPolicy
    ) throws -> PhotoNormalizedAsset {
        normalizationRequests.append(
            .init(bytes: bytes, metadata: metadata, policy: policy)
        )
        return normalized
    }
}

private extension PhotoNormalizedAsset {
    static let tinyFixture = PhotoNormalizedAsset(
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

private extension PhotoAssetPolicy {
    static let testFixture = PhotoAssetPolicy(
        maximumInputBytes: 8,
        maximumPixelCount: 16,
        fullMaximumDimension: 4,
        thumbnailMaximumDimension: 2,
        encodingQuality: 0.7
    )
}

private final class RecordingPhotoAssetFileSystem:
    PhotoAssetFileSystem,
    @unchecked Sendable {
    struct MoveOperation: Equatable {
        let source: URL
        let destination: URL
    }

    let applicationSupport: URL
    var removeError: PhotoAssetFileSystemError?
    private(set) var protectedWriteURLs: [URL] = []
    private(set) var protectedDirectoryURLs: [URL] = []
    private(set) var removedURLs: [URL] = []
    private(set) var moveOperations: [MoveOperation] = []

    init(applicationSupport: URL) {
        self.applicationSupport = applicationSupport
    }

    func applicationSupportDirectory() throws -> URL { applicationSupport }

    func createProtectedDirectory(at url: URL) throws {
        protectedDirectoryURLs.append(url)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func writeProtectedAtomically(_ data: Data, to url: URL) throws {
        protectedWriteURLs.append(url)
        try data.write(to: url, options: .atomic)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        moveOperations.append(.init(source: source, destination: destination))
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func data(at url: URL) throws -> Data {
        guard fileExists(at: url) else {
            throw PhotoAssetFileSystemError.notFound
        }
        return try Data(contentsOf: url)
    }

    func removeItemIfExists(at url: URL) throws {
        if let removeError { throw removeError }
        removedURLs.append(url)
        guard fileExists(at: url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        guard fileExists(at: url) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
    }
}
