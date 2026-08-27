import Foundation

public actor CloudPhotoAssetCoordinator: CloudPhotoAssetSynchronizing {
    private let database: any PrivateCloudPhotoAssetDatabase
    private let localStore: any CloudPhotoAssetLocalStoring
    private let stateStore: any CloudPhotoAssetSyncStateStoring
    private let temporaryStore: FileCloudPhotoAssetTemporaryStore
    private let retryPolicy: CloudPhotoAssetRetryPolicy
    private let maximumAssetBytes: Int
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var generation: UInt64 = 0

    public init(
        database: any PrivateCloudPhotoAssetDatabase,
        localStore: any CloudPhotoAssetLocalStoring,
        stateStore: any CloudPhotoAssetSyncStateStoring,
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
        self.temporaryStore = temporaryStore
        self.retryPolicy = retryPolicy
        self.maximumAssetBytes = maximumAssetBytes
        self.sleep = sleep
    }

    public func synchronize() async throws -> CloudPhotoAssetSyncOutcome {
        generation &+= 1
        let operationGeneration = generation
        let database = self.database

        let status = try await database.accountStatus()
        try ensureCurrent(operationGeneration)
        guard status == .available else { return .deferred(status) }

        try await performWithRetry(generation: operationGeneration) {
            try await database.ensureZone(
                named: CloudPhotoAssetRecordContract.zoneName
            )
        }

        var state = try await stateStore.load()
        try ensureCurrent(operationGeneration)
        let localAssetIDs = try await localStore.storedAssetIDs()
        try ensureCurrent(operationGeneration)
        try validate(assetIDs: localAssetIDs)
        try validate(state: state)

        if reconcile(localAssetIDs: localAssetIDs, state: &state) {
            try await persist(state, generation: operationGeneration)
        }

        try await processDeletions(
            state: &state,
            generation: operationGeneration
        )
        try await processUploads(
            state: &state,
            generation: operationGeneration
        )
        try await processRemoteChanges(
            state: &state,
            generation: operationGeneration
        )
        return .synchronized
    }

    private func processDeletions(
        state: inout CloudPhotoAssetSyncState,
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
                page = try await performWithRetry(generation: generation) {
                    try await database.fetchChanges(
                        inZone: CloudPhotoAssetRecordContract.zoneName,
                        previousToken: token
                    )
                }
            } catch CloudPhotoAssetDatabaseError.changeTokenExpired {
                guard !didRestartExpiredToken else { throw CloudPhotoAssetDatabaseError.changeTokenExpired }
                didRestartExpiredToken = true
                state.changeToken = nil
                try await persist(state, generation: generation)
                continue
            }

            for change in page.changes {
                try ensureCurrent(generation)
                switch change {
                case let .changed(record):
                    try await apply(
                        record,
                        state: &state,
                        generation: generation
                    )
                case let .deleted(recordName):
                    let assetID = try CloudPhotoAssetRecordContract.assetID(
                        fromRecordName: recordName
                    )
                    try await localStore.deleteCloudAsset(id: assetID)
                    try ensureCurrent(generation)
                    remove(assetID, from: &state.pendingUploadAssetIDs)
                    remove(assetID, from: &state.pendingDeletionAssetIDs)
                    remove(assetID, from: &state.uploadedAssetIDs)
                }
            }
            state.changeToken = page.changeToken
            try await persist(state, generation: generation)
            guard page.moreComing else { return }
        }
    }

    private func apply(
        _ record: CloudPhotoAssetDownloadRecord,
        state: inout CloudPhotoAssetSyncState,
        generation: UInt64
    ) async throws {
        guard record.recordName == (try CloudPhotoAssetRecordContract.recordName(
            for: record.assetID
        )) else {
            throw CloudPhotoAssetContractError.invalidRecordMetadata
        }
        let ownedURL = try temporaryStore.copyDownloadedFile(
            from: record.stagedFileURL
        )
        defer { temporaryStore.removeFile(at: ownedURL) }
        let bytes = try temporaryStore.readFile(at: ownedURL)
        try CloudPhotoAssetChecksum.validate(
            bytes,
            expectedChecksum: record.checksum,
            expectedByteCount: record.byteCount,
            maximumBytes: maximumAssetBytes
        )
        try ensureCurrent(generation)
        try await localStore.restoreCloudAsset(id: record.assetID, bytes: bytes)
        try ensureCurrent(generation)
        markUploaded(record.assetID, state: &state)
        remove(record.assetID, from: &state.pendingDeletionAssetIDs)
    }

    private func performWithRetry<Value: Sendable>(
        generation: UInt64,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        var attempt = 1
        while true {
            try ensureCurrent(generation)
            do {
                let value = try await operation()
                try ensureCurrent(generation)
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
        localAssetIDs: Set<String>,
        state: inout CloudPhotoAssetSyncState
    ) -> Bool {
        let original = state
        let uploaded = Set(state.uploadedAssetIDs)
        let deletions = Set(state.pendingDeletionAssetIDs)
            .union(uploaded.subtracting(localAssetIDs))
        let uploads = Set(state.pendingUploadAssetIDs)
            .union(localAssetIDs.subtracting(uploaded))
            .subtracting(deletions)

        state.pendingUploadAssetIDs = uploads.sorted()
        state.pendingDeletionAssetIDs = deletions.sorted()
        state.uploadedAssetIDs = uploaded.sorted()
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
            guard try CloudPhotoAssetRecordContract.canonicalAssetID(assetID) == assetID else {
                throw CloudPhotoAssetContractError.invalidAssetID
            }
        }
    }

    private func ensureCurrent(_ operationGeneration: UInt64) throws {
        try Task.checkCancellation()
        guard generation == operationGeneration else { throw CancellationError() }
    }
}
