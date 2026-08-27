import CoreModels
import Foundation
import ProgressPhotosKit
import SwiftData

@MainActor
public final class SwiftDataProgressPhotoRepository: ProgressPhotoRepository {
    private let modelContext: ModelContext
    private let assetStore: any PhotoAssetStoring
    private let cleanupJournal: any PhotoAssetCleanupJournaling
    private let now: @MainActor () -> Date
    private let makeID: @MainActor () -> UUID
    private let saveOperation: @MainActor () throws -> Void
    private let rollbackOperation: @MainActor () -> Void
    private var pendingCleanup = Set<String>()
    private var hasReconciledAssetStorage = false
    private var hasExclusiveOperation = false
    private var exclusiveOperationWaiters: [CheckedContinuation<Void, Never>] = []

    public var pendingAssetCleanupIDs: [String] {
        pendingCleanup.sorted()
    }

    public init(
        modelContext: ModelContext,
        assetStore: any PhotoAssetStoring,
        cleanupJournal: any PhotoAssetCleanupJournaling,
        now: @escaping @MainActor () -> Date = { .now },
        makeID: @escaping @MainActor () -> UUID = { UUID() },
        save: (@MainActor () throws -> Void)? = nil,
        rollback: (@MainActor () -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.assetStore = assetStore
        self.cleanupJournal = cleanupJournal
        self.now = now
        self.makeID = makeID
        saveOperation = save ?? { try modelContext.save() }
        rollbackOperation = rollback ?? { modelContext.rollback() }
    }

    public func fetchPhotos() async throws -> [ProgressPhotoSnapshot] {
        await acquireExclusiveOperation()
        defer { releaseExclusiveOperation() }
        let rows = try validatedRows()
        try await reconcileAssetStorageIfNeeded(rows: rows)
        return rows.map(\.snapshot)
            .sorted(by: ProgressPhotoOrdering.newestFirst)
    }

    public func importPhoto(
        _ input: ProgressPhotoInput,
        bytes: Data
    ) async throws -> ProgressPhotoSnapshot {
        await acquireExclusiveOperation()
        defer { releaseExclusiveOperation() }
        let existing = try validatedRows()
        try await reconcileAssetStorageIfNeeded(rows: existing)
        let id = makeID()
        guard !existing.contains(where: { $0.model.id == id }) else {
            throw ProgressPhotoRepositoryIntegrityError.photoIDCollision(id: id)
        }

        let reference = try await assetStore.importAsset(bytes)
        guard isOpaquePhotoAssetID(reference.assetID) else {
            try? await assetStore.deleteAsset(id: reference.assetID)
            throw ProgressPhotoRepositoryIntegrityError.invalidImageRef(id: id)
        }
        guard !existing.contains(where: {
            $0.snapshot.imageRef == reference.assetID
        }) else {
            throw ProgressPhotoRepositoryIntegrityError.duplicateImageRefs(
                assetID: reference.assetID,
                count: 2
            )
        }
        do {
            try await recordPendingCleanup(reference.assetID)
        } catch {
            do {
                try await assetStore.deleteAsset(id: reference.assetID)
            } catch {
                pendingCleanup.insert(reference.assetID)
            }
            throw ProgressPhotoRepositoryOperationError.cleanupJournalFailed(
                assetID: reference.assetID
            )
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
                try? await clearPendingCleanup(reference.assetID)
            } catch {
                throw ProgressPhotoRepositoryOperationError
                    .metadataSaveFailedCleanupPending(assetID: reference.assetID)
            }
            throw ProgressPhotoRepositoryOperationError.saveFailed
        }
        await clearReferencedCleanupIntent(reference.assetID)
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
        await acquireExclusiveOperation()
        defer { releaseExclusiveOperation() }
        let rows = try validatedRows()
        try await reconcileAssetStorageIfNeeded(rows: rows)
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
            try await recordPendingCleanup(row.snapshot.imageRef)
        } catch {
            do {
                try compensateDeletedMetadata(row.snapshot)
            } catch {
                pendingCleanup.insert(row.snapshot.imageRef)
                throw ProgressPhotoRepositoryOperationError.deleteCompensationFailed
            }
            throw ProgressPhotoRepositoryOperationError.cleanupJournalFailed(
                assetID: row.snapshot.imageRef
            )
        }

        do {
            try await assetStore.deleteAsset(id: row.snapshot.imageRef)
            try? await clearPendingCleanup(row.snapshot.imageRef)
        } catch {
            do {
                try compensateDeletedMetadata(row.snapshot)
                await clearReferencedCleanupIntent(row.snapshot.imageRef)
            } catch {
                throw ProgressPhotoRepositoryOperationError.deleteCompensationFailed
            }
            throw mapAssetDeleteError(error)
        }
    }

    public func retryPendingAssetCleanup() async throws {
        await acquireExclusiveOperation()
        defer { releaseExclusiveOperation() }
        let rows = try validatedRows()
        try await reconcileAssetStorageIfNeeded(rows: rows)
        let referenced = Set(rows.map { $0.snapshot.imageRef })
        for assetID in pendingAssetCleanupIDs where referenced.contains(assetID) {
            await clearReferencedCleanupIntent(assetID)
        }
        for assetID in pendingAssetCleanupIDs {
            do {
                try await assetStore.deleteAsset(id: assetID)
                try await clearPendingCleanup(assetID)
            } catch {
                throw mapAssetDeleteError(error)
            }
        }
    }

    private func reconcileAssetStorageIfNeeded(
        rows: [ValidatedRow]
    ) async throws {
        guard !hasReconciledAssetStorage else { return }
        let referenced = Set(rows.map { $0.snapshot.imageRef })
        let journalIDs: Set<String>
        let storedIDs: Set<String>
        do {
            journalIDs = try await cleanupJournal.loadPendingAssetIDs()
            storedIDs = try await assetStore.storedAssetIDs()
        } catch {
            throw ProgressPhotoRepositoryOperationError.cleanupJournalFailed(
                assetID: nil
            )
        }

        for assetID in journalIDs.intersection(referenced).sorted() {
            try? await cleanupJournal.removePendingAssetID(assetID)
            pendingCleanup.remove(assetID)
        }

        let orphanIDs = journalIDs
            .union(storedIDs.subtracting(referenced))
            .subtracting(referenced)
        pendingCleanup.formUnion(orphanIDs)
        for assetID in orphanIDs.sorted() {
            try? await cleanupJournal.addPendingAssetID(assetID)
            do {
                try await assetStore.deleteAsset(id: assetID)
                try await clearPendingCleanup(assetID)
            } catch {
                pendingCleanup.insert(assetID)
            }
        }
        hasReconciledAssetStorage = true
    }

    private func recordPendingCleanup(_ assetID: String) async throws {
        guard isOpaquePhotoAssetID(assetID) else {
            throw ProgressPhotoRepositoryOperationError.cleanupJournalFailed(
                assetID: assetID
            )
        }
        try await cleanupJournal.addPendingAssetID(assetID)
        pendingCleanup.insert(assetID)
    }

    private func clearPendingCleanup(_ assetID: String) async throws {
        try await cleanupJournal.removePendingAssetID(assetID)
        pendingCleanup.remove(assetID)
    }

    private func clearReferencedCleanupIntent(_ assetID: String) async {
        try? await cleanupJournal.removePendingAssetID(assetID)
        pendingCleanup.remove(assetID)
    }

    private func acquireExclusiveOperation() async {
        if !hasExclusiveOperation {
            hasExclusiveOperation = true
            return
        }
        await withCheckedContinuation { continuation in
            exclusiveOperationWaiters.append(continuation)
        }
    }

    private func releaseExclusiveOperation() {
        guard !exclusiveOperationWaiters.isEmpty else {
            hasExclusiveOperation = false
            return
        }
        let next = exclusiveOperationWaiters.removeFirst()
        next.resume()
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
        let rows = try models.map { model in
            ValidatedRow(
                model: model,
                snapshot: try validatedSnapshot(from: model)
            )
        }
        let imageRefGroups = Dictionary(grouping: rows) {
            $0.snapshot.imageRef
        }
        if let duplicate = imageRefGroups
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key < $1.key })
            .first {
            throw ProgressPhotoRepositoryIntegrityError.duplicateImageRefs(
                assetID: duplicate.key,
                count: duplicate.value.count
            )
        }
        return rows
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
