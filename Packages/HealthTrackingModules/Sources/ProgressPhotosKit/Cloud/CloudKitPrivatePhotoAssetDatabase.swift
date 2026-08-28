@preconcurrency import CloudKit
import Foundation

public actor CloudKitPrivatePhotoAssetDatabase: PrivateCloudPhotoAssetDatabase {
    private let systemDatabase: any CloudPhotoAssetSystemDatabase
    private let accountIdentityProvider: any CloudPhotoAccountIdentityProviding
    private let downloadStore: FileCloudPhotoAssetTemporaryStore
    private let maximumAssetBytes: Int

    public init(containerIdentifier: String? = nil) {
        let container = Self.container(identifier: containerIdentifier)
        let transferRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent("CloudSync", isDirectory: true)
            .appendingPathComponent("Transfers", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                "ProgressPhotoCloudTransfers",
                isDirectory: true
            )
        systemDatabase = CloudKitPhotoAssetSystemDatabase(container: container)
        accountIdentityProvider = CloudKitPhotoAccountIdentityProvider(
            container: container
        )
        downloadStore = FileCloudPhotoAssetTemporaryStore(directory: transferRoot)
        maximumAssetBytes = PhotoAssetPolicy.production.maximumInputBytes
    }

    public init(
        containerIdentifier: String? = nil,
        downloadStore: FileCloudPhotoAssetTemporaryStore,
        maximumAssetBytes: Int = PhotoAssetPolicy.production.maximumInputBytes
    ) {
        precondition(maximumAssetBytes > 0)
        let container = Self.container(identifier: containerIdentifier)
        systemDatabase = CloudKitPhotoAssetSystemDatabase(container: container)
        accountIdentityProvider = CloudKitPhotoAccountIdentityProvider(
            container: container
        )
        self.downloadStore = downloadStore
        self.maximumAssetBytes = maximumAssetBytes
    }

    public init(
        containerIdentifier: String? = nil,
        systemDatabase: any CloudPhotoAssetSystemDatabase,
        accountIdentityProvider: any CloudPhotoAccountIdentityProviding,
        downloadStore: FileCloudPhotoAssetTemporaryStore,
        maximumAssetBytes: Int
    ) {
        precondition(maximumAssetBytes > 0)
        _ = containerIdentifier
        self.systemDatabase = systemDatabase
        self.accountIdentityProvider = accountIdentityProvider
        self.downloadStore = downloadStore
        self.maximumAssetBytes = maximumAssetBytes
    }

    public func accountStatus() async throws -> CloudPhotoAccountStatus {
        try await systemDatabase.accountStatus()
    }

    public func accountIdentity() async throws -> String {
        try await accountIdentityProvider.accountIdentity()
    }

    public func ensureZone(named zoneName: String) async throws {
        try await systemDatabase.ensureZone(named: zoneName)
    }

    public func record(
        named recordName: String,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata? {
        guard let record = try await systemDatabase.record(
            named: recordName,
            inZone: zoneName
        ), record.hasUsableBinaryAsset else { return nil }
        return record.metadata
    }

    public func save(
        _ request: CloudPhotoAssetUploadRequest,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata {
        try await systemDatabase.save(request, inZone: zoneName)
    }

    public func deleteRecord(
        named recordName: String,
        inZone zoneName: String
    ) async throws {
        try await systemDatabase.deleteRecord(named: recordName, inZone: zoneName)
    }

    public func fetchChanges(
        inZone zoneName: String,
        previousToken: Data?
    ) async throws -> CloudPhotoAssetChangePage {
        let page = try await systemDatabase.fetchSystemChanges(
            inZone: zoneName,
            previousToken: previousToken
        )
        var ownedURLs: [URL] = []
        do {
            let changes = try page.changes.map { change -> CloudPhotoAssetChange in
                switch change {
                case let .changed(record):
                    let owned = try withExtendedLifetime(record) {
                        try downloadStore.stageDownload(
                            recordName: record.recordName,
                            assetID: record.assetID,
                            checksum: record.checksum,
                            byteCount: record.byteCount,
                            systemFileURL: record.systemFileURL,
                            maximumBytes: maximumAssetBytes
                        )
                    }
                    ownedURLs.append(owned.stagedFileURL)
                    return .changed(owned)
                case let .deleted(recordName):
                    return .deleted(recordName: recordName)
                }
            }
            return CloudPhotoAssetChangePage(
                changes: changes,
                changeToken: page.changeToken,
                moreComing: page.moreComing
            )
        } catch {
            for url in ownedURLs {
                downloadStore.removeFile(at: url)
            }
            throw error
        }
    }

    private static func container(identifier: String?) -> CKContainer {
        if let identifier {
            return CKContainer(identifier: identifier)
        }
        return CKContainer.default()
    }
}

private actor CloudKitPhotoAccountIdentityProvider:
    CloudPhotoAccountIdentityProviding {
    private let container: CKContainer

    init(container: CKContainer) {
        self.container = container
    }

    func accountIdentity() async throws -> String {
        do {
            let recordID = try await container.userRecordID()
            return recordID.recordName
        } catch {
            throw CloudKitPhotoAssetErrorMapper.map(error)
        }
    }
}

struct CloudKitPhotoAssetRecordModifyResults: @unchecked Sendable {
    let saveResults: [CKRecord.ID: Result<CKRecord, Error>]
    let deleteResults: [CKRecord.ID: Result<Void, Error>]
}

protocol CloudKitPhotoAssetRecordModifying: Sendable {
    func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> CloudKitPhotoAssetRecordModifyResults
}

actor CloudKitPhotoAssetRecordSaver {
    private let recordModifier: any CloudKitPhotoAssetRecordModifying

    init(recordModifier: any CloudKitPhotoAssetRecordModifying) {
        self.recordModifier = recordModifier
    }

    func save(_ record: CKRecord) async throws -> CKRecord {
        let results = try await recordModifier.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        guard results.deleteResults.isEmpty,
              results.saveResults.count == 1,
              let recordResult = results.saveResults[record.recordID] else {
            throw CloudPhotoAssetSyncError.invalidServerResponse
        }
        return try recordResult.get()
    }
}

private actor CloudKitPhotoAssetDatabaseRecordModifier:
    CloudKitPhotoAssetRecordModifying {
    private let database: CKDatabase

    init(database: CKDatabase) {
        self.database = database
    }

    func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> CloudKitPhotoAssetRecordModifyResults {
        let results = try await database.modifyRecords(
            saving: records,
            deleting: recordIDs,
            savePolicy: savePolicy,
            atomically: atomically
        )
        return CloudKitPhotoAssetRecordModifyResults(
            saveResults: results.saveResults,
            deleteResults: results.deleteResults
        )
    }
}

private actor CloudKitPhotoAssetSystemDatabase: CloudPhotoAssetSystemDatabase {
    private let container: CKContainer
    private let database: CKDatabase
    private let recordSaver: CloudKitPhotoAssetRecordSaver

    init(container: CKContainer) {
        self.container = container
        let privateDatabase = container.privateCloudDatabase
        database = privateDatabase
        recordSaver = CloudKitPhotoAssetRecordSaver(
            recordModifier: CloudKitPhotoAssetDatabaseRecordModifier(
                database: privateDatabase
            )
        )
    }

    func accountStatus() async throws -> CloudPhotoAccountStatus {
        switch try await container.accountStatus() {
        case .available:
            return .available
        case .restricted:
            return .restricted
        case .noAccount:
            return .noAccount
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        case .couldNotDetermine:
            return .couldNotDetermine
        @unknown default:
            return .couldNotDetermine
        }
    }

    func ensureZone(named zoneName: String) async throws {
        do {
            _ = try await database.save(
                CKRecordZone(zoneID: zoneID(named: zoneName))
            )
        } catch {
            throw CloudKitPhotoAssetErrorMapper.map(error)
        }
    }

    func record(
        named recordName: String,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetSystemRecord? {
        do {
            let record = try await database.record(
                for: recordID(named: recordName, zoneName: zoneName)
            )
            return try CloudKitPhotoAssetRecordMapper.systemRecord(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw CloudKitPhotoAssetErrorMapper.map(error)
        }
    }

    func save(
        _ request: CloudPhotoAssetUploadRequest,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata {
        let record = CloudKitPhotoAssetRecordMapper.uploadRecord(
            from: request,
            zoneID: zoneID(named: zoneName)
        )
        do {
            let savedRecord = try await saveRetainingAssetRecord(record)
            return try CloudKitPhotoAssetRecordMapper.metadata(from: savedRecord)
        } catch {
            throw CloudKitPhotoAssetErrorMapper.map(error)
        }
    }

    private func saveRetainingAssetRecord(_ record: CKRecord) async throws -> CKRecord {
        defer { withExtendedLifetime(record) {} }
        return try await recordSaver.save(record)
    }

    func deleteRecord(
        named recordName: String,
        inZone zoneName: String
    ) async throws {
        do {
            _ = try await database.deleteRecord(
                withID: recordID(named: recordName, zoneName: zoneName)
            )
        } catch {
            throw CloudKitPhotoAssetErrorMapper.map(error)
        }
    }

    func fetchSystemChanges(
        inZone zoneName: String,
        previousToken: Data?
    ) async throws -> CloudPhotoAssetSystemChangePage {
        let token = try decodeToken(previousToken)
        do {
            let result = try await database.recordZoneChanges(
                inZoneWith: zoneID(named: zoneName),
                since: token,
                desiredKeys: CloudPhotoAssetRecordContract.fieldNames,
                resultsLimit: 200
            )
            var changes: [CloudPhotoAssetSystemChange] = []
            for (_, modificationResult) in result.modificationResultsByID.sorted(
                by: { $0.key.recordName < $1.key.recordName }
            ) {
                do {
                    let record = try modificationResult.get().record
                    guard record.recordType
                        == CloudPhotoAssetRecordContract.recordType else {
                        continue
                    }
                    changes.append(.changed(try downloadRecord(from: record)))
                } catch {
                    throw CloudKitPhotoAssetErrorMapper.map(error)
                }
            }
            for deletion in result.deletions.sorted(
                by: { $0.recordID.recordName < $1.recordID.recordName }
            ) where deletion.recordType == CloudPhotoAssetRecordContract.recordType {
                changes.append(.deleted(recordName: deletion.recordID.recordName))
            }
            return CloudPhotoAssetSystemChangePage(
                changes: changes,
                changeToken: try encodeToken(result.changeToken),
                moreComing: result.moreComing
            )
        } catch {
            throw CloudKitPhotoAssetErrorMapper.map(error)
        }
    }

    private func downloadRecord(
        from record: CKRecord
    ) throws -> CloudPhotoAssetSystemDownloadRecord {
        let metadata = try CloudKitPhotoAssetRecordMapper.metadata(from: record)
        guard let asset = record["asset"] as? CKAsset,
              let systemFileURL = asset.fileURL else {
            throw CloudPhotoAssetContractError.invalidRecordMetadata
        }
        return try CloudPhotoAssetSystemDownloadRecord(
            recordName: metadata.recordName,
            assetID: metadata.assetID,
            checksum: metadata.checksum,
            byteCount: metadata.byteCount,
            systemFileURL: systemFileURL,
            lifetimeOwner: asset
        )
    }

    private func zoneID(named zoneName: String) -> CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    private func recordID(
        named recordName: String,
        zoneName: String
    ) -> CKRecord.ID {
        CKRecord.ID(
            recordName: recordName,
            zoneID: zoneID(named: zoneName)
        )
    }

    private func encodeToken(_ token: CKServerChangeToken) throws -> Data {
        try NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        )
    }

    private func decodeToken(_ data: Data?) throws -> CKServerChangeToken? {
        guard let data else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: data
            )
        } catch {
            throw CloudPhotoAssetDatabaseError.changeTokenExpired
        }
    }
}

enum CloudKitPhotoAssetRecordMapper {
    static func uploadRecord(
        from request: CloudPhotoAssetUploadRequest,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: CloudPhotoAssetRecordContract.recordType,
            recordID: CKRecord.ID(
                recordName: request.recordName,
                zoneID: zoneID
            )
        )
        record["assetID"] = request.assetID as CKRecordValue
        record["asset"] = CKAsset(fileURL: request.fileURL)
        record["checksum"] = request.checksum as CKRecordValue
        record["byteCount"] = NSNumber(value: request.byteCount)
        return record
    }

    static func systemRecord(
        from record: CKRecord
    ) throws -> CloudPhotoAssetSystemRecord {
        CloudPhotoAssetSystemRecord(
            metadata: try metadata(from: record),
            hasUsableBinaryAsset: hasUsableBinaryAsset(in: record)
        )
    }

    static func metadata(
        from record: CKRecord
    ) throws -> CloudPhotoAssetRecordMetadata {
        guard record.recordType == CloudPhotoAssetRecordContract.recordType,
              let assetID = record["assetID"] as? String,
              let checksum = record["checksum"] as? String,
              let byteCount = record["byteCount"] as? NSNumber,
              byteCount.int64Value >= 0,
              byteCount.int64Value <= Int64(Int.max) else {
            throw CloudPhotoAssetContractError.invalidRecordMetadata
        }
        return try CloudPhotoAssetRecordMetadata(
            recordName: record.recordID.recordName,
            assetID: assetID,
            checksum: checksum,
            byteCount: byteCount.intValue
        )
    }

    private static func hasUsableBinaryAsset(in record: CKRecord) -> Bool {
        guard let asset = record["asset"] as? CKAsset,
              let fileURL = asset.fileURL,
              fileURL.isFileURL,
              let resourceValues = try? fileURL.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isReadableKey,
                    .isSymbolicLinkKey,
                ]
              ),
              resourceValues.isRegularFile == true,
              resourceValues.isReadable == true,
              resourceValues.isSymbolicLink != true else {
            return false
        }
        return true
    }
}

private enum CloudKitPhotoAssetErrorMapper {
    static func map(_ error: Error) -> Error {
        if error is CancellationError { return CancellationError() }
        if let known = error as? CloudPhotoAssetDatabaseError { return known }
        guard let cloudError = error as? CKError else {
            return CloudPhotoAssetDatabaseError.permanent
        }
        switch cloudError.code {
        case .changeTokenExpired:
            return CloudPhotoAssetDatabaseError.changeTokenExpired
        case .unknownItem:
            return CloudPhotoAssetDatabaseError.recordNotFound
        case .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .requestRateLimited,
             .zoneBusy,
             .serverResponseLost,
             .accountTemporarilyUnavailable:
            return CloudPhotoAssetDatabaseError.retryable(
                retryAfter: cloudError.retryAfterSeconds
            )
        default:
            return CloudPhotoAssetDatabaseError.permanent
        }
    }
}
