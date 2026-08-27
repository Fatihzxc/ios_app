import CryptoKit
import Foundation

public enum CloudPhotoAssetRecordContract {
    public static let zoneName = "ProgressPhotoAssetsZone"
    public static let recordType = "ProgressPhotoAsset"
    public static let fieldNames = [
        "assetID",
        "asset",
        "checksum",
        "byteCount",
    ]

    private static let recordNamePrefix = "progress-photo-asset-"

    public static func recordName(for assetID: String) throws -> String {
        let canonicalID = try canonicalAssetID(assetID)
        return recordNamePrefix + canonicalID
    }

    public static func assetID(fromRecordName recordName: String) throws -> String {
        guard recordName.hasPrefix(recordNamePrefix) else {
            throw CloudPhotoAssetContractError.invalidRecordName
        }
        let candidate = String(recordName.dropFirst(recordNamePrefix.count))
        let canonicalID = try canonicalAssetID(candidate)
        guard recordName == recordNamePrefix + canonicalID else {
            throw CloudPhotoAssetContractError.invalidRecordName
        }
        return canonicalID
    }

    public static func canonicalAssetID(_ assetID: String) throws -> String {
        guard !assetID.isEmpty,
              !assetID.contains("/"),
              !assetID.contains("\\"),
              !assetID.contains(":"),
              let identifier = UUID(uuidString: assetID) else {
            throw CloudPhotoAssetContractError.invalidAssetID
        }
        let canonicalID = identifier.uuidString.lowercased()
        guard assetID.lowercased() == canonicalID else {
            throw CloudPhotoAssetContractError.invalidAssetID
        }
        return canonicalID
    }
}

public enum CloudPhotoAssetContractError: Error, Equatable, Sendable {
    case invalidAssetID
    case invalidRecordName
    case invalidRecordMetadata
}

public enum CloudPhotoAssetValidationError: Error, Equatable, Sendable {
    case byteCountMismatch(expected: Int, actual: Int)
    case checksumMismatch
    case exceedsMaximumBytes(maximumBytes: Int)
}

public enum CloudPhotoAssetChecksum {
    public static func sha256Hex(_ bytes: Data) -> String {
        SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func validate(
        _ bytes: Data,
        expectedChecksum: String,
        expectedByteCount: Int,
        maximumBytes: Int
    ) throws {
        guard bytes.count <= maximumBytes else {
            throw CloudPhotoAssetValidationError.exceedsMaximumBytes(
                maximumBytes: maximumBytes
            )
        }
        guard bytes.count == expectedByteCount else {
            throw CloudPhotoAssetValidationError.byteCountMismatch(
                expected: expectedByteCount,
                actual: bytes.count
            )
        }
        guard sha256Hex(bytes) == expectedChecksum else {
            throw CloudPhotoAssetValidationError.checksumMismatch
        }
    }
}

public enum CloudPhotoAccountStatus: Equatable, Sendable {
    case available
    case restricted
    case noAccount
    case temporarilyUnavailable
    case couldNotDetermine
}

public enum CloudPhotoAssetSyncOutcome: Equatable, Sendable {
    case synchronized
    case deferred(CloudPhotoAccountStatus)
}

public struct CloudPhotoAssetSyncState: Codable, Equatable, Sendable {
    public var pendingUploadAssetIDs: [String]
    public var pendingDeletionAssetIDs: [String]
    public var uploadedAssetIDs: [String]
    public var changeToken: Data?

    public init(
        pendingUploadAssetIDs: [String] = [],
        pendingDeletionAssetIDs: [String] = [],
        uploadedAssetIDs: [String] = [],
        changeToken: Data? = nil
    ) {
        self.pendingUploadAssetIDs = pendingUploadAssetIDs
        self.pendingDeletionAssetIDs = pendingDeletionAssetIDs
        self.uploadedAssetIDs = uploadedAssetIDs
        self.changeToken = changeToken
    }

    public static let empty = CloudPhotoAssetSyncState()
}

public struct CloudPhotoAssetRecordMetadata: Equatable, Sendable {
    public let recordName: String
    public let assetID: String
    public let checksum: String
    public let byteCount: Int

    public init(
        recordName: String,
        assetID: String,
        checksum: String,
        byteCount: Int
    ) throws {
        let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
        guard recordName == (try CloudPhotoAssetRecordContract.recordName(for: canonicalID)),
              Self.isValidChecksum(checksum),
              byteCount >= 0 else {
            throw CloudPhotoAssetContractError.invalidRecordMetadata
        }
        self.recordName = recordName
        self.assetID = canonicalID
        self.checksum = checksum
        self.byteCount = byteCount
    }

    private static func isValidChecksum(_ checksum: String) -> Bool {
        let hexadecimalCharacters = Set("0123456789abcdef")
        return checksum.count == 64
            && checksum.allSatisfy(hexadecimalCharacters.contains)
    }
}

public struct CloudPhotoAssetUploadRequest: Equatable, Sendable {
    public let recordName: String
    public let assetID: String
    public let checksum: String
    public let byteCount: Int
    public let fileURL: URL

    public init(
        recordName: String,
        assetID: String,
        checksum: String,
        byteCount: Int,
        fileURL: URL
    ) throws {
        let metadata = try CloudPhotoAssetRecordMetadata(
            recordName: recordName,
            assetID: assetID,
            checksum: checksum,
            byteCount: byteCount
        )
        self.recordName = metadata.recordName
        self.assetID = metadata.assetID
        self.checksum = metadata.checksum
        self.byteCount = metadata.byteCount
        self.fileURL = fileURL
    }
}

public struct CloudPhotoAssetDownloadRecord: Equatable, Sendable {
    public let recordName: String
    public let assetID: String
    public let checksum: String
    public let byteCount: Int
    public let stagedFileURL: URL

    public init(
        recordName: String,
        assetID: String,
        checksum: String,
        byteCount: Int,
        stagedFileURL: URL
    ) throws {
        let metadata = try CloudPhotoAssetRecordMetadata(
            recordName: recordName,
            assetID: assetID,
            checksum: checksum,
            byteCount: byteCount
        )
        self.recordName = metadata.recordName
        self.assetID = metadata.assetID
        self.checksum = metadata.checksum
        self.byteCount = metadata.byteCount
        self.stagedFileURL = stagedFileURL
    }
}

public enum CloudPhotoAssetChange: Equatable, Sendable {
    case changed(CloudPhotoAssetDownloadRecord)
    case deleted(recordName: String)
}

public struct CloudPhotoAssetChangePage: Equatable, Sendable {
    public let changes: [CloudPhotoAssetChange]
    public let changeToken: Data
    public let moreComing: Bool

    public init(
        changes: [CloudPhotoAssetChange],
        changeToken: Data,
        moreComing: Bool
    ) {
        self.changes = changes
        self.changeToken = changeToken
        self.moreComing = moreComing
    }
}

public enum CloudPhotoAssetDatabaseError: Error, Equatable, Sendable {
    case retryable(retryAfter: TimeInterval?)
    case changeTokenExpired
    case recordNotFound
    case permanent
}

public struct CloudPhotoAssetRetryPolicy: Equatable, Sendable {
    public let maximumAttempts: Int
    public let baseDelay: TimeInterval
    public let maximumDelay: TimeInterval

    public init(
        maximumAttempts: Int = 3,
        baseDelay: TimeInterval = 1,
        maximumDelay: TimeInterval = 30
    ) {
        precondition(maximumAttempts > 0)
        precondition(baseDelay >= 0)
        precondition(maximumDelay >= baseDelay)
        self.maximumAttempts = maximumAttempts
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
    }

    func delay(afterFailedAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter {
            return min(max(0, retryAfter), maximumDelay)
        }
        return min(baseDelay * pow(2, Double(attempt - 1)), maximumDelay)
    }
}

public enum CloudPhotoAssetSyncError: Error, Equatable, Sendable {
    case invalidServerResponse
}

public protocol CloudPhotoAssetSyncStateStoring: Sendable {
    func load() async throws -> CloudPhotoAssetSyncState
    func save(_ state: CloudPhotoAssetSyncState) async throws
}

public protocol CloudPhotoAssetLocalStoring: Sendable {
    func storedAssetIDs() async throws -> Set<String>
    func cloudAssetBytes(id: String) async throws -> Data?
    func restoreCloudAsset(id: String, bytes: Data) async throws
    func deleteCloudAsset(id: String) async throws
}

public protocol PrivateCloudPhotoAssetDatabase: Sendable {
    func accountStatus() async throws -> CloudPhotoAccountStatus
    func ensureZone(named zoneName: String) async throws
    func record(
        named recordName: String,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata?
    func save(
        _ request: CloudPhotoAssetUploadRequest,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata
    func deleteRecord(
        named recordName: String,
        inZone zoneName: String
    ) async throws
    func fetchChanges(
        inZone zoneName: String,
        previousToken: Data?
    ) async throws -> CloudPhotoAssetChangePage
}

public protocol CloudPhotoAssetSynchronizing: Sendable {
    func synchronize() async throws -> CloudPhotoAssetSyncOutcome
}
