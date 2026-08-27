import Foundation

@MainActor
public final class LocalPhotoAssetStore: PhotoAssetStoring {
    private let policy: PhotoAssetPolicy
    private let processor: any PhotoImageProcessing
    private let fileSystem: any PhotoAssetFileSystem
    private let makeAssetID: @MainActor () -> UUID
    private let makeTemporaryID: @MainActor () -> UUID

    public init(
        policy: PhotoAssetPolicy = .production,
        processor: any PhotoImageProcessing,
        fileSystem: any PhotoAssetFileSystem = FileManagerPhotoAssetFileSystem(),
        makeAssetID: @escaping @MainActor () -> UUID = { UUID() },
        makeTemporaryID: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        self.policy = policy
        self.processor = processor
        self.fileSystem = fileSystem
        self.makeAssetID = makeAssetID
        self.makeTemporaryID = makeTemporaryID
    }

    public func importAsset(_ bytes: Data) async throws -> PhotoAssetReference {
        guard !bytes.isEmpty else { throw PhotoAssetStoreError.emptyInput }
        guard bytes.count <= policy.maximumInputBytes else {
            throw PhotoAssetStoreError.inputTooLarge(
                maximumBytes: policy.maximumInputBytes
            )
        }

        let metadata: PhotoImageMetadata
        do {
            metadata = try processor.inspect(bytes)
        } catch {
            throw mapProcessingError(error)
        }
        guard metadata.pixelWidth > 0,
              metadata.pixelHeight > 0,
              metadata.pixelWidth <= policy.maximumPixelCount / metadata.pixelHeight else {
            throw PhotoAssetStoreError.pixelCountTooLarge(
                maximumPixels: policy.maximumPixelCount
            )
        }

        let normalized: PhotoNormalizedAsset
        do {
            normalized = try processor.normalize(
                bytes,
                metadata: metadata,
                policy: policy
            )
        } catch {
            throw mapProcessingError(error)
        }
        guard isValid(
            normalized.full,
            maximumDimension: policy.fullMaximumDimension
        ), isValid(
            normalized.thumbnail,
            maximumDimension: policy.thumbnailMaximumDimension
        ) else {
            throw PhotoAssetStoreError.invalidNormalizedOutput
        }

        let assetID = makeAssetID().uuidString.lowercased()
        guard isOpaquePhotoAssetID(assetID) else {
            throw PhotoAssetStoreError.invalidAssetID
        }

        let applicationSupport: URL
        do {
            applicationSupport = try fileSystem.applicationSupportDirectory()
        } catch {
            throw mapFileSystemError(error)
        }
        let root = applicationSupport
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
        let stagingRoot = root
            .appendingPathComponent(".staging", isDirectory: true)
        let stagingDirectory = stagingRoot.appendingPathComponent(
            makeTemporaryID().uuidString.lowercased(),
            isDirectory: true
        )
        let finalDirectory = root.appendingPathComponent(
            assetID,
            isDirectory: true
        )
        guard !fileSystem.fileExists(at: finalDirectory) else {
            throw PhotoAssetStoreError.assetIDCollision
        }

        do {
            try fileSystem.createDirectory(at: stagingRoot)
            try fileSystem.removeItemIfExists(at: stagingDirectory)
            try fileSystem.createDirectory(at: stagingDirectory)
            let fullURL = stagingDirectory.appendingPathComponent("full.jpg")
            let thumbnailURL = stagingDirectory.appendingPathComponent("thumbnail.jpg")
            try fileSystem.write(normalized.full.bytes, to: fullURL)
            try fileSystem.applyCompleteProtection(to: fullURL)
            try fileSystem.write(normalized.thumbnail.bytes, to: thumbnailURL)
            try fileSystem.applyCompleteProtection(to: thumbnailURL)
            try fileSystem.moveItem(at: stagingDirectory, to: finalDirectory)
        } catch {
            try? fileSystem.removeItemIfExists(at: stagingDirectory)
            throw mapFileSystemError(error)
        }
        return PhotoAssetReference(assetID: assetID)
    }

    public func loadAsset(
        id: String,
        variant: PhotoAssetVariant
    ) async throws -> PhotoAssetLoadResult {
        guard isOpaquePhotoAssetID(id) else {
            throw PhotoAssetStoreError.invalidAssetID
        }
        let url: URL
        do {
            let applicationSupport = try fileSystem.applicationSupportDirectory()
            let filename = variant == .full ? "full.jpg" : "thumbnail.jpg"
            url = applicationSupport
                .appendingPathComponent("ProgressPhotos", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
                .appendingPathComponent(filename)
        } catch {
            throw mapFileSystemError(error)
        }

        let bytes: Data
        do {
            bytes = try fileSystem.data(at: url)
        } catch PhotoAssetFileSystemError.notFound {
            return .missing
        } catch {
            throw mapFileSystemError(error)
        }
        guard !bytes.isEmpty else { return .corrupt }
        do {
            let metadata = try processor.inspect(bytes)
            guard metadata.pixelWidth > 0,
                  metadata.pixelHeight > 0,
                  metadata.orientation == .up else {
                return .corrupt
            }
        } catch {
            return .corrupt
        }
        return .available(bytes)
    }

    public func deleteAsset(id: String) async throws {
        guard isOpaquePhotoAssetID(id) else {
            throw PhotoAssetStoreError.invalidAssetID
        }
        do {
            let applicationSupport = try fileSystem.applicationSupportDirectory()
            let directory = applicationSupport
                .appendingPathComponent("ProgressPhotos", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
            try fileSystem.removeItemIfExists(at: directory)
        } catch {
            throw mapFileSystemError(error)
        }
    }

    private func isValid(
        _ image: PhotoEncodedImage,
        maximumDimension: Int
    ) -> Bool {
        !image.bytes.isEmpty
            && image.pixelWidth > 0
            && image.pixelHeight > 0
            && image.pixelWidth <= maximumDimension
            && image.pixelHeight <= maximumDimension
            && image.orientation == .up
            && !image.containsMetadata
    }

    private func mapProcessingError(_ error: Error) -> PhotoAssetStoreError {
        guard let processingError = error as? PhotoImageProcessingError else {
            return .invalidNormalizedOutput
        }
        switch processingError {
        case .corruptInput:
            return .corruptInput
        case .encodingFailed:
            return .invalidNormalizedOutput
        }
    }

    private func mapFileSystemError(_ error: Error) -> PhotoAssetStoreError {
        guard let fileError = error as? PhotoAssetFileSystemError else {
            return .fileOperationFailed
        }
        switch fileError {
        case .protectedDataUnavailable:
            return .protectedDataUnavailable
        case .notFound, .operationFailed:
            return .fileOperationFailed
        }
    }
}

@MainActor
public final class FileManagerPhotoAssetFileSystem: PhotoAssetFileSystem {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func applicationSupportDirectory() throws -> URL {
        guard let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PhotoAssetFileSystemError.operationFailed
        }
        return directory
    }

    public func createDirectory(at url: URL) throws {
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            throw mapped(error)
        }
    }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url)
        } catch {
            throw mapped(error)
        }
    }

    public func applyCompleteProtection(to url: URL) throws {
        #if targetEnvironment(simulator)
        _ = url
        #else
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        } catch {
            throw mapped(error)
        }
        #endif
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw mapped(error)
        }
    }

    public func data(at url: URL) throws -> Data {
        guard fileExists(at: url) else {
            throw PhotoAssetFileSystemError.notFound
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw mapped(error)
        }
    }

    public func removeItemIfExists(at url: URL) throws {
        guard fileExists(at: url) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw mapped(error)
        }
    }

    private func mapped(_ error: Error) -> PhotoAssetFileSystemError {
        let cocoa = error as NSError
        let protectedCodes = [
            CocoaError.Code.fileReadNoPermission.rawValue,
            CocoaError.Code.fileWriteNoPermission.rawValue,
        ]
        if cocoa.domain == NSCocoaErrorDomain,
           protectedCodes.contains(cocoa.code) {
            return .protectedDataUnavailable
        }
        if cocoa.domain == NSCocoaErrorDomain,
           cocoa.code == CocoaError.Code.fileNoSuchFile.rawValue {
            return .notFound
        }
        return .operationFailed
    }
}
