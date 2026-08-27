import CoreModels
import Foundation
import ProgressPhotosKit
import SwiftData

@MainActor
public final class SwiftDataProgressPhotoRepository:
    ProgressPhotoRepository,
    CloudPhotoAssetReferenceSnapshotProviding,
    CloudPhotoAssetInboundApplying {
    private let modelContext: ModelContext
    private let assetStore: any PhotoAssetStoring
    private let cleanupJournal: any PhotoAssetCleanupJournaling
    private let deletionIntentStore: any CloudPhotoAssetDeletionIntentStoring
    private let inboundAssetJournal: any CloudPhotoAssetInboundJournaling
    private let inboundAssetStore: (any CloudPhotoAssetLocalStoring)?
    private let now: @MainActor () -> Date
    private let makeID: @MainActor () -> UUID
    private let saveOperation: @MainActor () throws -> Void
    private let rollbackOperation: @MainActor () -> Void
    private var pendingCleanup = Set<String>()
    private var hasReconciledAssetStorage = false
    private var hasExclusiveOperation = false
    private var exclusiveOperationWaiters: [CheckedContinuation<Void, Never>] = []
    private var activeInboundApplyLease: CloudPhotoAssetInboundApplyLease?

    public var pendingAssetCleanupIDs: [String] {
        pendingCleanup.sorted()
    }

    public init(
        modelContext: ModelContext,
        assetStore: any PhotoAssetStoring,
        cleanupJournal: any PhotoAssetCleanupJournaling,
        deletionIntentStore: (any CloudPhotoAssetDeletionIntentStoring)? = nil,
        inboundAssetJournal: (any CloudPhotoAssetInboundJournaling)? = nil,
        inboundAssetStore: (any CloudPhotoAssetLocalStoring)? = nil,
        now: @escaping @MainActor () -> Date = { .now },
        makeID: @escaping @MainActor () -> UUID = { UUID() },
        save: (@MainActor () throws -> Void)? = nil,
        rollback: (@MainActor () -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.assetStore = assetStore
        self.cleanupJournal = cleanupJournal
        self.deletionIntentStore = deletionIntentStore
            ?? NoOpCloudPhotoAssetDeletionIntentStore.shared
        self.inboundAssetJournal = inboundAssetJournal
            ?? NoOpCloudPhotoAssetInboundJournal.shared
        self.inboundAssetStore = inboundAssetStore
        self.now = now
        self.makeID = makeID
        saveOperation = save ?? { try modelContext.save() }
        rollbackOperation = rollback ?? { modelContext.rollback() }
    }

    public func prepareInboundApply(
        id assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws -> CloudPhotoAssetInboundApplyPreparation {
        await acquireExclusiveOperation()
        do {
            try Task.checkCancellation()
            guard inboundAssetStore != nil else {
                throw CloudPhotoAssetSyncError.invalidServerResponse
            }
            guard activeInboundApplyLease == nil else {
                throw CloudPhotoAssetSyncError.invalidServerResponse
            }
            guard !accountIdentity.isEmpty,
                  try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
                    == assetID else {
                throw CloudPhotoAssetContractError.invalidAssetID
            }
            if try await deletionIntentStore.hasCommittedLocalDeletionIntent(assetID: assetID) {
                releaseExclusiveOperation()
                return .discardedCommittedDeletion
            }
            try Task.checkCancellation()
            let lease = CloudPhotoAssetInboundApplyLease(
                assetID: assetID,
                accountIdentity: accountIdentity
            )
            activeInboundApplyLease = lease
            return .prepared(lease)
        } catch {
            releaseExclusiveOperation()
            throw error
        }
    }

    public func commitInboundApply(
        _ lease: CloudPhotoAssetInboundApplyLease,
        bytes: Data
    ) async throws {
        guard activeInboundApplyLease == lease else {
            throw CloudPhotoAssetSyncError.invalidServerResponse
        }
        defer { releaseInboundApplyLease(lease) }
        guard let inboundAssetStore else {
            throw CloudPhotoAssetSyncError.invalidServerResponse
        }
        try await inboundAssetJournal.recordInboundAssetID(lease.assetID)
        try Task.checkCancellation()
        try await inboundAssetStore.restoreCloudAsset(id: lease.assetID, bytes: bytes)
    }

    public func cancelInboundApply(_ lease: CloudPhotoAssetInboundApplyLease) async {
        guard activeInboundApplyLease == lease else { return }
        releaseInboundApplyLease(lease)
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

    public func fullImage(assetID: String) async throws -> PhotoAssetLoadResult {
        guard isOpaquePhotoAssetID(assetID) else {
            throw PhotoAssetStoreError.invalidAssetID
        }
        return try await assetStore.loadAsset(id: assetID, variant: .full)
    }

    public func snapshot() async throws -> CloudPhotoAssetReferenceSnapshot {
        await acquireExclusiveOperation()
        defer { releaseExclusiveOperation() }
        let rows = try validatedRows()
        try await reconcileAssetStorageIfNeeded(rows: rows)
        return CloudPhotoAssetReferenceSnapshot(
            referencedAssetIDs: Set(rows.map { $0.snapshot.imageRef })
        )
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

        let deletionIntent: CloudPhotoAssetDeletionIntentReceipt
        do {
            deletionIntent = try await deletionIntentStore.recordCommittedDeletion(
                assetID: row.snapshot.imageRef
            )
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
            try await recordPendingCleanup(row.snapshot.imageRef)
        } catch {
            do {
                try compensateDeletedMetadata(row.snapshot)
                try await deletionIntentStore.clearCommittedDeletion(deletionIntent)
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
                try await deletionIntentStore.clearCommittedDeletion(deletionIntent)
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
        let freshPendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed()
        for assetID in pendingAssetCleanupIDs where
            !freshPendingInboundAssetIDs.contains(assetID) {
            do {
                if try await deleteAssetIfNotInbound(assetID) {
                    try await clearPendingCleanup(assetID)
                }
            } catch {
                throw mapAssetDeleteError(error)
            }
        }
    }

    private func reconcileAssetStorageIfNeeded(
        rows: [ValidatedRow]
    ) async throws {
        let referenced = Set(rows.map { $0.snapshot.imageRef })
        let pendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed()

        for assetID in pendingInboundAssetIDs.intersection(referenced).sorted() {
            do {
                try await inboundAssetJournal.clearInboundAssetID(assetID)
            } catch {
                throw ProgressPhotoRepositoryOperationError.cleanupJournalFailed(
                    assetID: assetID
                )
            }
        }

        guard !hasReconciledAssetStorage else { return }
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
            .subtracting(pendingInboundAssetIDs.subtracting(referenced))
        pendingCleanup.formUnion(orphanIDs)
        for assetID in orphanIDs.sorted() {
            try? await cleanupJournal.addPendingAssetID(assetID)
            let freshPendingInboundAssetIDs = try await loadPendingInboundAssetIDsFailClosed()
            if freshPendingInboundAssetIDs.contains(assetID) {
                await clearReferencedCleanupIntent(assetID)
                continue
            }
            do {
                if try await deleteAssetIfNotInbound(assetID) {
                    try await clearPendingCleanup(assetID)
                } else if try await loadPendingInboundAssetIDsFailClosed()
                    .contains(assetID) {
                    await clearReferencedCleanupIntent(assetID)
                }
            } catch {
                pendingCleanup.insert(assetID)
            }
        }
        hasReconciledAssetStorage = true
    }

    private func loadPendingInboundAssetIDsFailClosed() async throws -> Set<String> {
        do {
            return try await inboundAssetJournal.pendingInboundAssetIDs()
        } catch {
            throw ProgressPhotoRepositoryOperationError.cleanupJournalFailed(
                assetID: nil
            )
        }
    }

    private func deleteAssetIfNotInbound(_ assetID: String) async throws -> Bool {
        guard let lease = try await inboundAssetJournal.acquireCleanupLease(for: assetID)
        else { return false }
        do {
            try await assetStore.deleteAsset(id: assetID)
            await inboundAssetJournal.releaseCleanupLease(lease)
            return true
        } catch {
            await inboundAssetJournal.releaseCleanupLease(lease)
            throw error
        }
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

    private func releaseInboundApplyLease(
        _ lease: CloudPhotoAssetInboundApplyLease
    ) {
        guard activeInboundApplyLease == lease else { return }
        activeInboundApplyLease = nil
        releaseExclusiveOperation()
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
