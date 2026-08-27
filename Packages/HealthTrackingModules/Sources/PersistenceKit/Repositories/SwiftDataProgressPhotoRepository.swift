import CoreModels
import Foundation
import ProgressPhotosKit
import SwiftData

@MainActor
public final class SwiftDataProgressPhotoRepository: ProgressPhotoRepository {
    private let modelContext: ModelContext
    private let assetStore: any PhotoAssetStoring
    private let now: @MainActor () -> Date
    private let makeID: @MainActor () -> UUID
    private let saveOperation: @MainActor () throws -> Void
    private let rollbackOperation: @MainActor () -> Void
    private var pendingCleanup = Set<String>()

    public var pendingAssetCleanupIDs: [String] {
        pendingCleanup.sorted()
    }

    public init(
        modelContext: ModelContext,
        assetStore: any PhotoAssetStoring,
        now: @escaping @MainActor () -> Date = { .now },
        makeID: @escaping @MainActor () -> UUID = { UUID() },
        save: (@MainActor () throws -> Void)? = nil,
        rollback: (@MainActor () -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.assetStore = assetStore
        self.now = now
        self.makeID = makeID
        saveOperation = save ?? { try modelContext.save() }
        rollbackOperation = rollback ?? { modelContext.rollback() }
    }

    public func fetchPhotos() async throws -> [ProgressPhotoSnapshot] {
        try validatedRows().map(\.snapshot)
            .sorted(by: ProgressPhotoOrdering.newestFirst)
    }

    public func importPhoto(
        _ input: ProgressPhotoInput,
        bytes: Data
    ) async throws -> ProgressPhotoSnapshot {
        let existing = try validatedRows()
        let id = makeID()
        guard !existing.contains(where: { $0.model.id == id }) else {
            throw ProgressPhotoRepositoryIntegrityError.photoIDCollision(id: id)
        }

        let reference = try await assetStore.importAsset(bytes)
        guard isOpaquePhotoAssetID(reference.assetID) else {
            try? await assetStore.deleteAsset(id: reference.assetID)
            throw ProgressPhotoRepositoryIntegrityError.invalidImageRef(id: id)
        }
        let timestamp = now()
        let model = ProgressPhoto(
            id: id,
            createdAt: timestamp,
            updatedAt: timestamp,
            date: input.date,
            imageRef: reference.assetID,
            pose: input.pose,
            note: input.note
        )
        modelContext.insert(model)
        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            do {
                try await assetStore.deleteAsset(id: reference.assetID)
            } catch {
                pendingCleanup.insert(reference.assetID)
                throw ProgressPhotoRepositoryOperationError
                    .metadataSaveFailedCleanupPending(assetID: reference.assetID)
            }
            throw ProgressPhotoRepositoryOperationError.saveFailed
        }
        return try validatedSnapshot(from: model)
    }

    public func thumbnail(assetID: String) async throws -> PhotoAssetLoadResult {
        guard isOpaquePhotoAssetID(assetID) else {
            throw PhotoAssetStoreError.invalidAssetID
        }
        return try await assetStore.loadAsset(id: assetID, variant: .thumbnail)
    }

    public func deletePhoto(
        id: UUID,
        expectedUpdatedAt: Date
    ) async throws {
        let rows = try validatedRows()
        guard let row = rows.first(where: { $0.model.id == id }) else {
            return
        }
        guard row.model.updatedAt == expectedUpdatedAt else {
            throw ProgressPhotoRepositoryMutationError.stalePhoto(
                id: id,
                expectedUpdatedAt: expectedUpdatedAt,
                actualUpdatedAt: row.model.updatedAt
            )
        }

        modelContext.delete(row.model)
        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw ProgressPhotoRepositoryOperationError.saveFailed
        }

        do {
            try await assetStore.deleteAsset(id: row.snapshot.imageRef)
        } catch {
            do {
                try compensateDeletedMetadata(row.snapshot)
            } catch {
                pendingCleanup.insert(row.snapshot.imageRef)
                throw ProgressPhotoRepositoryOperationError.deleteCompensationFailed
            }
            throw mapAssetDeleteError(error)
        }
    }

    public func retryPendingAssetCleanup() async throws {
        for assetID in pendingAssetCleanupIDs {
            do {
                try await assetStore.deleteAsset(id: assetID)
                pendingCleanup.remove(assetID)
            } catch {
                throw mapAssetDeleteError(error)
            }
        }
    }

    private struct ValidatedRow {
        let model: ProgressPhoto
        let snapshot: ProgressPhotoSnapshot
    }

    private func validatedRows() throws -> [ValidatedRow] {
        let models: [ProgressPhoto]
        do {
            models = try modelContext.fetch(FetchDescriptor<ProgressPhoto>())
        } catch {
            throw ProgressPhotoRepositoryOperationError.loadFailed
        }
        let grouped = Dictionary(grouping: models, by: \.id)
        if let duplicate = grouped
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key.uuidString < $1.key.uuidString })
            .first {
            throw ProgressPhotoRepositoryIntegrityError.duplicatePhotoIDs(
                id: duplicate.key,
                count: duplicate.value.count
            )
        }
        return try models.map { model in
            ValidatedRow(
                model: model,
                snapshot: try validatedSnapshot(from: model)
            )
        }
    }

    private func validatedSnapshot(
        from model: ProgressPhoto
    ) throws -> ProgressPhotoSnapshot {
        guard isOpaquePhotoAssetID(model.imageRef) else {
            throw ProgressPhotoRepositoryIntegrityError.invalidImageRef(id: model.id)
        }
        let input: ProgressPhotoInput
        do {
            input = try ProgressPhotoInput(
                date: model.date,
                pose: model.pose,
                note: model.note
            )
        } catch {
            throw ProgressPhotoRepositoryIntegrityError.invalidPersistedPhoto(id: model.id)
        }
        guard input.note == model.note else {
            throw ProgressPhotoRepositoryIntegrityError.invalidPersistedPhoto(id: model.id)
        }
        return ProgressPhotoSnapshot(
            id: model.id,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            date: input.date,
            imageRef: model.imageRef,
            pose: input.pose,
            note: input.note
        )
    }

    private func compensateDeletedMetadata(
        _ snapshot: ProgressPhotoSnapshot
    ) throws {
        modelContext.insert(
            ProgressPhoto(
                id: snapshot.id,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                date: snapshot.date,
                imageRef: snapshot.imageRef,
                pose: snapshot.pose,
                note: snapshot.note
            )
        )
        do {
            try saveOperation()
        } catch {
            rollbackOperation()
            throw ProgressPhotoRepositoryOperationError.deleteCompensationFailed
        }
    }

    private func mapAssetDeleteError(
        _ error: Error
    ) -> ProgressPhotoRepositoryOperationError {
        if error as? PhotoAssetStoreError == .protectedDataUnavailable {
            return .protectedDataUnavailable
        }
        return .assetDeleteFailed
    }
}
