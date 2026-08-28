import Foundation

public actor CloudPhotoAssetCoordinator: CloudPhotoAssetSynchronizing {
    private let database: any PrivateCloudPhotoAssetDatabase
    private let localStore: any CloudPhotoAssetLocalStoring
    private let stateStore: any CloudPhotoAssetSyncStateStoring
    private let referenceSnapshotProvider: any CloudPhotoAssetReferenceSnapshotProviding
    private let deletionIntentStore: any CloudPhotoAssetDeletionIntentStoring
    private let inboundAssetApplier: any CloudPhotoAssetInboundApplying
    private let temporaryStore: FileCloudPhotoAssetTemporaryStore
    private let retryPolicy: CloudPhotoAssetRetryPolicy
    private let maximumAssetBytes: Int
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var generation: UInt64 = 0

    public init(
        database: any PrivateCloudPhotoAssetDatabase,
        localStore: any CloudPhotoAssetLocalStoring,
        stateStore: any CloudPhotoAssetSyncStateStoring,
        referenceSnapshotProvider: (any CloudPhotoAssetReferenceSnapshotProviding)? = nil,
        deletionIntentStore: (any CloudPhotoAssetDeletionIntentStoring)? = nil,
        inboundAssetApplier: any CloudPhotoAssetInboundApplying,
        temporaryStore: FileCloudPhotoAssetTemporaryStore,
        retryPolicy: CloudPhotoAssetRetryPolicy = .init(),
        maximumAssetBytes: Int = PhotoAssetPolicy.production.maximumInputBytes,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { delay in
            guard delay > 0 else { return }
            try await Task.sleep(
                nanoseconds: UInt64(delay * 1_000_000_000)
            )
        }
    ) {
        precondition(maximumAssetBytes > 0)
        self.database = database
        self.localStore = localStore
        self.stateStore = stateStore
        self.referenceSnapshotProvider = referenceSnapshotProvider
            ?? EmptyCloudPhotoAssetReferenceSnapshotProvider.shared
        self.deletionIntentStore = deletionIntentStore
            ?? NoOpCloudPhotoAssetDeletionIntentStore.shared
        self.inboundAssetApplier = inboundAssetApplier
        self.temporaryStore = temporaryStore
        self.retryPolicy = retryPolicy
        self.maximumAssetBytes = maximumAssetBytes
        self.sleep = sleep
    }

    public func synchronize() async throws -> CloudPhotoAssetSyncOutcome {
        generation &+= 1
        let operationGeneration = generation
        let database = self.database

        let accountResolution = await deletionIntentStore.beginAccountResolution()
        try ensureCurrent(operationGeneration)

        let status = try await database.accountStatus()
        try ensureCurrent(operationGeneration)
        guard status == .available else { return .deferred(status) }

        let accountIdentity = try await database.accountIdentity()
        try ensureCurrent(operationGeneration)
        guard !accountIdentity.isEmpty else {
            throw CloudPhotoAssetDatabaseError.permanent
        }
        try await performWithRetry(generation: operationGeneration) {
            try await database.ensureZone(
                named: CloudPhotoAssetRecordContract.zoneName
            )
        }

        var state = try await stateStore.load()
        try ensureCurrent(operationGeneration)
        try validate(state: state)

        var didAdoptAccountIdentity = false
        if state.requiresLegacyAccountReset
            || (state.accountIdentity != nil
                && state.accountIdentity != accountIdentity) {
            state = CloudPhotoAssetSyncState(accountIdentity: accountIdentity)
            try await persist(state, generation: operationGeneration)
        } else if state.accountIdentity == nil {
            state.accountIdentity = accountIdentity
            didAdoptAccountIdentity = true
        }

        let accountAuthorization = try await deletionIntentStore.activateAccountIdentity(
            accountIdentity,
            resolution: accountResolution
        )
        do {
            let outcome = try await synchronizeAuthorizedAccount(
                accountIdentity: accountIdentity,
                state: &state,
                didAdoptAccountIdentity: didAdoptAccountIdentity,
                generation: operationGeneration
            )
            await deletionIntentStore.suspendAccountAuthorization(accountAuthorization)
            try ensureCurrent(operationGeneration)
            return outcome
        } catch {
            await deletionIntentStore.suspendAccountAuthorization(accountAuthorization)
            throw error
        }
    }

    private func synchronizeAuthorizedAccount(
        accountIdentity: String,
        state: inout CloudPhotoAssetSyncState,
        didAdoptAccountIdentity: Bool,
        generation operationGeneration: UInt64
    ) async throws -> CloudPhotoAssetSyncOutcome {
        try ensureCurrent(operationGeneration)
        let committedDeletionIntents = try await deletionIntentStore
            .pendingDeletionIntents(forAccountIdentity: accountIdentity)
        var committedDeletionIDs = Set(committedDeletionIntents.map(\.assetID))
        try ensureCurrent(operationGeneration)
        let referenceSnapshot = try await referenceSnapshotProvider.snapshot()
        try ensureCurrent(operationGeneration)
        let referencedAssetIDs = referenceSnapshot.referencedAssetIDs
        let usableLocalAssetIDs = try await localStore.usableCloudAssetIDs()
        try ensureCurrent(operationGeneration)
        try validate(assetIDs: committedDeletionIDs)
        try validate(assetIDs: referencedAssetIDs)
        try validate(assetIDs: usableLocalAssetIDs)

        let referencedDeletionIntents = committedDeletionIntents.filter {
            referencedAssetIDs.contains($0.assetID)
        }
        for intent in referencedDeletionIntents.sorted(by: {
            $0.intentID.uuidString < $1.intentID.uuidString
        }) {
            try await deletionIntentStore.clearCommittedDeletion(intent)
            try ensureCurrent(operationGeneration)
        }
        let referencedDeletionIDs = Set(referencedDeletionIntents.map(\.assetID))
        committedDeletionIDs.subtract(referencedDeletionIDs)
        state.pendingDeletionAssetIDs.removeAll {
            referencedDeletionIDs.contains($0)
        }
        state.uploadedAssetIDs.removeAll {
            referencedDeletionIDs.contains($0)
        }
        if !referencedDeletionIDs.isEmpty {
            state.changeToken = nil
        }

        let didReconcile = reconcile(usableLocalAssetIDs: usableLocalAssetIDs,
            referencedAssetIDs: referencedAssetIDs,
            committedDeletionIDs: committedDeletionIDs,
            state: &state
        )
        if didAdoptAccountIdentity
            || !referencedDeletionIDs.isEmpty
            || didReconcile {
            try await persist(state, generation: operationGeneration)
        }

        try await processDeletions(
            state: &state,
            accountIdentity: accountIdentity,
            generation: operationGeneration
        )
        try await processUploads(
            state: &state,
            generation: operationGeneration
        )
        try await processRemoteChanges(
            referencedAssetIDs: referencedAssetIDs,
            accountIdentity: accountIdentity,
            state: &state,
            generation: operationGeneration
        )
        return .synchronized
    }

    private func processDeletions(
        state: inout CloudPhotoAssetSyncState,
        accountIdentity: String,
        generation: UInt64
    ) async throws {
        let database = self.database
        for assetID in state.pendingDeletionAssetIDs.sorted() {
            try ensureCurrent(generation)
            let recordName = try CloudPhotoAssetRecordContract.recordName(for: assetID)
            do {
                try await performWithRetry(generation: generation) {
                    try await database.deleteRecord(
                        named: recordName,
                        inZone: CloudPhotoAssetRecordContract.zoneName
                    )
                }
            } catch CloudPhotoAssetDatabaseError.recordNotFound {
                try ensureCurrent(generation)
            }
            try await deletionIntentStore.clearCommittedDeletion(
                assetID: assetID,
                forAccountIdentity: accountIdentity
            )
            try ensureCurrent(generation)
            remove(assetID, from: &state.pendingDeletionAssetIDs)
            remove(assetID, from: &state.pendingUploadAssetIDs)
            remove(assetID, from: &state.uploadedAssetIDs)
            try await persist(state, generation: generation)
        }
    }

    private func processUploads(
        state: inout CloudPhotoAssetSyncState,
        generation: UInt64
    ) async throws {
        let database = self.database
        for assetID in state.pendingUploadAssetIDs.sorted() {
            try ensureCurrent(generation)
            guard !state.pendingDeletionAssetIDs.contains(assetID) else { continue }
            guard let bytes = try await localStore.cloudAssetBytes(id: assetID) else {
                try ensureCurrent(generation)
                remove(assetID, from: &state.pendingUploadAssetIDs)
                try await persist(state, generation: generation)
                continue
            }
            try ensureCurrent(generation)
            guard bytes.count <= maximumAssetBytes else {
                throw CloudPhotoAssetValidationError.exceedsMaximumBytes(
                    maximumBytes: maximumAssetBytes
                )
            }
            let checksum = CloudPhotoAssetChecksum.sha256Hex(bytes)
            let recordName = try CloudPhotoAssetRecordContract.recordName(for: assetID)
            let existing = try await performWithRetry(generation: generation) {
                try await database.record(
                    named: recordName,
                    inZone: CloudPhotoAssetRecordContract.zoneName
                )
            }
            if let existing,
               existing.assetID == assetID,
               existing.checksum == checksum,
               existing.byteCount == bytes.count {
                markUploaded(assetID, state: &state)
                try await persist(state, generation: generation)
                continue
            }

            let uploadURL = try temporaryStore.createUploadFile(bytes: bytes)
            defer { temporaryStore.removeFile(at: uploadURL) }
            let request = try CloudPhotoAssetUploadRequest(
                recordName: recordName,
                assetID: assetID,
                checksum: checksum,
                byteCount: bytes.count,
                fileURL: uploadURL
            )
            let saved = try await performWithRetry(generation: generation) {
                try await database.save(
                    request,
                    inZone: CloudPhotoAssetRecordContract.zoneName
                )
            }
            guard saved.recordName == request.recordName,
                  saved.assetID == request.assetID,
                  saved.checksum == request.checksum,
                  saved.byteCount == request.byteCount else {
                throw CloudPhotoAssetSyncError.invalidServerResponse
            }
            markUploaded(assetID, state: &state)
            try await persist(state, generation: generation)
        }
    }

    private func processRemoteChanges(
        referencedAssetIDs: Set<String>,
        accountIdentity: String,
        state: inout CloudPhotoAssetSyncState,
        generation: UInt64
    ) async throws {
        let database = self.database
        var didRestartExpiredToken = false
        while true {
            try ensureCurrent(generation)
            let page: CloudPhotoAssetChangePage
            do {
                let token = state.changeToken
                page = try await performWithRetry(
                    generation: generation,
                    onDiscard: { [temporaryStore = self.temporaryStore] page in
                        for change in page.changes {
                            if case let .changed(record) = change {
                                temporaryStore.removeFile(
                                    at: record.stagedFileURL
                                )
                            }
                        }
                    },
                    operation: {
                        try await database.fetchChanges(
                            inZone: CloudPhotoAssetRecordContract.zoneName,
                            previousToken: token
                        )
                    }
                )
            } catch CloudPhotoAssetDatabaseError.changeTokenExpired {
                guard !didRestartExpiredToken else {
                    throw CloudPhotoAssetDatabaseError.changeTokenExpired
                }
                didRestartExpiredToken = true
                state.changeToken = nil
                try await persist(state, generation: generation)
                continue
            }

            do {
                for change in page.changes {
                    try ensureCurrent(generation)
                    switch change {
                    case let .changed(record):
                        try await apply(
                            record,
                            accountIdentity: accountIdentity,
                            state: &state,
                            generation: generation
                        )
                    case let .deleted(recordName):
                        let assetID = try CloudPhotoAssetRecordContract.assetID(
                            fromRecordName: recordName
                        )
                        if referencedAssetIDs.contains(assetID) {
                            remove(assetID, from: &state.uploadedAssetIDs)
                            if try await localStore.cloudAssetBytes(id: assetID) != nil {
                                insert(assetID, into: &state.pendingUploadAssetIDs)
                            }
                        } else {
                            try await localStore.deleteCloudAsset(id: assetID)
                            try ensureCurrent(generation)
                            remove(assetID, from: &state.pendingUploadAssetIDs)
                            remove(assetID, from: &state.pendingDeletionAssetIDs)
                            remove(assetID, from: &state.uploadedAssetIDs)
                        }
                    }
                }
                state.changeToken = page.changeToken
                try await persist(state, generation: generation)
            } catch {
                for change in page.changes {
                    if case let .changed(record) = change {
                        temporaryStore.removeFile(at: record.stagedFileURL)
                    }
                }
                throw error
            }
            guard page.moreComing else { return }
        }
    }

    private func apply(
        _ record: CloudPhotoAssetDownloadRecord,
        accountIdentity: String,
        state: inout CloudPhotoAssetSyncState,
        generation: UInt64
    ) async throws {
        defer { temporaryStore.removeFile(at: record.stagedFileURL) }
        guard record.recordName == (try CloudPhotoAssetRecordContract.recordName(
            for: record.assetID
        )) else {
            throw CloudPhotoAssetContractError.invalidRecordMetadata
        }
        let bytes = try temporaryStore.readFile(
            at: record.stagedFileURL,
            maximumBytes: maximumAssetBytes
        )
        try CloudPhotoAssetChecksum.validate(
            bytes,
            expectedChecksum: record.checksum,
            expectedByteCount: record.byteCount,
            maximumBytes: maximumAssetBytes
        )
        try ensureCurrent(generation)
        let preparation = try await inboundAssetApplier.prepareInboundApply(
            id: record.assetID,
            forAccountIdentity: accountIdentity
        )
        switch preparation {
        case .discardedCommittedDeletion:
            try ensureCurrent(generation)
            return
        case let .prepared(lease):
            do {
                try ensureCurrent(generation)
                try await inboundAssetApplier.commitInboundApply(
                    lease,
                    bytes: bytes
                )
            } catch {
                await inboundAssetApplier.cancelInboundApply(lease)
                throw error
            }
            try ensureCurrent(generation)
        }
        markUploaded(record.assetID, state: &state)
        remove(record.assetID, from: &state.pendingDeletionAssetIDs)
    }

    private func performWithRetry<Value: Sendable>(
        generation: UInt64,
        onDiscard: @escaping @Sendable (Value) -> Void = { _ in },
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        var attempt = 1
        while true {
            try ensureCurrent(generation)
            do {
                let value = try await operation()
                do {
                    try ensureCurrent(generation)
                } catch {
                    onDiscard(value)
                    throw error
                }
                return value
            } catch {
                try ensureCurrent(generation)
                guard let databaseError = error as? CloudPhotoAssetDatabaseError,
                      case let .retryable(retryAfter) = databaseError,
                      attempt < retryPolicy.maximumAttempts else {
                    throw error
                }
                let delay = retryPolicy.delay(
                    afterFailedAttempt: attempt,
                    retryAfter: retryAfter
                )
                try await sleep(delay)
                try ensureCurrent(generation)
                attempt += 1
            }
        }
    }

    private func persist(
        _ state: CloudPhotoAssetSyncState,
        generation: UInt64
    ) async throws {
        try ensureCurrent(generation)
        try await stateStore.save(state)
        try ensureCurrent(generation)
    }

    private func reconcile(
        usableLocalAssetIDs: Set<String>,
        referencedAssetIDs: Set<String>,
        committedDeletionIDs: Set<String>,
        state: inout CloudPhotoAssetSyncState
    ) -> Bool {
        let original = state
        let uploaded = Set(state.uploadedAssetIDs)
        let deletions = committedDeletionIDs
        let referencedUsable = usableLocalAssetIDs.intersection(referencedAssetIDs)
        let uploads = Set(state.pendingUploadAssetIDs)
            .intersection(referencedUsable)
            .union(referencedUsable.subtracting(uploaded))
            .subtracting(deletions)
        let referencedMissingUploaded = referencedAssetIDs
            .subtracting(usableLocalAssetIDs)
            .intersection(uploaded)

        state.pendingUploadAssetIDs = uploads.sorted()
        state.pendingDeletionAssetIDs = deletions.sorted()
        state.uploadedAssetIDs = uploaded.sorted()
        if !referencedMissingUploaded.isEmpty {
            state.changeToken = nil
        }
        return state != original
    }

    private func markUploaded(
        _ assetID: String,
        state: inout CloudPhotoAssetSyncState
    ) {
        remove(assetID, from: &state.pendingUploadAssetIDs)
        insert(assetID, into: &state.uploadedAssetIDs)
    }

    private func insert(_ assetID: String, into values: inout [String]) {
        guard !values.contains(assetID) else { return }
        values.append(assetID)
        values.sort()
    }

    private func remove(_ assetID: String, from values: inout [String]) {
        values.removeAll { $0 == assetID }
    }

    private func validate(state: CloudPhotoAssetSyncState) throws {
        try validate(assetIDs: Set(state.pendingUploadAssetIDs))
        try validate(assetIDs: Set(state.pendingDeletionAssetIDs))
        try validate(assetIDs: Set(state.uploadedAssetIDs))
    }

    private func validate(assetIDs: Set<String>) throws {
        for assetID in assetIDs {
            guard try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
                == assetID else {
                throw CloudPhotoAssetContractError.invalidAssetID
            }
        }
    }

    private func ensureCurrent(_ operationGeneration: UInt64) throws {
        try Task.checkCancellation()
        guard generation == operationGeneration else { throw CancellationError() }
    }
}
