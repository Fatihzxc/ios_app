@preconcurrency import CloudKit
import Foundation

public actor CloudKitPrivatePhotoAssetDatabase: PrivateCloudPhotoAssetDatabase {
    private let container: CKContainer
    private let database: CKDatabase

    public init(containerIdentifier: String? = nil) {
        let resolvedContainer: CKContainer
        if let containerIdentifier {
            resolvedContainer = CKContainer(identifier: containerIdentifier)
        } else {
            resolvedContainer = CKContainer.default()
        }
        container = resolvedContainer
        database = resolvedContainer.privateCloudDatabase
    }

    public func accountStatus() async throws -> CloudPhotoAccountStatus {
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

    public func ensureZone(named zoneName: String) async throws {
        do {
            _ = try await database.save(
                CKRecordZone(zoneID: zoneID(named: zoneName))
            )
        } catch {
            throw map(error)
        }
    }

    public func record(
        named recordName: String,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata? {
        do {
            let record = try await database.record(
                for: recordID(named: recordName, zoneName: zoneName)
            )
            return try metadata(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw map(error)
        }
    }

    public func save(
        _ request: CloudPhotoAssetUploadRequest,
        inZone zoneName: String
    ) async throws -> CloudPhotoAssetRecordMetadata {
        let record = CKRecord(
            recordType: CloudPhotoAssetRecordContract.recordType,
            recordID: recordID(named: request.recordName, zoneName: zoneName)
        )
        record["assetID"] = request.assetID as CKRecordValue
        record["asset"] = CKAsset(fileURL: request.fileURL)
        record["checksum"] = request.checksum as CKRecordValue
        record["byteCount"] = NSNumber(value: request.byteCount)
        do {
            let savedRecord = try await database.save(record)
            return try metadata(from: savedRecord)
        } catch {
            throw map(error)
        }
    }

    public func deleteRecord(
        named recordName: String,
        inZone zoneName: String
    ) async throws {
        do {
            _ = try await database.deleteRecord(
                withID: recordID(named: recordName, zoneName: zoneName)
            )
        } catch {
            throw map(error)
        }
    }

    public func fetchChanges(
        inZone zoneName: String,
        previousToken: Data?
    ) async throws -> CloudPhotoAssetChangePage {
        let token = try decodeToken(previousToken)
        do {
            let result = try await database.recordZoneChanges(
                inZoneWith: zoneID(named: zoneName),
                since: token,
                desiredKeys: CloudPhotoAssetRecordContract.fieldNames,
                resultsLimit: 200
            )
            var changes: [CloudPhotoAssetChange] = []
            for (_, modificationResult) in result.modificationResultsByID.sorted(
                by: { $0.key.recordName < $1.key.recordName }
            ) {
                do {
                    let record = try modificationResult.get().record
                    guard record.recordType == CloudPhotoAssetRecordContract.recordType else {
                        continue
                    }
                    changes.append(.changed(try downloadRecord(from: record)))
                } catch {
                    throw map(error)
                }
            }
            for deletion in result.deletions.sorted(
                by: { $0.recordID.recordName < $1.recordID.recordName }
            ) where deletion.recordType == CloudPhotoAssetRecordContract.recordType {
                changes.append(.deleted(recordName: deletion.recordID.recordName))
            }
            return CloudPhotoAssetChangePage(
                changes: changes,
                changeToken: try encodeToken(result.changeToken),
                moreComing: result.moreComing
            )
        } catch {
            throw map(error)
        }
    }

    private func metadata(from record: CKRecord) throws -> CloudPhotoAssetRecordMetadata {
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

    private func downloadRecord(from record: CKRecord) throws -> CloudPhotoAssetDownloadRecord {
        let metadata = try metadata(from: record)
        guard let asset = record["asset"] as? CKAsset,
              let stagedFileURL = asset.fileURL else {
            throw CloudPhotoAssetContractError.invalidRecordMetadata
        }
        return try CloudPhotoAssetDownloadRecord(
            recordName: metadata.recordName,
            assetID: metadata.assetID,
            checksum: metadata.checksum,
            byteCount: metadata.byteCount,
            stagedFileURL: stagedFileURL
        )
    }

    private func zoneID(named zoneName: String) -> CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    private func recordID(named recordName: String, zoneName: String) -> CKRecord.ID {
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

    private func map(_ error: Error) -> Error {
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
