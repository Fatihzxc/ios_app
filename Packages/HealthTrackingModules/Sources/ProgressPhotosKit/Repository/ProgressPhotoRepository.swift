import Foundation

public enum ProgressPhotoRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicatePhotoIDs(id: UUID, count: Int)
    case photoIDCollision(id: UUID)
    case invalidPersistedPhoto(id: UUID)
    case invalidImageRef(id: UUID)
}

public enum ProgressPhotoRepositoryMutationError: Error, Equatable, Sendable {
    case photoNotFound(id: UUID)
    case stalePhoto(
        id: UUID,
        expectedUpdatedAt: Date,
        actualUpdatedAt: Date
    )
}

public enum ProgressPhotoRepositoryOperationError: Error, Equatable, Sendable {
    case loadFailed
    case saveFailed
    case metadataSaveFailedCleanupPending(assetID: String)
    case protectedDataUnavailable
    case assetDeleteFailed
    case deleteCompensationFailed
}

@MainActor
public protocol ProgressPhotoRepository: AnyObject {
    var pendingAssetCleanupIDs: [String] { get }
    func fetchPhotos() async throws -> [ProgressPhotoSnapshot]
    func importPhoto(
        _ input: ProgressPhotoInput,
        bytes: Data
    ) async throws -> ProgressPhotoSnapshot
    func thumbnail(assetID: String) async throws -> PhotoAssetLoadResult
    func deletePhoto(id: UUID, expectedUpdatedAt: Date) async throws
    func retryPendingAssetCleanup() async throws
}

@MainActor
public final class NoOpProgressPhotoRepository: ProgressPhotoRepository {
    public static let shared = NoOpProgressPhotoRepository()
    public var pendingAssetCleanupIDs: [String] { [] }

    private init() {}

    public func fetchPhotos() async throws -> [ProgressPhotoSnapshot] { [] }

    public func importPhoto(
        _ input: ProgressPhotoInput,
        bytes: Data
    ) async throws -> ProgressPhotoSnapshot {
        throw ProgressPhotoRepositoryOperationError.saveFailed
    }

    public func thumbnail(assetID: String) async throws -> PhotoAssetLoadResult {
        .missing
    }

    public func deletePhoto(id: UUID, expectedUpdatedAt: Date) async throws {}
    public func retryPendingAssetCleanup() async throws {}
}
