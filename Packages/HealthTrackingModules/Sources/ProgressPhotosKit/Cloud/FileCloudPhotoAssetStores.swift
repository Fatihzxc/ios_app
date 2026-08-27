import CryptoKit
import Foundation

public actor FileCloudPhotoAssetSyncStateStore: CloudPhotoAssetSyncStateStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() async throws -> CloudPhotoAssetSyncState {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .empty }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(CloudPhotoAssetSyncState.self, from: data)
    }

    public func save(_ state: CloudPhotoAssetSyncState) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        #if targetEnvironment(simulator)
        try data.write(to: fileURL, options: .atomic)
        #else
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtection]
        )
        #endif
    }
}

public actor FileCloudPhotoAssetDeletionIntentStore:
    CloudPhotoAssetDeletionIntentStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private var activeAccountResolutionID: UUID?
    private var activeAccountAuthorization: CloudPhotoAssetAccountAuthorization?
    private var activeAccountIdentity: String? {
        activeAccountAuthorization?.accountIdentity
    }

    public init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func beginAccountResolution() async -> CloudPhotoAssetAccountResolution {
        let resolution = CloudPhotoAssetAccountResolution()
        activeAccountAuthorization = nil
        activeAccountResolutionID = resolution.resolutionID
        return resolution
    }

    public func activateAccountIdentity(
        _ accountIdentity: String,
        resolution: CloudPhotoAssetAccountResolution
    ) async throws -> CloudPhotoAssetAccountAuthorization {
        try validate(accountIdentity: accountIdentity)
        guard activeAccountResolutionID == resolution.resolutionID else {
            throw CancellationError()
        }
        activeAccountResolutionID = nil
        let loaded = try loadState()
        var state = loaded.state
        for index in state.intents.indices where
            state.intents[index].accountIdentity == nil
                && state.intents[index].quarantineIdentityHint == accountIdentity {
            state.intents[index].accountIdentity = accountIdentity
            state.intents[index].quarantineIdentityHint = nil
        }
        state.intents.sort()
        state.lastVerifiedAccountIdentity = accountIdentity
        if loaded.requiresMigration || state != loaded.state {
            try save(state)
        }
        let authorization = CloudPhotoAssetAccountAuthorization(
            accountIdentity: accountIdentity
        )
        activeAccountAuthorization = authorization
        return authorization
    }

    public func suspendAccountAuthorization(
        _ authorization: CloudPhotoAssetAccountAuthorization
    ) async {
        guard activeAccountAuthorization?.authorizationID
                == authorization.authorizationID else { return }
        activeAccountAuthorization = nil
    }

    public func pendingDeletionIntents(
        forAccountIdentity accountIdentity: String
    ) async throws -> [CloudPhotoAssetDeletionIntentReceipt] {
        try validate(accountIdentity: accountIdentity)
        let loaded = try loadState()
        if loaded.requiresMigration {
            try save(loaded.state)
        }
        var receipts: [CloudPhotoAssetDeletionIntentReceipt] = []
        for intent in loaded.state.intents where
            intent.accountIdentity == accountIdentity {
            guard intent.quarantineIdentityHint == nil else {
                throw CloudPhotoAssetContractError.invalidAssetID
            }
            receipts.append(
                CloudPhotoAssetDeletionIntentReceipt(
                    assetID: intent.assetID,
                    accountIdentity: accountIdentity,
                    quarantineIdentityHint: nil,
                    intentID: intent.intentID
                )
            )
        }
        return receipts
    }

    public func pendingDeletionAssetIDs(
        forAccountIdentity accountIdentity: String
    ) async throws -> Set<String> {
        try validate(accountIdentity: accountIdentity)
        let loaded = try loadState()
        if loaded.requiresMigration {
            try save(loaded.state)
        }
        return Set(
            loaded.state.intents.lazy
                .filter { $0.accountIdentity == accountIdentity }
                .map(\.assetID)
        )
    }

    public func unresolvedDeletionAssetIDs() async throws -> Set<String> {
        let loaded = try loadState()
        if loaded.requiresMigration {
            try save(loaded.state)
        }
        return Set(
            loaded.state.intents.lazy
                .filter { $0.accountIdentity == nil }
                .map(\.assetID)
        )
    }

    public func hasCommittedLocalDeletionIntent(assetID: String) async throws -> Bool {
        let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
        let loaded = try loadState()
        if loaded.requiresMigration {
            try save(loaded.state)
        }
        return loaded.state.intents.contains { $0.assetID == canonicalID }
    }

    public func recordCommittedDeletion(
        assetID: String
    ) async throws -> CloudPhotoAssetDeletionIntentReceipt {
        let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
        var state = try loadState().state
        let storedIntent: FileCloudPhotoAssetDeletionIntentRecord
        if let activeAccountIdentity {
            storedIntent = FileCloudPhotoAssetDeletionIntentRecord(
                intentID: UUID(),
                assetID: canonicalID,
                accountIdentity: activeAccountIdentity,
                quarantineIdentityHint: nil
            )
        } else {
            storedIntent = FileCloudPhotoAssetDeletionIntentRecord(
                intentID: UUID(),
                assetID: canonicalID,
                accountIdentity: nil,
                quarantineIdentityHint: state.lastVerifiedAccountIdentity
            )
        }
        state.intents.append(storedIntent)
        state.intents.sort()
        try save(state)
        return CloudPhotoAssetDeletionIntentReceipt(
            assetID: canonicalID,
            accountIdentity: storedIntent.accountIdentity,
            quarantineIdentityHint: storedIntent.quarantineIdentityHint,
            intentID: storedIntent.intentID
        )
    }

    public func clearCommittedDeletion(
        _ intent: CloudPhotoAssetDeletionIntentReceipt
    ) async throws {
        let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(
            intent.assetID
        )
        var state = try loadState().state
        guard let storedIntent = state.intents.first(where: {
            $0.intentID == intent.intentID
        }) else {
            try save(state)
            return
        }
        guard storedIntent.assetID == canonicalID else {
            throw CloudPhotoAssetContractError.invalidAssetID
        }
        state.intents.removeAll { $0.intentID == intent.intentID }
        try save(state)
    }

    public func clearCommittedDeletion(
        assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws {
        let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
        try validate(accountIdentity: accountIdentity)
        var state = try loadState().state
        state.intents.removeAll {
            $0.assetID == canonicalID && $0.accountIdentity == accountIdentity
        }
        try save(state)
    }

    private func loadState() throws -> (
        state: FileCloudPhotoAssetDeletionIntentState,
        requiresMigration: Bool
    ) {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return (.empty, false)
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        if let header = try? decoder.decode(
            FileCloudPhotoAssetDeletionIntentSchemaHeader.self,
            from: data
        ) {
            switch header.schemaVersion {
            case FileCloudPhotoAssetDeletionIntentState.currentSchemaVersion:
                guard let decoded = try? decoder.decode(
                    FileCloudPhotoAssetDeletionIntentState.self,
                    from: data
                ) else {
                    throw CloudPhotoAssetContractError.invalidAssetID
                }
                return (try validated(decoded), false)
            case 2:
                guard let legacy = try? decoder.decode(
                    FileCloudPhotoAssetDeletionIntentV2State.self,
                    from: data
                ) else {
                    throw CloudPhotoAssetContractError.invalidAssetID
                }
                return (
                    try migratedState(
                        accountAssetIDs: legacy.accountAssetIDs,
                        unresolvedAssetIDs: legacy.unresolvedAssetIDs,
                        quarantinedIntents: legacy.quarantinedIntents,
                        lastVerifiedAccountIdentity: legacy.lastVerifiedAccountIdentity
                    ),
                    true
                )
            case 1:
                guard let legacy = try? decoder.decode(
                    FileCloudPhotoAssetDeletionIntentV1State.self,
                    from: data
                ) else {
                    throw CloudPhotoAssetContractError.invalidAssetID
                }
                return (
                    try migratedState(
                        accountAssetIDs: legacy.accountAssetIDs,
                        unresolvedAssetIDs: legacy.unresolvedAssetIDs,
                        quarantinedIntents: [],
                        lastVerifiedAccountIdentity: nil
                    ),
                    true
                )
            default:
                throw CloudPhotoAssetContractError.invalidAssetID
            }
        }

        let legacyIDs = try decoder.decode([String].self, from: data)
        return (
            try migratedState(
                accountAssetIDs: [:],
                unresolvedAssetIDs: legacyIDs,
                quarantinedIntents: [],
                lastVerifiedAccountIdentity: nil
            ),
            true
        )
    }

    private func migratedState(
        accountAssetIDs: [String: [String]],
        unresolvedAssetIDs: [String],
        quarantinedIntents: [
            FileCloudPhotoAssetDeletionIntentV2QuarantinedIntent
        ],
        lastVerifiedAccountIdentity: String?
    ) throws -> FileCloudPhotoAssetDeletionIntentState {
        var intents: [FileCloudPhotoAssetDeletionIntentRecord] = []
        for accountIdentity in accountAssetIDs.keys.sorted() {
            try validate(accountIdentity: accountIdentity)
            for assetID in try validatedAssetIDs(
                accountAssetIDs[accountIdentity] ?? []
            ).sorted() {
                intents.append(
                    FileCloudPhotoAssetDeletionIntentRecord(
                        intentID: UUID(),
                        assetID: assetID,
                        accountIdentity: accountIdentity,
                        quarantineIdentityHint: nil
                    )
                )
            }
        }
        for assetID in try validatedAssetIDs(unresolvedAssetIDs).sorted() {
            intents.append(
                FileCloudPhotoAssetDeletionIntentRecord(
                    intentID: UUID(),
                    assetID: assetID,
                    accountIdentity: nil,
                    quarantineIdentityHint: nil
                )
            )
        }
        for legacyIntent in quarantinedIntents {
            try validate(accountIdentity: legacyIntent.accountIdentityHint)
            let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(
                legacyIntent.assetID
            )
            guard canonicalID == legacyIntent.assetID else {
                throw CloudPhotoAssetContractError.invalidAssetID
            }
            intents.append(
                FileCloudPhotoAssetDeletionIntentRecord(
                    intentID: UUID(),
                    assetID: canonicalID,
                    accountIdentity: nil,
                    quarantineIdentityHint: legacyIntent.accountIdentityHint
                )
            )
        }
        return try validated(
            FileCloudPhotoAssetDeletionIntentState(
                intents: intents,
                lastVerifiedAccountIdentity: lastVerifiedAccountIdentity
            )
        )
    }

    private func validated(
        _ state: FileCloudPhotoAssetDeletionIntentState
    ) throws -> FileCloudPhotoAssetDeletionIntentState {
        if let lastVerifiedAccountIdentity = state.lastVerifiedAccountIdentity {
            try validate(accountIdentity: lastVerifiedAccountIdentity)
        }
        var intentIDs = Set<UUID>()
        var intents: [FileCloudPhotoAssetDeletionIntentRecord] = []
        for intent in state.intents {
            let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(
                intent.assetID
            )
            guard canonicalID == intent.assetID,
                  intentIDs.insert(intent.intentID).inserted,
                  intent.accountIdentity == nil
                    || intent.quarantineIdentityHint == nil else {
                throw CloudPhotoAssetContractError.invalidAssetID
            }
            if let accountIdentity = intent.accountIdentity {
                try validate(accountIdentity: accountIdentity)
            }
            if let quarantineIdentityHint = intent.quarantineIdentityHint {
                try validate(accountIdentity: quarantineIdentityHint)
            }
            intents.append(intent)
        }
        return FileCloudPhotoAssetDeletionIntentState(
            intents: intents.sorted(),
            lastVerifiedAccountIdentity: state.lastVerifiedAccountIdentity
        )
    }

    private func validatedAssetIDs(_ assetIDs: [String]) throws -> Set<String> {
        var result = Set<String>()
        for assetID in assetIDs {
            let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
            guard canonicalID == assetID else {
                throw CloudPhotoAssetContractError.invalidAssetID
            }
            result.insert(canonicalID)
        }
        return result
    }

    private func validate(accountIdentity: String) throws {
        guard !accountIdentity.isEmpty else {
            throw CloudPhotoAssetDatabaseError.permanent
        }
    }

    private func save(_ state: FileCloudPhotoAssetDeletionIntentState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        #if targetEnvironment(simulator)
        try data.write(to: fileURL, options: .atomic)
        #else
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #endif
    }
}

private struct FileCloudPhotoAssetDeletionIntentState:
    Codable,
    Equatable,
    Sendable {
    static let currentSchemaVersion = 3
    static let empty = FileCloudPhotoAssetDeletionIntentState(
        intents: [],
        lastVerifiedAccountIdentity: nil
    )

    let schemaVersion: Int
    var intents: [FileCloudPhotoAssetDeletionIntentRecord]
    var lastVerifiedAccountIdentity: String?

    init(
        schemaVersion: Int = FileCloudPhotoAssetDeletionIntentState.currentSchemaVersion,
        intents: [FileCloudPhotoAssetDeletionIntentRecord],
        lastVerifiedAccountIdentity: String?
    ) {
        self.schemaVersion = schemaVersion
        self.intents = intents
        self.lastVerifiedAccountIdentity = lastVerifiedAccountIdentity
    }
}

private struct FileCloudPhotoAssetDeletionIntentRecord:
    Codable,
    Sendable,
    Comparable {
    let intentID: UUID
    let assetID: String
    var accountIdentity: String?
    var quarantineIdentityHint: String?

    static func < (
        lhs: FileCloudPhotoAssetDeletionIntentRecord,
        rhs: FileCloudPhotoAssetDeletionIntentRecord
    ) -> Bool {
        lhs.intentID.uuidString < rhs.intentID.uuidString
    }
}

private struct FileCloudPhotoAssetDeletionIntentV2State: Codable, Sendable {
    let schemaVersion: Int
    let accountAssetIDs: [String: [String]]
    let unresolvedAssetIDs: [String]
    let quarantinedIntents: [
        FileCloudPhotoAssetDeletionIntentV2QuarantinedIntent
    ]
    let lastVerifiedAccountIdentity: String?
}

private struct FileCloudPhotoAssetDeletionIntentV2QuarantinedIntent:
    Codable,
    Sendable {
    let assetID: String
    let accountIdentityHint: String
}

private struct FileCloudPhotoAssetDeletionIntentV1State: Codable, Sendable {
    let schemaVersion: Int
    let accountAssetIDs: [String: [String]]
    let unresolvedAssetIDs: [String]
}

private struct FileCloudPhotoAssetDeletionIntentSchemaHeader: Codable, Sendable {
    let schemaVersion: Int
}

public actor FileCloudPhotoAssetInboundJournal:
    CloudPhotoAssetInboundJournaling {
    private let storage: FileCloudPhotoAssetIDSetStorage
    private var cleanupLeasesByAssetID: [String: UUID] = [:]
    private var cleanupLeaseWaitersByAssetID: [
        String: [UUID: CheckedContinuation<Void, Error>]
    ] = [:]
    private var inboundRecordWaiterObserversByAssetID: [
        String: [CheckedContinuation<UUID, Never>]
    ] = [:]

    public init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        storage = FileCloudPhotoAssetIDSetStorage(
            fileURL: fileURL,
            fileManager: fileManager
        )
    }

    public func pendingInboundAssetIDs() async throws -> Set<String> {
        try storage.load()
    }

    public func loadInboundAssetIDs() async throws -> Set<String> {
        try storage.load()
    }

    public func acquireCleanupLease(
        for assetID: String
    ) async throws -> CloudPhotoAssetInboundCleanupLease? {
        try Task.checkCancellation()
        let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
        guard cleanupLeasesByAssetID[canonicalID] == nil,
              cleanupLeaseWaitersByAssetID[canonicalID]?.isEmpty != false else {
            return nil
        }
        let pending = try storage.load()
        guard !pending.contains(canonicalID) else { return nil }
        let lease = CloudPhotoAssetInboundCleanupLease(assetID: canonicalID)
        cleanupLeasesByAssetID[canonicalID] = lease.leaseID
        return lease
    }

    public func releaseCleanupLease(
        _ lease: CloudPhotoAssetInboundCleanupLease
    ) async {
        guard let canonicalID = try? CloudPhotoAssetRecordContract.canonicalAssetID(
            lease.assetID
        ), cleanupLeasesByAssetID[canonicalID] == lease.leaseID else {
            return
        }
        cleanupLeasesByAssetID.removeValue(forKey: canonicalID)
        let waiters = cleanupLeaseWaitersByAssetID.removeValue(
            forKey: canonicalID
        ) ?? [:]
        for waiter in waiters.values { waiter.resume(returning: ()) }
    }

    public func recordInboundAssetID(_ assetID: String) async throws {
        try Task.checkCancellation()
        let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
        while cleanupLeasesByAssetID[canonicalID] != nil {
            let waiterID = UUID()
            try await waitForCleanupLeaseRelease(
                for: canonicalID,
                waiterID: waiterID
            )
            try Task.checkCancellation()
        }
        try Task.checkCancellation()
        var pending = try storage.load()
        pending.insert(canonicalID)
        try storage.save(pending)
    }

    public func clearInboundAssetID(_ assetID: String) async throws {
        let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
        var pending = try storage.load()
        pending.remove(canonicalID)
        try storage.save(pending)
    }

    func waitForInboundRecordWaiter(for assetID: String) async throws -> UUID {
        let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
        if let waiterID = cleanupLeaseWaitersByAssetID[canonicalID]?.keys.min(
            by: { $0.uuidString < $1.uuidString }
        ) {
            return waiterID
        }
        return await withCheckedContinuation { continuation in
            inboundRecordWaiterObserversByAssetID[canonicalID, default: []]
                .append(continuation)
        }
    }

    func inboundRecordWaiterIDs(for assetID: String) async throws -> Set<UUID> {
        let canonicalID = try CloudPhotoAssetRecordContract.canonicalAssetID(assetID)
        guard let waiters = cleanupLeaseWaitersByAssetID[canonicalID] else {
            return []
        }
        return Set(waiters.keys)
    }

    private func waitForCleanupLeaseRelease(
        for assetID: String,
        waiterID: UUID
    ) async throws {
        try await withTaskCancellationHandler(
            operation: {
                try Task.checkCancellation()
                try await self.suspendInboundRecordWaiter(
                    for: assetID,
                    waiterID: waiterID
                )
            },
            onCancel: {
                Task {
                    await self.cancelInboundRecordWaiter(
                        for: assetID,
                        waiterID: waiterID
                    )
                }
            }
        )
    }

    private func suspendInboundRecordWaiter(
        for assetID: String,
        waiterID: UUID
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            cleanupLeaseWaitersByAssetID[assetID, default: [:]][waiterID] =
                continuation
            let observers = inboundRecordWaiterObserversByAssetID.removeValue(
                forKey: assetID
            ) ?? []
            for observer in observers {
                observer.resume(returning: waiterID)
            }
        }
    }

    private func cancelInboundRecordWaiter(
        for assetID: String,
        waiterID: UUID
    ) {
        guard var waiters = cleanupLeaseWaitersByAssetID[assetID],
              let continuation = waiters.removeValue(forKey: waiterID) else {
            return
        }
        if waiters.isEmpty {
            cleanupLeaseWaitersByAssetID.removeValue(forKey: assetID)
        } else {
            cleanupLeaseWaitersByAssetID[assetID] = waiters
        }
        continuation.resume(throwing: CancellationError())
    }
}

public actor EmptyCloudPhotoAssetReferenceSnapshotProvider:
    CloudPhotoAssetReferenceSnapshotProviding {
    public static let shared = EmptyCloudPhotoAssetReferenceSnapshotProvider()

    public init() {}

    public func snapshot() async throws -> CloudPhotoAssetReferenceSnapshot {
        CloudPhotoAssetReferenceSnapshot(referencedAssetIDs: [])
    }
}

public actor NoOpCloudPhotoAssetDeletionIntentStore:
    CloudPhotoAssetDeletionIntentStoring {
    public static let shared = NoOpCloudPhotoAssetDeletionIntentStore()
    private var activeAccountResolutionID: UUID?

    public init() {}

    public func beginAccountResolution() async -> CloudPhotoAssetAccountResolution {
        let resolution = CloudPhotoAssetAccountResolution()
        activeAccountResolutionID = resolution.resolutionID
        return resolution
    }

    public func activateAccountIdentity(
        _ accountIdentity: String,
        resolution: CloudPhotoAssetAccountResolution
    ) async throws -> CloudPhotoAssetAccountAuthorization {
        guard activeAccountResolutionID == resolution.resolutionID else {
            throw CancellationError()
        }
        activeAccountResolutionID = nil
        return CloudPhotoAssetAccountAuthorization(accountIdentity: accountIdentity)
    }

    public func suspendAccountAuthorization(
        _ authorization: CloudPhotoAssetAccountAuthorization
    ) async {
        _ = authorization
    }

    public func pendingDeletionIntents(
        forAccountIdentity accountIdentity: String
    ) async throws -> [CloudPhotoAssetDeletionIntentReceipt] {
        _ = accountIdentity
        return []
    }

    public func pendingDeletionAssetIDs(
        forAccountIdentity accountIdentity: String
    ) async throws -> Set<String> {
        _ = accountIdentity
        return []
    }

    public func unresolvedDeletionAssetIDs() async throws -> Set<String> { [] }

    public func hasCommittedLocalDeletionIntent(assetID: String) async throws -> Bool {
        _ = assetID
        return false
    }

    public func recordCommittedDeletion(
        assetID: String
    ) async throws -> CloudPhotoAssetDeletionIntentReceipt {
        CloudPhotoAssetDeletionIntentReceipt(
            assetID: assetID,
            accountIdentity: nil
        )
    }

    public func clearCommittedDeletion(
        _ intent: CloudPhotoAssetDeletionIntentReceipt
    ) async throws {
        _ = intent
    }

    public func clearCommittedDeletion(
        assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws {
        _ = assetID
        _ = accountIdentity
    }
}

public actor NoOpCloudPhotoAssetInboundJournal:
    CloudPhotoAssetInboundJournaling {
    public static let shared = NoOpCloudPhotoAssetInboundJournal()

    public init() {}

    public func pendingInboundAssetIDs() async throws -> Set<String> { [] }
    public func acquireCleanupLease(
        for assetID: String
    ) async throws -> CloudPhotoAssetInboundCleanupLease? {
        CloudPhotoAssetInboundCleanupLease(assetID: assetID)
    }
    public func releaseCleanupLease(
        _ lease: CloudPhotoAssetInboundCleanupLease
    ) async {
        _ = lease
    }
    public func recordInboundAssetID(_ assetID: String) async throws { _ = assetID }
    public func clearInboundAssetID(_ assetID: String) async throws { _ = assetID }
}

public actor DirectCloudPhotoAssetInboundApplier:
    CloudPhotoAssetInboundApplying {
    private let inboundAssetJournal: any CloudPhotoAssetInboundJournaling
    private let localStore: any CloudPhotoAssetLocalStoring
    private var activeInboundApplyLeases: [
        UUID: CloudPhotoAssetInboundApplyLease
    ] = [:]

    public init(
        inboundAssetJournal: any CloudPhotoAssetInboundJournaling,
        localStore: any CloudPhotoAssetLocalStoring
    ) {
        self.inboundAssetJournal = inboundAssetJournal
        self.localStore = localStore
    }

    public func prepareInboundApply(
        id assetID: String,
        forAccountIdentity accountIdentity: String
    ) async throws -> CloudPhotoAssetInboundApplyPreparation {
        guard !accountIdentity.isEmpty,
              try CloudPhotoAssetRecordContract.canonicalAssetID(assetID) == assetID
        else {
            throw CloudPhotoAssetContractError.invalidAssetID
        }
        let lease = CloudPhotoAssetInboundApplyLease(
            assetID: assetID,
            accountIdentity: accountIdentity
        )
        activeInboundApplyLeases[lease.leaseID] = lease
        return .prepared(lease)
    }

    public func commitInboundApply(
        _ lease: CloudPhotoAssetInboundApplyLease,
        bytes: Data
    ) async throws {
        guard activeInboundApplyLeases[lease.leaseID] == lease else {
            throw CloudPhotoAssetSyncError.invalidServerResponse
        }
        activeInboundApplyLeases.removeValue(forKey: lease.leaseID)
        try await inboundAssetJournal.recordInboundAssetID(lease.assetID)
        try Task.checkCancellation()
        try await localStore.restoreCloudAsset(id: lease.assetID, bytes: bytes)
    }

    public func cancelInboundApply(_ lease: CloudPhotoAssetInboundApplyLease) async {
        guard activeInboundApplyLeases[lease.leaseID] == lease else { return }
        activeInboundApplyLeases.removeValue(forKey: lease.leaseID)
    }
}

private final class FileCloudPhotoAssetIDSetStorage: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> Set<String> {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let identifiers = try JSONDecoder().decode([String].self, from: data)
        for identifier in identifiers {
            guard try CloudPhotoAssetRecordContract.canonicalAssetID(identifier)
                == identifier else {
                throw CloudPhotoAssetContractError.invalidAssetID
            }
        }
        return Set(identifiers)
    }

    func save(_ identifiers: Set<String>) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(identifiers.sorted())
        #if targetEnvironment(simulator)
        try data.write(to: fileURL, options: .atomic)
        #else
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #endif
    }
}

public final class CloudPhotoAssetFileHandleFactory:
    CloudPhotoAssetFileHandleOpening,
    @unchecked Sendable {
    public init() {}

    public func openForReading(
        at sourceURL: URL
    ) throws -> any CloudPhotoAssetReadHandling {
        FileCloudPhotoAssetHandle(
            handle: try FileHandle(forReadingFrom: sourceURL)
        )
    }

    public func openForWriting(
        at destinationURL: URL
    ) throws -> any CloudPhotoAssetWriteHandling {
        FileCloudPhotoAssetHandle(
            handle: try FileHandle(forWritingTo: destinationURL)
        )
    }
}

private final class FileCloudPhotoAssetHandle:
    CloudPhotoAssetReadHandling,
    CloudPhotoAssetWriteHandling,
    @unchecked Sendable {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func read(upToCount count: Int) throws -> Data? {
        try handle.read(upToCount: count)
    }

    func write(contentsOf data: Data) throws {
        try handle.write(contentsOf: data)
    }

    func close() throws {
        try handle.close()
    }
}

public final class FileCloudPhotoAssetTemporaryStore: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager
    private let makeID: @Sendable () -> UUID
    private let fileHandleFactory: any CloudPhotoAssetFileHandleOpening

    public init(
        directory: URL,
        fileManager: FileManager = .default,
        makeID: @escaping @Sendable () -> UUID = { UUID() },
        fileHandleFactory: any CloudPhotoAssetFileHandleOpening = CloudPhotoAssetFileHandleFactory()
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.makeID = makeID
        self.fileHandleFactory = fileHandleFactory
        sweepStaleTransfers()
    }

    public func createUploadFile(bytes: Data) throws -> URL {
        let url = try makeOwnedURL()
        do {
            try writeProtected(bytes, to: url)
            return url
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    public func copyDownloadedFile(from source: URL) throws -> URL {
        let destination = try makeOwnedURL()
        do {
            try copyFile(
                from: source,
                to: destination,
                maximumBytes: PhotoAssetPolicy.production.maximumInputBytes
            )
            return destination
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    public func readFile(at url: URL) throws -> Data {
        try readFile(
            at: url,
            maximumBytes: PhotoAssetPolicy.production.maximumInputBytes
        )
    }

    public func readFile(at url: URL, maximumBytes: Int) throws -> Data {
        precondition(maximumBytes > 0)
        guard isOwned(url) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let reader = try fileHandleFactory.openForReading(at: url)
        var bytes = Data()
        var remaining = maximumBytes
        do {
            while true {
                let chunk = try reader.read(
                    upToCount: min(remaining + 1, 64 * 1_024)
                ) ?? Data()
                guard !chunk.isEmpty else { break }
                guard chunk.count <= remaining else {
                    throw CloudPhotoAssetValidationError.exceedsMaximumBytes(
                        maximumBytes: maximumBytes
                    )
                }
                bytes.append(chunk)
                remaining -= chunk.count
            }
        } catch {
            try? reader.close()
            throw error
        }
        try reader.close()
        return bytes
    }

    public func stageDownload(
        recordName: String,
        assetID: String,
        checksum: String,
        byteCount: Int,
        systemFileURL: URL,
        maximumBytes: Int
    ) throws -> CloudPhotoAssetDownloadRecord {
        precondition(maximumBytes > 0)
        let metadata = try CloudPhotoAssetRecordMetadata(
            recordName: recordName,
            assetID: assetID,
            checksum: checksum,
            byteCount: byteCount
        )
        guard metadata.byteCount <= maximumBytes else {
            throw CloudPhotoAssetValidationError.exceedsMaximumBytes(
                maximumBytes: maximumBytes
            )
        }

        let destination = try makeOwnedURL()
        do {
            let result = try copyValidatedDownload(
                from: systemFileURL,
                to: destination,
                expectedChecksum: metadata.checksum,
                expectedByteCount: metadata.byteCount,
                maximumBytes: maximumBytes
            )
            guard result.byteCount == metadata.byteCount else {
                throw CloudPhotoAssetValidationError.byteCountMismatch(
                    expected: metadata.byteCount,
                    actual: result.byteCount
                )
            }
            guard result.checksum == metadata.checksum else {
                throw CloudPhotoAssetValidationError.checksumMismatch
            }
            return try CloudPhotoAssetDownloadRecord(
                recordName: metadata.recordName,
                assetID: metadata.assetID,
                checksum: metadata.checksum,
                byteCount: metadata.byteCount,
                stagedFileURL: destination
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    public func removeFile(at url: URL) {
        guard isOwned(url) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func makeOwnedURL() throws -> URL {
        try prepareDirectory()
        let url = directory.appendingPathComponent(
            makeID().uuidString.lowercased() + ".asset"
        )
        guard !fileManager.fileExists(atPath: url.path),
              fileManager.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            #if !targetEnvironment(simulator)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
            #endif
            return url
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        #if !targetEnvironment(simulator)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directory.path
        )
        #endif
    }

    private func writeProtected(_ bytes: Data, to url: URL) throws {
        #if targetEnvironment(simulator)
        try bytes.write(to: url, options: .atomic)
        #else
        try bytes.write(
            to: url,
            options: [.atomic, .completeFileProtection]
        )
        #endif
    }

    private func copyValidatedDownload(
        from source: URL,
        to destination: URL,
        expectedChecksum: String,
        expectedByteCount: Int,
        maximumBytes: Int
    ) throws -> (byteCount: Int, checksum: String) {
        let reader = try fileHandleFactory.openForReading(at: source)
        let writer: any CloudPhotoAssetWriteHandling
        do {
            writer = try fileHandleFactory.openForWriting(at: destination)
        } catch {
            try? reader.close()
            throw error
        }
        let result: (byteCount: Int, checksum: String)
        do {
            var remaining = maximumBytes
            var byteCount = 0
            var hasher = SHA256()
            while true {
                let chunk = try reader.read(upToCount: remaining + 1) ?? Data()
                guard !chunk.isEmpty else { break }
                guard chunk.count <= remaining else {
                    if remaining > 0 {
                        let boundedChunk = Data(chunk.prefix(remaining))
                        try writer.write(contentsOf: boundedChunk)
                    }
                    throw CloudPhotoAssetValidationError.exceedsMaximumBytes(
                        maximumBytes: maximumBytes
                    )
                }
                try writer.write(contentsOf: chunk)
                hasher.update(data: chunk)
                byteCount += chunk.count
                remaining -= chunk.count
            }
            guard byteCount == expectedByteCount else {
                throw CloudPhotoAssetValidationError.byteCountMismatch(
                    expected: expectedByteCount,
                    actual: byteCount
                )
            }
            let checksum = hasher.finalize()
                .map { String(format: "%02x", $0) }
                .joined()
            guard checksum == expectedChecksum else {
                throw CloudPhotoAssetValidationError.checksumMismatch
            }
            result = (byteCount, checksum)
        } catch {
            try? close(reader: reader, writer: writer)
            throw error
        }
        try close(reader: reader, writer: writer)
        return result
    }

    private func copyFile(
        from source: URL,
        to destination: URL,
        maximumBytes: Int
    ) throws {
        let reader = try fileHandleFactory.openForReading(at: source)
        let writer: any CloudPhotoAssetWriteHandling
        do {
            writer = try fileHandleFactory.openForWriting(at: destination)
        } catch {
            try? reader.close()
            throw error
        }
        do {
            var remaining = maximumBytes
            while true {
                let chunk = try reader.read(
                    upToCount: min(remaining + 1, 64 * 1_024)
                ) ?? Data()
                guard !chunk.isEmpty else { break }
                guard chunk.count <= remaining else {
                    throw CloudPhotoAssetValidationError.exceedsMaximumBytes(
                        maximumBytes: maximumBytes
                    )
                }
                try writer.write(contentsOf: chunk)
                remaining -= chunk.count
            }
        } catch {
            try? close(reader: reader, writer: writer)
            throw error
        }
        try close(reader: reader, writer: writer)
    }

    private func close(
        reader: any CloudPhotoAssetReadHandling,
        writer: any CloudPhotoAssetWriteHandling
    ) throws {
        var closeError: Error?
        do {
            try writer.close()
        } catch {
            closeError = error
        }
        do {
            try reader.close()
        } catch {
            if closeError == nil {
                closeError = error
            }
        }
        if let closeError {
            throw closeError
        }
    }

    private func sweepStaleTransfers() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ) else { return }
        for url in contents where isCanonicalTransferFileName(
            url.lastPathComponent
        ) {
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true else {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }

    private func isOwned(_ url: URL) -> Bool {
        let standardizedRoot = directory.standardizedFileURL
        let standardizedCandidate = url.standardizedFileURL
        guard standardizedCandidate.deletingLastPathComponent()
            == standardizedRoot,
        isCanonicalTransferFileName(standardizedCandidate.lastPathComponent) else {
            return false
        }
        guard let originalValues = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]),
        originalValues.isRegularFile == true,
        originalValues.isSymbolicLink != true else {
            return false
        }
        let ownedRoot = standardizedRoot.resolvingSymlinksInPath()
        let candidate = standardizedCandidate.resolvingSymlinksInPath()
        return candidate.deletingLastPathComponent() == ownedRoot
    }

    private func isCanonicalTransferFileName(_ fileName: String) -> Bool {
        let suffix = ".asset"
        guard fileName.hasSuffix(suffix) else { return false }
        let identifier = String(fileName.dropLast(suffix.count))
        guard let uuid = UUID(uuidString: identifier) else { return false }
        return uuid.uuidString.lowercased() == identifier
    }
}

public actor NoOpCloudPhotoAssetCoordinator: CloudPhotoAssetSynchronizing {
    public static let shared = NoOpCloudPhotoAssetCoordinator()

    public init() {}

    public func synchronize() async -> CloudPhotoAssetSyncOutcome {
        .synchronized
    }
}
