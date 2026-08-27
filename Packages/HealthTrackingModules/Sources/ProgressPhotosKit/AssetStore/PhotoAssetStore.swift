import Foundation

public struct PhotoAssetPolicy: Equatable, Sendable {
    public let maximumInputBytes: Int
    public let maximumPixelCount: Int
    public let fullMaximumDimension: Int
    public let thumbnailMaximumDimension: Int
    public let encodingQuality: Double

    public init(
        maximumInputBytes: Int,
        maximumPixelCount: Int,
        fullMaximumDimension: Int,
        thumbnailMaximumDimension: Int,
        encodingQuality: Double
    ) {
        precondition(maximumInputBytes > 0)
        precondition(maximumPixelCount > 0)
        precondition(fullMaximumDimension > 0)
        precondition(thumbnailMaximumDimension > 0)
        precondition((0...1).contains(encodingQuality))
        self.maximumInputBytes = maximumInputBytes
        self.maximumPixelCount = maximumPixelCount
        self.fullMaximumDimension = fullMaximumDimension
        self.thumbnailMaximumDimension = thumbnailMaximumDimension
        self.encodingQuality = encodingQuality
    }

    public static let production = PhotoAssetPolicy(
        maximumInputBytes: 25 * 1_024 * 1_024,
        maximumPixelCount: 40_000_000,
        fullMaximumDimension: 2_048,
        thumbnailMaximumDimension: 320,
        encodingQuality: 0.82
    )
}

public enum PhotoImageOrientation: Int, Equatable, Sendable {
    case up = 1
    case upMirrored = 2
    case down = 3
    case downMirrored = 4
    case leftMirrored = 5
    case right = 6
    case rightMirrored = 7
    case left = 8
}

public struct PhotoImageMetadata: Equatable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let orientation: PhotoImageOrientation

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        orientation: PhotoImageOrientation
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.orientation = orientation
    }
}

public struct PhotoEncodedImage: Equatable, Sendable {
    public let bytes: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let orientation: PhotoImageOrientation
    public let containsMetadata: Bool

    public init(
        bytes: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        orientation: PhotoImageOrientation,
        containsMetadata: Bool
    ) {
        self.bytes = bytes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.orientation = orientation
        self.containsMetadata = containsMetadata
    }
}

public struct PhotoNormalizedAsset: Equatable, Sendable {
    public let full: PhotoEncodedImage
    public let thumbnail: PhotoEncodedImage

    public init(full: PhotoEncodedImage, thumbnail: PhotoEncodedImage) {
        self.full = full
        self.thumbnail = thumbnail
    }
}

public enum PhotoImageProcessingError: Error, Equatable, Sendable {
    case corruptInput
    case encodingFailed
}

@MainActor
public protocol PhotoImageProcessing: AnyObject {
    func inspect(_ bytes: Data) throws -> PhotoImageMetadata
    func normalize(
        _ bytes: Data,
        metadata: PhotoImageMetadata,
        policy: PhotoAssetPolicy
    ) throws -> PhotoNormalizedAsset
}

public enum PhotoAssetFileSystemError: Error, Equatable, Sendable {
    case notFound
    case protectedDataUnavailable
    case operationFailed
}

@MainActor
public protocol PhotoAssetFileSystem: AnyObject {
    func applicationSupportDirectory() throws -> URL
    func createDirectory(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func write(_ data: Data, to url: URL) throws
    func applyCompleteProtection(to url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func data(at url: URL) throws -> Data
    func removeItemIfExists(at url: URL) throws
}

public struct PhotoAssetReference: Equatable, Sendable {
    public let assetID: String

    public init(assetID: String) {
        self.assetID = assetID
    }
}

public enum PhotoAssetVariant: Equatable, Sendable {
    case full
    case thumbnail
}

public enum PhotoAssetLoadResult: Equatable, Sendable {
    case available(Data)
    case missing
    case corrupt
}

public enum PhotoAssetStoreError: Error, Equatable, Sendable {
    case emptyInput
    case inputTooLarge(maximumBytes: Int)
    case pixelCountTooLarge(maximumPixels: Int)
    case corruptInput
    case invalidNormalizedOutput
    case invalidAssetID
    case assetIDCollision
    case protectedDataUnavailable
    case fileOperationFailed
}

@MainActor
public protocol PhotoAssetStoring: AnyObject {
    func importAsset(_ bytes: Data) async throws -> PhotoAssetReference
    func loadAsset(
        id: String,
        variant: PhotoAssetVariant
    ) async throws -> PhotoAssetLoadResult
    func deleteAsset(id: String) async throws
}
