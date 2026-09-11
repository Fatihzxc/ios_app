import CryptoKit
import Foundation

public struct ExportManifestIntervalV1: Codable, Equatable, Sendable {
    public let start: String
    public let endExclusive: String
}

public struct ExportManifestPayloadV1: Codable, Equatable, Sendable {
    public let relativePath: String
    public let byteSize: UInt64
    public let sha256: String
    public let mediaType: String
}

public enum ExportManifestPhotoStatusV1: String, Codable, Equatable, Sendable {
    case included
    case missing
    case corrupt
}

public struct ExportManifestPhotoV1: Codable, Equatable, Sendable {
    public let photoID: String
    public let status: ExportManifestPhotoStatusV1
    public let relativePath: String?

    public init(
        photoID: String,
        status: ExportManifestPhotoStatusV1,
        relativePath: String? = nil
    ) {
        self.photoID = photoID
        self.status = status
        self.relativePath = relativePath
    }
}

public struct ExportManifestV1: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let interval: ExportManifestIntervalV1
    public let selectedModules: [String]
    public let format: String
    public let includesPhotos: Bool
    public let payloads: [ExportManifestPayloadV1]
    public let photos: [ExportManifestPhotoV1]

    public init(
        interval: ExportManifestIntervalV1,
        selectedModules: [String],
        format: String,
        includesPhotos: Bool,
        payloads: [ExportManifestPayloadV1],
        photos: [ExportManifestPhotoV1]
    ) {
        schemaVersion = 1
        self.interval = interval
        self.selectedModules = selectedModules
        self.format = format
        self.includesPhotos = includesPhotos
        self.payloads = payloads.sorted { $0.relativePath < $1.relativePath }
        self.photos = photos.sorted { $0.photoID < $1.photoID }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

enum ReportExportSHA256 {
    static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
