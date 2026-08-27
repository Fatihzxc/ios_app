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
    public var accountIdentity: String?
    public var pendingUploadAssetIDs: [String]
    public var pendingDeletionAssetIDs: [String]
    public var uploadedAssetIDs: [String]
    public var changeToken: Data?
    var requiresLegacyAccountReset: Bool

    public init(
        accountIdentity: String? = nil,
        pendingUploadAssetIDs: [String] = [],
        pendingDeletionAssetIDs: [String] = [],
        uploadedAssetIDs: [String] = [],
        changeToken: Data? = nil
    ) {
        self.accountIdentity = accountIdentity
        self.pendingUploadAssetIDs = pendingUploadAssetIDs
        self.pendingDeletionAssetIDs = pendingDeletionAssetIDs
        self.uploadedAssetIDs = uploadedAssetIDs
        self.changeToken = changeToken
        requiresLegacyAccountReset = false
    }

    public static let empty = CloudPhotoAssetSyncState()

    private enum CodingKeys: String, CodingKey {
        case accountIdentity
        case pendingUploadAssetIDs
        case pendingDeletionAssetIDs
        case uploadedAssetIDs
        case changeToken
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .accountIdentity
        )
        pendingUploadAssetIDs = try container.decode(
            [String].self,
            forKey: .pendingUploadAssetIDs
        )
        pendingDeletionAssetIDs = try container.decode(
            [String].self,
            forKey: .pendingDeletionAssetIDs
        )
        uploadedAssetIDs = try container.decode(
            [String].self,
            forKey: .uploadedAssetIDs
        )
        changeToken = try container.decodeIfPresent(Data.self, forKey: .changeToken)
        requiresLegacyAccountReset = !container.contains(.accountIdentity)
            || accountIdentity == nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(accountIdentity, forKey: .accountIdentity)
        try container.encode(pendingUploadAssetIDs, forKey: .pendingUploadAssetIDs)
        try container.encode(pendingDeletionAssetIDs, forKey: .pendingDeletionAssetIDs)
        try container.encode(uploadedAssetIDs, forKey: .uploadedAssetIDs)
        try container.encodeIfPresent(changeToken, forKey: .changeToken)
    }
}

public struct CloudPhotoAssetReferenceSnapshot: Equatable, Sendable {
    public let referencedAssetIDs: Set<String>

    public init(referencedAssetIDs: Set<String>) {
        self.referencedAssetIDs = referencedAssetIDs
    }
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

public struct CloudPhotoAssetSystemRecord: Equatable, Sendable {
    public let metadata: CloudPhotoAssetRecordMetadata
    public let hasUsableBinaryAsset: Bool

    public init(
        metadata: CloudPhotoAssetRecordMetadata,
        hasUsableBinaryAsset: Bool
    ) {
        self.metadata = metadata
        self.hasUsableBinaryAsset = hasUsableBinaryAsset
    }
}

final class CloudPhotoAssetSystemFileLifetimeLease: @unchecked Sendable {
    private let owner: AnyObject

    init(retaining owner: AnyObject) {
        self.owner = owner
    }
}

public struct CloudPhotoAssetSystemDownloadRecord: Equatable, Sendable {
    public let recordName: String
    public let assetID: String
    public let checksum: String
    public let byteCount: Int
    public let systemFileURL: URL
    private let lifetimeLease: CloudPhotoAssetSystemFileLifetimeLease?

    public init(
        recordName: String,
        assetID: String,
        checksum: String,
        byteCount: Int,
        systemFileURL: URL
    ) throws {
        try self.init(
            recordName: recordName,
            assetID: assetID,
            checksum: checksum,
            byteCount: byteCount,
            systemFileURL: systemFileURL,
            lifetimeLease: nil
        )
    }

    init(
        recordName: String,
        assetID: String,
        checksum: String,
        byteCount: Int,
        systemFileURL: URL,
        lifetimeOwner: AnyObject
    ) throws {
        try self.init(
            recordName: recordName,
            assetID: assetID,
            checksum: checksum,
            byteCount: byteCount,
            systemFileURL: systemFileURL,
            lifetimeLease: CloudPhotoAssetSystemFileLifetimeLease(
                retaining: lifetimeOwner
            )
        )
    }

    private init(
        recordName: String,
        assetID: String,
        checksum: String,
        byteCount: Int,
        systemFileURL: URL,
        lifetimeLease: CloudPhotoAssetSystemFileLifetimeLease?
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
        self.systemFileURL = systemFileURL
        self.lifetimeLease = lifetimeLease
    }

    public static func == (
        lhs: CloudPhotoAssetSystemDownloadRecord,
        rhs: CloudPhotoAssetSystemDownloadRecord
    ) -> Bool {
        lhs.recordName == rhs.recordName
            && lhs.assetID == rhs.assetID
            && lhs.checksum == rhs.checksum
            && lhs.byteCount == rhs.byteCount
            && lhs.systemFileURL == rhs.systemFileURL
    }
}

public enum CloudPhotoAssetSystemChange: Equatable, Sendable {
    case changed(CloudPhotoAssetSystemDownloadRecord)
    case deleted(recordName: String)
}

public struct CloudPhotoAssetSystemChangePage: Equatable, Sendable {
    public let changes: [CloudPhotoAssetSystemChange]
    public let changeToken: Data
    public let moreComing: Bool

    public init(
        changes: [CloudPhotoAssetSystemChange],
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

public protocol CloudPhotoAssetReferenceSnapshotProviding: Sendable {
    func snapshot() async throws -> CloudPhotoAssetReferenceSnapshot
}

public struct CloudPhotoAssetInboundApplyLease: Equatable, Sendable {
    public let assetID: String
    public let accountIdentity: String
    let leaseID: UUID

    public init(assetID: String, accountIdentity: String) {
        self.assetID = assetID
        self.accountIdentity = accountIdentity
        leaseID = UUID()
    }
}

public enum CloudPhotoAssetInboundApplyPreparation: Equatable, Sendable {
    case prepared(CloudPhotoAssetInboundApplyLease)
    case discardedCommittedDeletion
}

public protocol CloudPhotoAssetInboundApplying: Sendable {
    func prepareInboundApply(
        id assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws -> CloudPhotoAssetInboundApplyPreparation
    func commitInboundApply(
        _ lease: CloudPhotoAssetInboundApplyLease,
        bytes: Data
    ) async throws
    func cancelInboundApply(_ lease: CloudPhotoAssetInboundApplyLease) async
}

public struct CloudPhotoAssetDeletionIntentReceipt: Equatable, Sendable {
    public let intentID: UUID
    public let assetID: String
    public let accountIdentity: String?
    public let quarantineIdentityHint: String?

    public init(
        assetID: String,
        accountIdentity: String?,
        quarantineIdentityHint: String? = nil,
        intentID: UUID = UUID()
    ) {
        self.intentID = intentID
        self.assetID = assetID
        self.accountIdentity = accountIdentity
        self.quarantineIdentityHint = quarantineIdentityHint
    }
}

public struct CloudPhotoAssetAccountAuthorization: Equatable, Sendable {
    public let accountIdentity: String
    let authorizationID: UUID

    public init(accountIdentity: String) {
        self.accountIdentity = accountIdentity
        authorizationID = UUID()
    }
}

public struct CloudPhotoAssetAccountResolution: Equatable, Sendable {
    let resolutionID: UUID

    public init() {
        resolutionID = UUID()
    }
}

public struct CloudPhotoAssetInboundCleanupLease: Equatable, Sendable {
    public let assetID: String
    let leaseID: UUID

    public init(assetID: String) {
        self.assetID = assetID
        leaseID = UUID()
    }
}

public protocol CloudPhotoAssetDeletionIntentStoring: Sendable {
    func beginAccountResolution() async -> CloudPhotoAssetAccountResolution
    func activateAccountIdentity(
        _ accountIdentity: String,
        resolution: CloudPhotoAssetAccountResolution
    ) async throws -> CloudPhotoAssetAccountAuthorization
    func suspendAccountAuthorization(_ authorization: CloudPhotoAssetAccountAuthorization) async
    func pendingDeletionIntents(
        forAccountIdentity accountIdentity: String
    ) async throws -> [CloudPhotoAssetDeletionIntentReceipt]
    func pendingDeletionAssetIDs(
        forAccountIdentity accountIdentity: String
    ) async throws -> Set<String>
    func unresolvedDeletionAssetIDs() async throws -> Set<String>
    func hasCommittedLocalDeletionIntent(assetID: String) async throws -> Bool
    func recordCommittedDeletion(
        assetID: String
    ) async throws -> CloudPhotoAssetDeletionIntentReceipt
    func clearCommittedDeletion(
        _ intent: CloudPhotoAssetDeletionIntentReceipt
    ) async throws
    func clearCommittedDeletion(
        assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws
}

public protocol CloudPhotoAssetInboundJournaling: Sendable {
    func pendingInboundAssetIDs() async throws -> Set<String>
    func acquireCleanupLease(for assetID: String) async throws
        -> CloudPhotoAssetInboundCleanupLease?
    func releaseCleanupLease(_ lease: CloudPhotoAssetInboundCleanupLease) async
    func recordInboundAssetID(_ assetID: String) async throws
    func clearInboundAssetID(_ assetID: String) async throws
}

public protocol CloudPhotoAssetReadHandling: Sendable {
    func read(upToCount count: Int) throws -> Data?
    func close() throws
}

public protocol CloudPhotoAssetWriteHandling: Sendable {
    func write(contentsOf data: Data) throws
    func close() throws
}

public protocol CloudPhotoAssetFileHandleOpening: Sendable {
    func openForReading(at sourceURL: URL) throws -> any CloudPhotoAssetReadHandling
    func openForWriting(at destinationURL: URL) throws -> any CloudPhotoAssetWriteHandling
}

public protocol CloudPhotoAssetLocalStoring: Sendable {
    func storedAssetIDs() async throws -> Set<String>
    func usableCloudAssetIDs() async throws -> Set<String>
    func cloudAssetBytes(id: String) async throws -> Data?
    func restoreCloudAsset(id: String, bytes: Data) async throws
    func deleteCloudAsset(id: String) async throws
}

public protocol PrivateCloudPhotoAssetDatabase: Sendable {
    func accountStatus() async throws -> CloudPhotoAccountStatus
    func accountIdentity() async throws -> String
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

public protocol CloudPhotoAccountIdentityProviding: Sendable {
    func accountIdentity() async throws -> String
}

public protocol CloudPhotoAssetSystemDatabase: Sendable {
    func accountStatus() async throws -> CloudPhotoAccountStatus
    func ensureZone(named zoneName: String) async throws
    func record(
        named recordName: String,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetSystemRecord?
    func save(
        _ request: CloudPhotoAssetUploadRequest,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata
    func deleteRecord(
        named recordName: String,
        inZone zoneName: String
    ) async throws
    func fetchSystemChanges(
        inZone zoneName: String,
        previousToken: Data?
    ) async throws -> CloudPhotoAssetSystemChangePage
}

public protocol CloudPhotoAssetSynchronizing: Sendable {
    func synchronize() async throws -> CloudPhotoAssetSyncOutcome
}
