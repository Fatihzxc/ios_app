import Darwin
import Foundation

enum ReportExportDescriptorBoundary: Sendable {
    case allocationDirectoryCreated
    case allocationDirectorySecured
    case markerPublication
    case payloadWrite
    case payloadStageCreated
    case payloadStageBeforeUnlink
    case markerRead
    case recursiveCleanup
    case recursiveEntryMetadata
    case recursiveEntryOpened
    case recursiveEntryBeforeUnlink
}

struct ReportExportDescriptorCreationResidue: Error {
    let root: ReportExportDescriptorRoot
    let entryName: String
    let originalError: any Error
}

protocol ReportExportDescriptorTemporaryFileSystem: ReportExportTemporaryFileSystem {
    var descriptorBackend: FileManagerReportExportTemporaryFileSystem { get }
    func reachDescriptorBoundary(_ boundary: ReportExportDescriptorBoundary) throws
}

extension FileManagerReportExportTemporaryFileSystem: ReportExportDescriptorTemporaryFileSystem {
    var descriptorBackend: FileManagerReportExportTemporaryFileSystem { self }
    func reachDescriptorBoundary(_ boundary: ReportExportDescriptorBoundary) throws {
        _ = boundary
    }
}

enum ReportExportDescriptorCleanupResult: Sendable {
    case removed
    case stale
}

struct ReportExportCleanupRecoveryRecord: Sendable {
    let cleanupID: UUID
    let rootDirectory: URL
    let rootIdentity: ReportExportFileIdentity
    let ownedEntryName: String
    let ownedIdentity: ReportExportFileIdentity
    let marker: Data
    let requiresMarker: Bool
}

/// Public Darwin exposes the descriptor commands but keeps the C protection-class
/// macros behind a private header. Apple File System Reference defines class A as
/// complete protection; keep that semantic encoding named and verify it by reading
/// the class back from the same descriptor after every write.
private enum ReportExportDarwinProtectionClass: Int32, Sendable {
    case complete = 1
}

final class ReportExportFileDescriptor: @unchecked Sendable {
    let rawValue: Int32

    init(taking rawValue: Int32) {
        self.rawValue = rawValue
    }

    func duplicate() throws -> ReportExportFileDescriptor {
        let duplicated = Darwin.dup(rawValue)
        guard duplicated >= 0 else { throw ReportExportDescriptorIO.currentPOSIXError() }
        return ReportExportFileDescriptor(taking: duplicated)
    }

    deinit {
        _ = Darwin.close(rawValue)
    }
}

/// Serializes the short, synchronous namespace transactions owned by ReportsKit.
///
/// The lock is never held across an `await`. Visible root/allocation entries are
/// protected between transactions by an owner-only mode and Darwin's owner-settable
/// `UF_APPEND | UF_IMMUTABLE` flags. Destructive or creation mutations temporarily
/// clear them only inside this authority; staging uses a bounded append-only window.
/// The invariant is validated from held descriptors. This is an iOS sandbox/process authority
/// boundary, not a claim that an arbitrary same-UID process unable to cooperate
/// with this authority cannot clear user flags.
final class ReportExportNamespaceAuthority: @unchecked Sendable {
    static let shared = ReportExportNamespaceAuthority()

    private let lock = NSRecursiveLock()

    @discardableResult
    func transaction<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

final class ReportExportRootNamespaceLease: @unchecked Sendable {
    private let identity: ReportExportFileIdentity
    private let lock = NSLock()
    private var active = true

    init(identity: ReportExportFileIdentity) { self.identity = identity }

    func release() throws {
        lock.lock()
        defer { lock.unlock() }
        guard active else {
            return
        }
        try ReportExportRootNamespaceRegistry.shared.release(identity)
        active = false
    }

    deinit { try? release() }
}

/// Identity-keyed root ownership. The first lease records the exact incoming
/// mode/flags; the last restores that baseline even when unrelated root entries
/// exist. Failed restores retain the held descriptor in this bounded registry
/// and receive a finite automatic retry sequence.
final class ReportExportRootNamespaceRegistry: @unchecked Sendable {
    static let shared = ReportExportRootNamespaceRegistry()

    private struct Entry {
        let descriptor: ReportExportFileDescriptor
        let identity: ReportExportFileIdentity
        let originalMode: mode_t
        let originalFlags: UInt32
        var references: Int
        var restoreAttempts: Int
        var restoreScheduled: Bool
    }

    private let lock = NSLock()
    private var entries: [ReportExportFileIdentity: Entry] = [:]
    private let maximumEntries = 64
    private let maximumRestoreAttempts = 8

    func acquire(_ descriptor: ReportExportFileDescriptor) throws
        -> ReportExportRootNamespaceLease {
        try ReportExportNamespaceAuthority.shared.transaction {
            let current = try ReportExportDescriptorIO.metadata(for: descriptor.rawValue)
            guard current.isDirectory, current.owner == Darwin.geteuid() else {
                throw ReportExportError.unsafeTemporaryPath
            }

            lock.lock()
            if var existing = entries[current.identity] {
                lock.unlock()
                try ReportExportDescriptorIO.establishPrivateDirectory(descriptor.rawValue)
                lock.lock()
                existing = entries[current.identity] ?? existing
                existing.references += 1
                existing.restoreAttempts = 0
                existing.restoreScheduled = false
                entries[current.identity] = existing
                lock.unlock()
                return ReportExportRootNamespaceLease(identity: current.identity)
            }
            guard entries.count < maximumEntries else {
                lock.unlock()
                throw ReportExportError.temporaryStorageFailed
            }
            lock.unlock()

            let retained = try descriptor.duplicate()
            do {
                try ReportExportDescriptorIO.establishPrivateDirectory(descriptor.rawValue)
            } catch {
                do {
                    try Self.restore(
                        descriptor: descriptor,
                        identity: current.identity,
                        mode: current.permissionMode,
                        flags: current.flags
                    )
                } catch {
                    lock.lock()
                    entries[current.identity] = Entry(
                        descriptor: retained,
                        identity: current.identity,
                        originalMode: current.permissionMode,
                        originalFlags: current.flags,
                        references: 0,
                        restoreAttempts: 0,
                        restoreScheduled: false
                    )
                    lock.unlock()
                    scheduleRestore(current.identity)
                }
                throw error
            }
            lock.lock()
            entries[current.identity] = Entry(
                descriptor: retained,
                identity: current.identity,
                originalMode: current.permissionMode,
                originalFlags: current.flags,
                references: 1,
                restoreAttempts: 0,
                restoreScheduled: false
            )
            lock.unlock()
            return ReportExportRootNamespaceLease(identity: current.identity)
        }
    }

    func release(_ identity: ReportExportFileIdentity) throws {
        try ReportExportNamespaceAuthority.shared.transaction {
            lock.lock()
            guard var entry = entries[identity], entry.references > 0 else {
                lock.unlock()
                return
            }
            entry.references -= 1
            entries[identity] = entry
            lock.unlock()
            guard entry.references == 0 else { return }
            do {
                try Self.restore(
                    descriptor: entry.descriptor,
                    identity: entry.identity,
                    mode: entry.originalMode,
                    flags: entry.originalFlags
                )
                lock.lock()
                if entries[identity]?.references == 0 { entries.removeValue(forKey: identity) }
                lock.unlock()
            } catch {
                scheduleRestore(identity)
                throw error
            }
        }
    }

    private func scheduleRestore(_ identity: ReportExportFileIdentity) {
        lock.lock()
        guard var entry = entries[identity], entry.references == 0,
              !entry.restoreScheduled,
              entry.restoreAttempts < maximumRestoreAttempts else {
            lock.unlock()
            return
        }
        entry.restoreScheduled = true
        entries[identity] = entry
        let attempt = entry.restoreAttempts
        lock.unlock()
        let delay = UInt64(100_000_000 * (attempt + 1))
        Task.detached { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            self?.retryRestore(identity)
        }
    }

    private func retryRestore(_ identity: ReportExportFileIdentity) {
        do {
            try ReportExportNamespaceAuthority.shared.transaction {
                lock.lock()
                guard var entry = entries[identity], entry.references == 0 else {
                    lock.unlock()
                    return
                }
                entry.restoreScheduled = false
                lock.unlock()
                do {
                    try Self.restore(
                        descriptor: entry.descriptor,
                        identity: entry.identity,
                        mode: entry.originalMode,
                        flags: entry.originalFlags
                    )
                    lock.lock()
                    if entries[identity]?.references == 0 {
                        entries.removeValue(forKey: identity)
                    }
                    lock.unlock()
                } catch {
                    lock.lock()
                    if var current = entries[identity], current.references == 0 {
                        current.restoreAttempts += 1
                        entries[identity] = current
                    }
                    lock.unlock()
                    throw error
                }
            }
        } catch {
            scheduleRestore(identity)
        }
    }

    private static func restore(
        descriptor: ReportExportFileDescriptor,
        identity: ReportExportFileIdentity,
        mode: mode_t,
        flags: UInt32
    ) throws {
        let current = try ReportExportDescriptorIO.metadata(for: descriptor.rawValue)
        guard current.identity == identity, current.isDirectory else {
            throw ReportExportError.cleanupIdentityMismatch
        }
        try ReportExportDescriptorIO.setNamespaceProtection(false, on: descriptor.rawValue)
        guard Darwin.fchmod(descriptor.rawValue, mode) == 0,
              Darwin.fchflags(descriptor.rawValue, flags) == 0 else {
            throw ReportExportDescriptorIO.currentPOSIXError()
        }
        let restored = try ReportExportDescriptorIO.metadata(for: descriptor.rawValue)
        guard restored.identity == identity,
              restored.permissionMode == mode,
              restored.flags == flags else {
            throw ReportExportError.cleanupIdentityMismatch
        }
    }
}

/// Bounded authorization for zero-byte staging names that could not be unlinked.
/// Every bound record retains the exact parent and stage descriptors plus the one
/// original name. Recovery never scans by URL or inode, so a later name replacement
/// or inode reuse cannot authorize removal. Terminal records keep those descriptors
/// and consume capacity until the exact stage reaches link count zero.
final class ReportExportStageResidueRegistry: @unchecked Sendable {
    static let shared = ReportExportStageResidueRegistry()

    private struct Entry {
        let id: UUID
        var parent: ReportExportFileDescriptor?
        var parentIdentity: ReportExportFileIdentity?
        var originalParentFlags: UInt32?
        var visibleName: String?
        var stage: ReportExportFileDescriptor?
        var attempts: Int
        var scheduled: Bool
        var terminal: Bool
        var onResolution: (@Sendable () -> Void)?
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private let scheduler: any ReportExportCleanupScheduling
    private let maximumCount: Int
    private let maximumAttempts = 8
    private let delays: [UInt64] = [
        100_000_000, 150_000_000, 200_000_000, 250_000_000,
        500_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000,
    ]

    convenience init() {
        self.init(scheduler: SystemReportExportCleanupScheduler())
    }

    init(
        scheduler: any ReportExportCleanupScheduling,
        maximumCount: Int = 64
    ) {
        self.scheduler = scheduler
        self.maximumCount = maximumCount
    }

    var retainedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func reserve() throws -> UUID {
        retryTerminals()
        lock.lock()
        defer { lock.unlock() }
        guard entries.count < maximumCount else {
            throw ReportExportError.temporaryStorageFailed
        }
        let id = UUID()
        entries[id] = Entry(
            id: id,
            parent: nil,
            parentIdentity: nil,
            originalParentFlags: nil,
            visibleName: nil,
            stage: nil,
            attempts: 0,
            scheduled: false,
            terminal: false,
            onResolution: nil
        )
        return id
    }

    func release(_ id: UUID) {
        lock.lock()
        entries.removeValue(forKey: id)
        lock.unlock()
    }

    func bindParent(
        _ id: UUID,
        parent: ReportExportFileDescriptor,
        visibleName: String
    ) {
        lock.lock()
        if var entry = entries[id] {
            entry.parent = parent
            entry.visibleName = visibleName
            entries[id] = entry
        }
        lock.unlock()
    }

    func recordParentBaseline(
        _ id: UUID,
        identity: ReportExportFileIdentity,
        flags: UInt32
    ) {
        lock.lock()
        if var entry = entries[id] {
            entry.parentIdentity = identity
            entry.originalParentFlags = flags
            entries[id] = entry
        }
        lock.unlock()
    }

    func attachStage(_ id: UUID, descriptor: ReportExportFileDescriptor) {
        lock.lock()
        if var entry = entries[id] {
            entry.stage = descriptor
            entries[id] = entry
        }
        lock.unlock()
    }

    @discardableResult
    func setResolutionAction(
        _ id: UUID,
        action: @escaping @Sendable () -> Void
    ) -> Bool {
        lock.lock()
        guard var entry = entries[id] else {
            lock.unlock()
            return false
        }
        entry.onResolution = action
        entries[id] = entry
        lock.unlock()
        return true
    }

    func retain(_ id: UUID) {
        schedule(id)
    }

    private func retryTerminals() {
        lock.lock()
        let pending = entries.values.filter(\.terminal).map(\.id)
        lock.unlock()
        for id in pending {
            retry(id, scheduleAfterFailure: false)
        }
    }

    private func schedule(_ id: UUID) {
        lock.lock()
        guard var entry = entries[id], !entry.scheduled, !entry.terminal else {
            lock.unlock()
            return
        }
        entry.scheduled = true
        entries[id] = entry
        let delay = delays[min(entry.attempts, delays.count - 1)]
        lock.unlock()
        scheduler.schedule(afterNanoseconds: delay) { [weak self] in
            self?.retry(id, scheduleAfterFailure: true)
        }
    }

    private func retry(_ id: UUID, scheduleAfterFailure: Bool) {
        lock.lock()
        guard var entry = entries[id] else {
            lock.unlock()
            return
        }
        entry.scheduled = false
        entries[id] = entry
        lock.unlock()

        do {
            try ReportExportNamespaceAuthority.shared.transaction {
                try Self.cleanup(entry)
            }
            lock.lock()
            let action = entries.removeValue(forKey: id)?.onResolution
            lock.unlock()
            action?()
        } catch {
            lock.lock()
            guard var current = entries[id] else {
                lock.unlock()
                return
            }
            current.attempts += 1
            current.terminal = current.attempts >= maximumAttempts
            entries[id] = current
            let shouldSchedule = scheduleAfterFailure && !current.terminal
            lock.unlock()
            if shouldSchedule { schedule(id) }
        }
    }

    private static func cleanup(_ entry: Entry) throws {
        guard let parent = entry.parent else { return }
        let currentParent = try ReportExportDescriptorIO.metadata(for: parent.rawValue)
        guard currentParent.isDirectory, currentParent.owner == Darwin.geteuid() else {
            throw ReportExportError.cleanupIdentityMismatch
        }
        if let expectedParent = entry.parentIdentity,
           currentParent.identity != expectedParent {
            throw ReportExportError.cleanupIdentityMismatch
        }
        guard let originalFlags = entry.originalParentFlags else {
            guard entry.stage == nil else { throw ReportExportError.cleanupIdentityMismatch }
            return
        }
        guard let stage = entry.stage, let visibleName = entry.visibleName else {
            try ReportExportDescriptorIO.setFlags(
                originalFlags,
                on: parent.rawValue,
                expectedIdentity: currentParent.identity
            )
            return
        }

        var stageMetadata = try ReportExportDescriptorIO.metadata(for: stage.rawValue)
        guard stageMetadata.isRegularFile,
              stageMetadata.owner == Darwin.geteuid(),
              stageMetadata.byteCount == 0 else {
            throw ReportExportError.cleanupIdentityMismatch
        }
        if stageMetadata.permissions != (S_IRUSR | S_IWUSR) {
            guard Darwin.fchmod(stage.rawValue, S_IRUSR | S_IWUSR) == 0 else {
                throw ReportExportDescriptorIO.currentPOSIXError()
            }
            let secured = try ReportExportDescriptorIO.metadata(for: stage.rawValue)
            guard secured.identity == stageMetadata.identity,
                  secured.isRegularFile,
                  secured.owner == Darwin.geteuid(),
                  secured.permissions == (S_IRUSR | S_IWUSR),
                  secured.byteCount == 0 else {
                throw ReportExportError.cleanupIdentityMismatch
            }
            stageMetadata = secured
        }

        let appendOnlyFlags = (originalFlags
            & ~ReportExportDescriptorIO.namespaceProtectionFlags) | UInt32(UF_APPEND)
        try ReportExportDescriptorIO.setFlags(
            appendOnlyFlags,
            on: parent.rawValue,
            expectedIdentity: currentParent.identity
        )

        do {
            let visible: ReportExportDescriptorIO.Metadata?
            do {
                visible = try ReportExportDescriptorIO.metadata(
                    at: visibleName,
                    relativeTo: parent.rawValue
                )
            } catch let error as POSIXError where error.code == .ENOENT {
                visible = nil
            }
            guard let visible, visible.identity == stageMetadata.identity else {
                try ReportExportDescriptorIO.setFlags(
                    originalFlags,
                    on: parent.rawValue,
                    expectedIdentity: currentParent.identity
                )
                let refreshed = try ReportExportDescriptorIO.metadata(for: stage.rawValue)
                guard refreshed.linkCount == 0 else {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                return
            }
            guard visible.isRegularFile, visible.byteCount == 0 else {
                throw ReportExportError.cleanupIdentityMismatch
            }

            if stageMetadata.flags & ReportExportDescriptorIO.namespaceProtectionFlags != 0 {
                try ReportExportDescriptorIO.setFlags(
                    stageMetadata.flags & ~ReportExportDescriptorIO.namespaceProtectionFlags,
                    on: stage.rawValue,
                    expectedIdentity: stageMetadata.identity
                )
            }
            // This is the only clear-to-unlink interval. `createAnonymousFile` admits
            // only an app-owned private parent, the namespace authority is held, the
            // same stage FD and exact original name were just matched, and there is no
            // callback between this flag change and `unlinkat`.
            let removalFlags = originalFlags
                & ~ReportExportDescriptorIO.namespaceProtectionFlags
            try ReportExportDescriptorIO.setFlags(
                removalFlags,
                on: parent.rawValue,
                expectedIdentity: currentParent.identity
            )
            var unlinkResult: Int32
            repeat {
                unlinkResult = visibleName.withCString {
                    Darwin.unlinkat(parent.rawValue, $0, 0)
                }
            } while unlinkResult != 0 && errno == EINTR
            let unlinkError = unlinkResult == 0
                ? nil
                : ReportExportDescriptorIO.currentPOSIXError()
            try ReportExportDescriptorIO.setFlags(
                originalFlags,
                on: parent.rawValue,
                expectedIdentity: currentParent.identity
            )
            if let unlinkError { throw unlinkError }
            guard try ReportExportDescriptorIO.metadata(for: stage.rawValue).linkCount == 0 else {
                throw ReportExportError.cleanupIdentityMismatch
            }
        } catch let operationError {
            do {
                try ReportExportDescriptorIO.setFlags(
                    originalFlags,
                    on: parent.rawValue,
                    expectedIdentity: currentParent.identity
                )
            } catch {
                throw error
            }
            throw operationError
        }
    }
}

struct ReportExportDescriptorEntry: Sendable {
    let parent: ReportExportFileDescriptor
    let name: String
    let descriptor: ReportExportFileDescriptor
    let identity: ReportExportFileIdentity

    func validate() throws {
        let metadata = try ReportExportDescriptorIO.metadata(
            at: name,
            relativeTo: parent.rawValue
        )
        guard metadata.identity == identity, metadata.isDirectory else {
            throw ReportExportError.unsafeTemporaryPath
        }
    }
}

struct ReportExportDescriptorRoot: Sendable {
    let presentationURL: URL
    let entry: ReportExportDescriptorEntry
    let namespaceLease: ReportExportRootNamespaceLease

    var descriptor: ReportExportFileDescriptor { entry.descriptor }
    var identity: ReportExportFileIdentity { entry.identity }

    func validate() throws {
        try entry.validate()
        try ReportExportDescriptorIO.validatePrivateDirectory(descriptor.rawValue)
    }

    func releaseNamespaceLease() throws { try namespaceLease.release() }
}

final class ReportExportDescriptorAllocation: @unchecked Sendable {
    private enum Phase {
        case owned(String)
        case quarantined(String)
        case removed
    }

    let root: ReportExportDescriptorRoot
    let presentationURL: URL
    let descriptor: ReportExportFileDescriptor
    let identity: ReportExportFileIdentity
    let marker: Data

    private let lock = NSLock()
    private var phase: Phase
    private var markerWasPublished = false

    init(
        root: ReportExportDescriptorRoot,
        presentationURL: URL,
        entryName: String,
        descriptor: ReportExportFileDescriptor,
        identity: ReportExportFileIdentity,
        marker: Data
    ) {
        self.root = root
        self.presentationURL = presentationURL
        self.descriptor = descriptor
        self.identity = identity
        self.marker = marker
        phase = .owned(entryName)
    }

    var currentEntryName: String? {
        lock.lock()
        defer { lock.unlock() }
        switch phase {
        case let .owned(name), let .quarantined(name): return name
        case .removed: return nil
        }
    }

    var isQuarantined: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .quarantined = phase { return true }
        return false
    }

    var wasMarkerPublished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return markerWasPublished
    }

    func markMarkerPublished() {
        lock.lock()
        markerWasPublished = true
        lock.unlock()
    }

    func markQuarantined(as name: String) {
        lock.lock()
        phase = .quarantined(name)
        lock.unlock()
    }

    func markRemoved() {
        lock.lock()
        phase = .removed
        lock.unlock()
    }

    func recoveryRecord(cleanupID: UUID) -> ReportExportCleanupRecoveryRecord? {
        lock.lock()
        defer { lock.unlock() }
        let name: String
        let requiresMarker: Bool
        switch phase {
        case let .owned(current):
            name = current
            requiresMarker = markerWasPublished
        case let .quarantined(current):
            name = current
            requiresMarker = false
        case .removed:
            return nil
        }
        return ReportExportCleanupRecoveryRecord(
            cleanupID: cleanupID,
            rootDirectory: root.presentationURL,
            rootIdentity: root.identity,
            ownedEntryName: name,
            ownedIdentity: identity,
            marker: marker,
            requiresMarker: requiresMarker
        )
    }
}

/// Test-injectable owner for bounded restoration of flags on caller-owned ZIP
/// destination directories. Unlike the allocation-root registry, this authority
/// never changes a caller directory's permission mode.
final class ReportExportVisibleDirectoryRegistry: @unchecked Sendable {
    static let shared = ReportExportVisibleDirectoryRegistry()

    private struct Entry {
        let descriptor: ReportExportFileDescriptor
        let identity: ReportExportFileIdentity
        let originalMode: mode_t
        let originalFlags: UInt32
        var references: Int
        var restoreAttempts: Int
        var restoreScheduled: Bool
    }

    private let lock = NSLock()
    private var entries: [ReportExportFileIdentity: Entry] = [:]
    private let scheduler: any ReportExportCleanupScheduling
    private let maximumEntries: Int
    private let beforeRestore: @Sendable () throws -> Void
    private let maximumRestoreAttempts = 8
    private let retryDelays: [UInt64] = [
        100_000_000, 150_000_000, 200_000_000, 250_000_000,
        500_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000,
    ]

    convenience init() {
        self.init(scheduler: SystemReportExportCleanupScheduler())
    }

    init(
        scheduler: any ReportExportCleanupScheduling,
        maximumEntries: Int = 64,
        beforeRestore: @escaping @Sendable () throws -> Void = {}
    ) {
        self.scheduler = scheduler
        self.maximumEntries = maximumEntries
        self.beforeRestore = beforeRestore
    }

    var retainedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func acquire(_ descriptor: ReportExportFileDescriptor) throws
        -> ReportExportFileIdentity {
        try ReportExportNamespaceAuthority.shared.transaction {
            let current = try ReportExportDescriptorIO.metadata(for: descriptor.rawValue)
            guard current.isDirectory, current.owner == Darwin.geteuid() else {
                throw ReportExportError.unsafeTemporaryPath
            }

            lock.lock()
            if var existing = entries[current.identity] {
                guard existing.references > 0 else {
                    lock.unlock()
                    throw ReportExportError.temporaryStorageFailed
                }
                existing.references += 1
                entries[current.identity] = existing
                lock.unlock()
                do {
                    let verified = try ReportExportDescriptorIO.metadata(
                        for: descriptor.rawValue
                    )
                    guard verified.identity == current.identity, verified.hasNoUnlink else {
                        throw ReportExportError.unsafeTemporaryPath
                    }
                    return current.identity
                } catch {
                    try? release(current.identity)
                    throw error
                }
            }
            guard entries.count < maximumEntries else {
                lock.unlock()
                throw ReportExportError.temporaryStorageFailed
            }
            lock.unlock()

            let retained = try descriptor.duplicate()
            lock.lock()
            entries[current.identity] = Entry(
                descriptor: retained,
                identity: current.identity,
                originalMode: current.permissionMode,
                originalFlags: current.flags,
                references: 0,
                restoreAttempts: 0,
                restoreScheduled: false
            )
            lock.unlock()

            do {
                try ReportExportDescriptorIO.setNoUnlink(true, on: descriptor.rawValue)
                let verified = try ReportExportDescriptorIO.metadata(for: descriptor.rawValue)
                guard verified.identity == current.identity,
                      verified.permissionMode == current.permissionMode,
                      verified.hasNoUnlink else {
                    throw ReportExportError.unsafeTemporaryPath
                }
                lock.lock()
                if var entry = entries[current.identity] {
                    entry.references = 1
                    entries[current.identity] = entry
                }
                lock.unlock()
                return current.identity
            } catch let operationError {
                do {
                    try restore(current.identity, invokeSeam: false)
                    removeIfUnreferenced(current.identity)
                } catch {
                    recordRestoreFailure(current.identity)
                }
                throw operationError
            }
        }
    }

    func validate(
        _ identity: ReportExportFileIdentity,
        descriptor: ReportExportFileDescriptor
    ) throws {
        let current = try ReportExportDescriptorIO.metadata(for: descriptor.rawValue)
        guard current.identity == identity,
              current.isDirectory,
              current.owner == Darwin.geteuid(),
              current.hasNoUnlink else {
            throw ReportExportError.unsafeTemporaryPath
        }
        lock.lock()
        let isOwned = (entries[identity]?.references ?? 0) > 0
        lock.unlock()
        guard isOwned else { throw ReportExportError.unsafeTemporaryPath }
    }

    func release(_ identity: ReportExportFileIdentity) throws {
        try ReportExportNamespaceAuthority.shared.transaction {
            lock.lock()
            guard var entry = entries[identity], entry.references > 0 else {
                lock.unlock()
                return
            }
            entry.references -= 1
            entries[identity] = entry
            lock.unlock()
            guard entry.references == 0 else { return }
            do {
                try restore(identity, invokeSeam: true)
                removeIfUnreferenced(identity)
            } catch {
                recordRestoreFailure(identity)
                throw error
            }
        }
    }

    private func restore(
        _ identity: ReportExportFileIdentity,
        invokeSeam: Bool
    ) throws {
        lock.lock()
        guard let entry = entries[identity], entry.references == 0 else {
            lock.unlock()
            return
        }
        lock.unlock()
        if invokeSeam { try beforeRestore() }
        let current = try ReportExportDescriptorIO.metadata(for: entry.descriptor.rawValue)
        guard current.identity == entry.identity,
              current.isDirectory,
              current.owner == Darwin.geteuid(),
              current.permissionMode == entry.originalMode else {
            throw ReportExportError.cleanupIdentityMismatch
        }
        try ReportExportDescriptorIO.setFlags(
            entry.originalFlags,
            on: entry.descriptor.rawValue,
            expectedIdentity: entry.identity
        )
        let restored = try ReportExportDescriptorIO.metadata(for: entry.descriptor.rawValue)
        guard restored.identity == entry.identity,
              restored.permissionMode == entry.originalMode,
              restored.flags == entry.originalFlags else {
            throw ReportExportError.cleanupIdentityMismatch
        }
    }

    private func removeIfUnreferenced(_ identity: ReportExportFileIdentity) {
        lock.lock()
        if entries[identity]?.references == 0 {
            entries.removeValue(forKey: identity)
        }
        lock.unlock()
    }

    private func recordRestoreFailure(_ identity: ReportExportFileIdentity) {
        lock.lock()
        guard var entry = entries[identity], entry.references == 0 else {
            lock.unlock()
            return
        }
        entry.restoreAttempts += 1
        entries[identity] = entry
        lock.unlock()
        scheduleRestore(identity)
    }

    private func scheduleRestore(_ identity: ReportExportFileIdentity) {
        lock.lock()
        guard var entry = entries[identity], entry.references == 0,
              !entry.restoreScheduled,
              entry.restoreAttempts < maximumRestoreAttempts else {
            lock.unlock()
            return
        }
        entry.restoreScheduled = true
        entries[identity] = entry
        let delay = retryDelays[min(entry.restoreAttempts, retryDelays.count - 1)]
        lock.unlock()
        scheduler.schedule(afterNanoseconds: delay) { [weak self] in
            self?.retryRestore(identity)
        }
    }

    private func retryRestore(_ identity: ReportExportFileIdentity) {
        do {
            try ReportExportNamespaceAuthority.shared.transaction {
                lock.lock()
                guard var entry = entries[identity], entry.references == 0 else {
                    lock.unlock()
                    return
                }
                entry.restoreScheduled = false
                entries[identity] = entry
                lock.unlock()
                do {
                    try restore(identity, invokeSeam: true)
                    removeIfUnreferenced(identity)
                } catch {
                    recordRestoreFailure(identity)
                    throw error
                }
            }
        } catch {
            scheduleRestore(identity)
        }
    }
}

final class StoredZIPDestinationBinding: @unchecked Sendable {
    let url: URL
    let fileName: String
    let parentDescriptor: ReportExportFileDescriptor
    let requiresPrivateInvariant: Bool
    private let validateAction: @Sendable () throws -> Void

    init(
        url: URL,
        fileName: String,
        parentDescriptor: ReportExportFileDescriptor,
        requiresPrivateInvariant: Bool = false,
        validate: @escaping @Sendable () throws -> Void
    ) {
        self.url = url
        self.fileName = fileName
        self.parentDescriptor = parentDescriptor
        self.requiresPrivateInvariant = requiresPrivateInvariant
        validateAction = validate
    }

    func validate() throws { try validateAction() }

    func destinationExists() throws -> Bool {
        do {
            _ = try ReportExportDescriptorIO.metadata(
                at: fileName,
                relativeTo: parentDescriptor.rawValue
            )
            return true
        } catch let error as POSIXError where error.code == .ENOENT {
            return false
        }
    }

    func acquireNamespaceLease(
        registry: ReportExportVisibleDirectoryRegistry = .shared
    ) throws -> ReportExportVisibleDirectoryLease {
        try ReportExportVisibleDirectoryLease(
            descriptor: parentDescriptor,
            restorationRegistry: registry
        )
    }
}

final class ReportExportVisibleDirectoryLease: @unchecked Sendable {
    private let descriptor: ReportExportFileDescriptor
    private let restorationRegistry: ReportExportVisibleDirectoryRegistry
    private let identity: ReportExportFileIdentity
    private let lock = NSLock()
    private var active = true

    init(
        descriptor: ReportExportFileDescriptor,
        restorationRegistry: ReportExportVisibleDirectoryRegistry = .shared
    ) throws {
        self.descriptor = descriptor
        self.restorationRegistry = restorationRegistry
        identity = try restorationRegistry.acquire(descriptor)
    }

    func validate() throws {
        try ReportExportNamespaceAuthority.shared.transaction {
            try restorationRegistry.validate(identity, descriptor: descriptor)
        }
    }

    func release() throws {
        lock.lock()
        defer { lock.unlock() }
        guard active else {
            return
        }
        active = false
        try restorationRegistry.release(identity)
    }

    deinit { try? release() }
}

struct ReportExportDescriptorDirectoryChain: Sendable {
    let entries: [ReportExportDescriptorEntry]
    let finalDescriptor: ReportExportFileDescriptor

    func validate() throws {
        for entry in entries {
            try entry.validate()
            try ReportExportDescriptorIO.validatePrivateDirectory(entry.descriptor.rawValue)
        }
    }
}

enum ReportExportDescriptorIO {
    static let namespaceProtectionFlags = UInt32(UF_APPEND | UF_IMMUTABLE)

    struct Metadata: Sendable {
        let identity: ReportExportFileIdentity
        let mode: mode_t
        let owner: uid_t
        let linkCount: nlink_t
        let byteCount: off_t
        let flags: UInt32

        var isDirectory: Bool { mode & S_IFMT == S_IFDIR }
        var isRegularFile: Bool { mode & S_IFMT == S_IFREG }
        var isSymbolicLink: Bool { mode & S_IFMT == S_IFLNK }
        var permissions: mode_t { mode & mode_t(0o777) }
        var permissionMode: mode_t { mode & mode_t(0o7777) }
        var hasNoUnlink: Bool {
            flags & ReportExportDescriptorIO.namespaceProtectionFlags
                == ReportExportDescriptorIO.namespaceProtectionFlags
        }
    }

    static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    static func metadata(for descriptor: Int32) throws -> Metadata {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else { throw currentPOSIXError() }
        return Metadata(
            identity: ReportExportFileIdentity(
                device: UInt64(truncatingIfNeeded: status.st_dev),
                inode: UInt64(truncatingIfNeeded: status.st_ino)
            ),
            mode: status.st_mode,
            owner: status.st_uid,
            linkCount: status.st_nlink,
            byteCount: status.st_size,
            flags: status.st_flags
        )
    }

    static func metadata(at name: String, relativeTo descriptor: Int32) throws -> Metadata {
        var status = stat()
        let result = name.withCString {
            Darwin.fstatat(descriptor, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0 else { throw currentPOSIXError() }
        return Metadata(
            identity: ReportExportFileIdentity(
                device: UInt64(truncatingIfNeeded: status.st_dev),
                inode: UInt64(truncatingIfNeeded: status.st_ino)
            ),
            mode: status.st_mode,
            owner: status.st_uid,
            linkCount: status.st_nlink,
            byteCount: status.st_size,
            flags: status.st_flags
        )
    }

    static func establishPrivateDirectory(_ descriptor: Int32) throws {
        var current = try metadata(for: descriptor)
        guard current.isDirectory, current.owner == Darwin.geteuid() else {
            throw ReportExportError.unsafeTemporaryPath
        }
        if current.permissionMode != S_IRWXU {
            let wasProtected = current.hasNoUnlink
            if wasProtected { try setNamespaceProtection(false, on: descriptor) }
            guard Darwin.fchmod(descriptor, S_IRWXU) == 0 else {
                if wasProtected { try? setNamespaceProtection(true, on: descriptor) }
                throw currentPOSIXError()
            }
            if wasProtected { try setNamespaceProtection(true, on: descriptor) }
            current = try metadata(for: descriptor)
        }
        if !current.hasNoUnlink { try setNamespaceProtection(true, on: descriptor) }
        try validatePrivateDirectory(descriptor)
    }

    static func establishPrivateFile(_ descriptor: Int32) throws {
        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            throw currentPOSIXError()
        }
        try setNamespaceProtection(true, on: descriptor)
        let current = try metadata(for: descriptor)
        guard current.isRegularFile,
              current.owner == Darwin.geteuid(),
              current.permissions == (S_IRUSR | S_IWUSR),
              current.hasNoUnlink else {
            throw ReportExportError.unsafeTemporaryPath
        }
    }

    static func validatePrivateDirectory(_ descriptor: Int32) throws {
        let current = try metadata(for: descriptor)
        guard current.isDirectory,
              current.owner == Darwin.geteuid(),
              current.permissionMode == S_IRWXU,
              current.hasNoUnlink else {
            throw ReportExportError.unsafeTemporaryPath
        }
    }

    static func setNoUnlink(_ enabled: Bool, on descriptor: Int32) throws {
        try setNamespaceProtection(enabled, on: descriptor)
    }

    static func setNamespaceProtection(_ enabled: Bool, on descriptor: Int32) throws {
        let current = try metadata(for: descriptor)
        // Darwin reserves `UF_NOUNLINK`; the owner-settable combination below
        // keeps an entry immovable and its directory append-only between the
        // authority's short creation/removal transactions.
        let updated = enabled
            ? current.flags | namespaceProtectionFlags
            : current.flags & ~namespaceProtectionFlags
        try setFlags(updated, on: descriptor, expectedIdentity: current.identity)
        guard try metadata(for: descriptor).hasNoUnlink == enabled else {
            throw ReportExportError.unsafeTemporaryPath
        }
    }

    static func setFlags(
        _ flags: UInt32,
        on descriptor: Int32,
        expectedIdentity: ReportExportFileIdentity
    ) throws {
        guard Darwin.fchflags(descriptor, flags) == 0 else { throw currentPOSIXError() }
        let updated = try metadata(for: descriptor)
        guard updated.identity == expectedIdentity, updated.flags == flags else {
            throw ReportExportError.unsafeTemporaryPath
        }
    }

    @discardableResult
    static func withRemovalAllowed<T>(
        in directory: Int32,
        requirePrivateInvariant: Bool = true,
        _ operation: () throws -> T
    ) throws -> T {
        let before = try metadata(for: directory)
        guard before.isDirectory,
              before.owner == Darwin.geteuid(),
              (!requirePrivateInvariant || before.hasNoUnlink) else {
            throw ReportExportError.unsafeTemporaryPath
        }
        if before.hasNoUnlink { try setNoUnlink(false, on: directory) }
        do {
            let result = try operation()
            let after = try metadata(for: directory)
            guard after.identity == before.identity, after.isDirectory else {
                throw ReportExportError.unsafeTemporaryPath
            }
            if before.hasNoUnlink { try setNoUnlink(true, on: directory) }
            return result
        } catch {
            if before.hasNoUnlink { try? setNoUnlink(true, on: directory) }
            throw error
        }
    }

    /// Opens only a creation window: `UF_APPEND` stays set, so the verified
    /// directory cannot be renamed or lose entries while descriptor-bound clone
    /// publication executes. The exact incoming flags are restored afterward.
    @discardableResult
    static func withCreationAllowed<T>(
        in directory: Int32,
        _ operation: () throws -> T
    ) throws -> T {
        let before = try metadata(for: directory)
        guard before.isDirectory,
              before.owner == Darwin.geteuid(),
              before.hasNoUnlink else {
            throw ReportExportError.unsafeTemporaryPath
        }
        let creationFlags = (before.flags & ~UInt32(UF_IMMUTABLE)) | UInt32(UF_APPEND)
        try setFlags(
            creationFlags,
            on: directory,
            expectedIdentity: before.identity
        )
        do {
            let result = try operation()
            let during = try metadata(for: directory)
            guard during.identity == before.identity,
                  during.isDirectory,
                  during.flags & UInt32(UF_APPEND) != 0 else {
                throw ReportExportError.unsafeTemporaryPath
            }
            try setFlags(
                before.flags,
                on: directory,
                expectedIdentity: before.identity
            )
            return result
        } catch let operationError {
            do {
                try setFlags(
                    before.flags,
                    on: directory,
                    expectedIdentity: before.identity
                )
            } catch {
                throw error
            }
            throw operationError
        }
    }

    static func openDirectory(at name: String, relativeTo descriptor: Int32) throws
        -> ReportExportFileDescriptor {
        let opened = name.withCString {
            Darwin.openat(
                descriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard opened >= 0 else { throw currentPOSIXError() }
        let result = ReportExportFileDescriptor(taking: opened)
        guard try metadata(for: opened).isDirectory else {
            throw ReportExportError.unsafeTemporaryPath
        }
        return result
    }

    static func openRegularFile(at name: String, relativeTo descriptor: Int32) throws
        -> ReportExportFileDescriptor {
        let opened = name.withCString {
            Darwin.openat(descriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard opened >= 0 else { throw currentPOSIXError() }
        let result = ReportExportFileDescriptor(taking: opened)
        guard try metadata(for: opened).isRegularFile else {
            throw ReportExportError.unsafeTemporaryPath
        }
        return result
    }

    static func openDirectoryTree(_ url: URL) throws -> ReportExportFileDescriptor {
        guard url.isFileURL, url.standardizedFileURL.path.hasPrefix("/") else {
            throw ReportExportError.unsafeTemporaryPath
        }
        let root = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard root >= 0 else { throw currentPOSIXError() }
        var current = ReportExportFileDescriptor(taking: root)
        for component in url.standardizedFileURL.pathComponents where component != "/" {
            current = try openDirectory(at: component, relativeTo: current.rawValue)
        }
        return current
    }

    static func makeEntry(
        at url: URL,
        createIfMissing: Bool
    ) throws -> ReportExportDescriptorEntry {
        let parentURL = url.deletingLastPathComponent().standardizedFileURL
            .resolvingSymlinksInPath()
        let parent = try openDirectoryTree(parentURL)
        let name = url.lastPathComponent
        try ReportExportWorkspace.validate(relativePath: name)
        if createIfMissing {
            let result = name.withCString {
                Darwin.mkdirat(parent.rawValue, $0, S_IRWXU)
            }
            if result != 0, errno != EEXIST { throw currentPOSIXError() }
        }
        let descriptor = try openDirectory(at: name, relativeTo: parent.rawValue)
        let metadata = try metadata(for: descriptor.rawValue)
        return ReportExportDescriptorEntry(
            parent: parent,
            name: name,
            descriptor: descriptor,
            identity: metadata.identity
        )
    }

    static func validate(
        allocation: ReportExportDescriptorAllocation,
        chain: ReportExportDescriptorDirectoryChain? = nil
    ) throws {
        try ReportExportNamespaceAuthority.shared.transaction {
            try allocation.root.validate()
            try validatePrivateDirectory(allocation.descriptor.rawValue)
            guard let entryName = allocation.currentEntryName else {
                throw ReportExportError.cleanupIdentityMismatch
            }
            let current = try metadata(
                at: entryName,
                relativeTo: allocation.root.descriptor.rawValue
            )
            guard current.identity == allocation.identity,
                  current.isDirectory,
                  current.owner == Darwin.geteuid(),
                  current.permissionMode == S_IRWXU,
                  current.hasNoUnlink else {
                throw ReportExportError.unsafeTemporaryPath
            }
            try chain?.validate()
        }
    }

    static func createAnonymousFile(
        in parent: Int32,
        parentURL: URL,
        visibleName: String,
        privateParent: Bool,
        registry: ReportExportStageResidueRegistry = .shared,
        afterOpenBeforeMetadata: @escaping @Sendable () throws -> Void = {},
        beforeUnlink: @escaping @Sendable () throws -> Void = {},
        beforeUnlinkOperation: @escaping @Sendable () throws -> Void = {},
        afterResidueResolution: @escaping @Sendable () -> Void = {}
    ) throws -> ReportExportFileDescriptor {
        let reservation: UUID
        do {
            reservation = try registry.reserve()
        } catch {
            afterResidueResolution()
            throw error
        }
        guard registry.setResolutionAction(
            reservation,
            action: afterResidueResolution
        ) else {
            afterResidueResolution()
            throw ReportExportError.temporaryStorageFailed
        }
        let retainedParent: ReportExportFileDescriptor
        do {
            retainedParent = ReportExportFileDescriptor(
                taking: try checkedDuplicate(parent)
            )
        } catch {
            registry.release(reservation)
            afterResidueResolution()
            throw error
        }
        registry.bindParent(
            reservation,
            parent: retainedParent,
            visibleName: visibleName
        )
        _ = parentURL
        do {
            return try ReportExportNamespaceAuthority.shared.transaction {
                guard privateParent else {
                    throw ReportExportError.unsafeTemporaryPath
                }
                let parentMetadata = try metadata(for: parent)
                guard parentMetadata.isDirectory,
                      parentMetadata.owner == Darwin.geteuid(),
                      parentMetadata.hasNoUnlink else {
                    throw ReportExportError.unsafeTemporaryPath
                }
                registry.recordParentBaseline(
                    reservation,
                    identity: parentMetadata.identity,
                    flags: parentMetadata.flags
                )
                let appendOnlyFlags = (parentMetadata.flags & ~namespaceProtectionFlags)
                    | UInt32(UF_APPEND)
                try setFlags(
                    appendOnlyFlags,
                    on: parent,
                    expectedIdentity: parentMetadata.identity
                )
                let opened = visibleName.withCString {
                    Darwin.openat(
                        parent,
                        $0,
                        O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                        S_IRUSR | S_IWUSR
                    )
                }
                guard opened >= 0 else { throw currentPOSIXError() }
                let descriptor = ReportExportFileDescriptor(taking: opened)
                // Ownership is retained before the first fallible metadata read.
                registry.attachStage(reservation, descriptor: descriptor)
                guard Darwin.fchmod(opened, S_IRUSR | S_IWUSR) == 0 else {
                    throw currentPOSIXError()
                }
                try afterOpenBeforeMetadata()
                let initial = try metadata(for: opened)
                guard initial.isRegularFile,
                      initial.owner == Darwin.geteuid(),
                      initial.permissions == (S_IRUSR | S_IWUSR),
                      initial.linkCount == 1,
                      initial.byteCount == 0 else {
                    throw ReportExportError.unsafeTemporaryPath
                }
                try beforeUnlink()
                let before = try metadata(for: opened)
                let visible = try metadata(at: visibleName, relativeTo: parent)
                guard before.identity == initial.identity,
                      before.isRegularFile,
                      before.owner == Darwin.geteuid(),
                      before.permissions == (S_IRUSR | S_IWUSR),
                      before.linkCount == 1,
                      before.byteCount == 0,
                      visible.identity == initial.identity,
                      visible.isRegularFile,
                      visible.byteCount == 0 else {
                    throw ReportExportError.unsafeTemporaryPath
                }

                // The injectable boundary runs while the parent remains append-only.
                // No callback exists between the final same-FD/name check and unlink.
                try beforeUnlinkOperation()
                let finalStage = try metadata(for: opened)
                let finalVisible = try metadata(at: visibleName, relativeTo: parent)
                guard finalStage.identity == initial.identity,
                      finalStage.isRegularFile,
                      finalStage.owner == Darwin.geteuid(),
                      finalStage.permissions == (S_IRUSR | S_IWUSR),
                      finalStage.linkCount == 1,
                      finalStage.byteCount == 0,
                      finalVisible.identity == initial.identity,
                      finalVisible.isRegularFile,
                      finalVisible.byteCount == 0 else {
                    throw ReportExportError.unsafeTemporaryPath
                }
                do {
                    let unlinkFlags = parentMetadata.flags & ~namespaceProtectionFlags
                    try setFlags(
                        unlinkFlags,
                        on: parent,
                        expectedIdentity: parentMetadata.identity
                    )
                    var result: Int32
                    repeat {
                        result = visibleName.withCString { Darwin.unlinkat(parent, $0, 0) }
                    } while result != 0 && errno == EINTR
                    guard result == 0 else { throw currentPOSIXError() }
                    try setFlags(
                        parentMetadata.flags,
                        on: parent,
                        expectedIdentity: parentMetadata.identity
                    )
                } catch {
                    try? setFlags(
                        parentMetadata.flags,
                        on: parent,
                        expectedIdentity: parentMetadata.identity
                    )
                    throw error
                }
                let anonymous = try metadata(for: opened)
                guard anonymous.identity == initial.identity,
                      anonymous.isRegularFile,
                      anonymous.owner == Darwin.geteuid(),
                      anonymous.permissions == (S_IRUSR | S_IWUSR),
                      anonymous.linkCount == 0,
                      anonymous.byteCount == 0 else {
                    throw ReportExportError.unsafeTemporaryPath
                }
                registry.release(reservation)
                return descriptor
            }
        } catch {
            registry.retain(reservation)
            throw error
        }
    }

    private static func checkedDuplicate(_ descriptor: Int32) throws -> Int32 {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else { throw currentPOSIXError() }
        return duplicate
    }

    static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    bytes.baseAddress!.advanced(by: offset),
                    bytes.count - offset
                )
                if written < 0 {
                    if errno == EINTR { continue }
                    throw currentPOSIXError()
                }
                guard written > 0 else { throw POSIXError(.EIO) }
                offset += written
            }
        }
        guard Darwin.fsync(descriptor) == 0 else { throw currentPOSIXError() }
    }

    static func clone(
        sourceDescriptor: Int32,
        to name: String,
        in parentDescriptor: Int32
    ) throws {
        let result = name.withCString {
            Darwin.fclonefileat(sourceDescriptor, parentDescriptor, $0, 0)
        }
        guard result == 0 else { throw currentPOSIXError() }
    }

    static func readFile(at name: String, relativeTo parent: Int32) throws
        -> (Data, ReportExportFileIdentity) {
        let opened = name.withCString {
            Darwin.openat(parent, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard opened >= 0 else { throw currentPOSIXError() }
        let descriptor = ReportExportFileDescriptor(taking: opened)
        let metadata = try metadata(for: opened)
        guard metadata.isRegularFile else { throw ReportExportError.cleanupIdentityMismatch }
        let handle = FileHandle(fileDescriptor: descriptor.rawValue, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        return (data, metadata.identity)
    }

    static func directoryNames(_ descriptor: Int32) throws -> [String] {
        let original = try metadata(for: descriptor)
        guard original.isDirectory else { throw ReportExportError.unsafeTemporaryPath }
        let independent = ".".withCString {
            Darwin.openat(
                descriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard independent >= 0 else { throw currentPOSIXError() }
        do {
            let reopened = try metadata(for: independent)
            guard reopened.identity == original.identity, reopened.isDirectory else {
                throw ReportExportError.unsafeTemporaryPath
            }
        } catch {
            _ = Darwin.close(independent)
            throw error
        }
        guard let stream = Darwin.fdopendir(independent) else {
            let failure = currentPOSIXError()
            _ = Darwin.close(independent)
            throw failure
        }
        defer { Darwin.closedir(stream) }
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = Darwin.readdir(stream) else {
                if errno != 0 { throw currentPOSIXError() }
                break
            }
            var storage = entry.pointee.d_name
            let name = withUnsafeBytes(of: &storage) {
                String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name != ".", name != ".." { result.append(name) }
        }
        return result.sorted()
    }

    static func removeContents(
        of descriptor: Int32,
        beforeBoundary: @escaping @Sendable (ReportExportDescriptorBoundary) throws -> Void = { _ in }
    ) throws {
        for name in try directoryNames(descriptor) {
            let quarantined = try ReportExportNamespaceAuthority.shared.transaction {
                let initial = try metadata(at: name, relativeTo: descriptor)
                guard initial.owner == Darwin.geteuid(),
                      initial.hasNoUnlink,
                      (initial.isDirectory
                        ? initial.permissionMode == S_IRWXU
                        : initial.isRegularFile
                            && initial.permissions == (S_IRUSR | S_IWUSR)) else {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                try beforeBoundary(.recursiveEntryMetadata)
                let opened = try openEntry(
                    at: name,
                    relativeTo: descriptor,
                    metadata: initial
                )
                guard try metadata(for: opened.rawValue).identity == initial.identity else {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                try setNoUnlink(false, on: opened.rawValue)
                let quarantine = ".cleanup-\(UUID().uuidString.lowercased())"
                let renameResult = try withRemovalAllowed(in: descriptor) {
                    name.withCString { source in
                        quarantine.withCString { destination in
                            Darwin.renameatx_np(
                                descriptor,
                                source,
                                descriptor,
                                destination,
                                UInt32(RENAME_EXCL)
                            )
                        }
                    }
                }
                if renameResult != 0 {
                    try? setNoUnlink(true, on: opened.rawValue)
                    throw currentPOSIXError()
                }
                try setNoUnlink(true, on: opened.rawValue)
                let moved = try metadata(at: quarantine, relativeTo: descriptor)
                guard moved.identity == initial.identity else {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                try beforeBoundary(.recursiveEntryOpened)
                let reopened = try openEntry(
                    at: quarantine,
                    relativeTo: descriptor,
                    metadata: moved
                )
                guard try metadata(for: reopened.rawValue).identity == moved.identity else {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                return (quarantine, moved, reopened)
            }
            if quarantined.1.isDirectory {
                try removeContents(
                    of: quarantined.2.rawValue,
                    beforeBoundary: beforeBoundary
                )
                try removeEntry(
                    quarantined.0,
                    relativeTo: descriptor,
                    expectedIdentity: quarantined.1.identity,
                    flags: AT_REMOVEDIR,
                    beforeUnlink: { try beforeBoundary(.recursiveEntryBeforeUnlink) }
                )
            } else {
                try removeEntry(
                    quarantined.0,
                    relativeTo: descriptor,
                    expectedIdentity: quarantined.1.identity,
                    flags: 0,
                    beforeUnlink: { try beforeBoundary(.recursiveEntryBeforeUnlink) }
                )
            }
        }
    }

    static func openEntry(
        at name: String,
        relativeTo parent: Int32,
        metadata: Metadata
    ) throws -> ReportExportFileDescriptor {
        let typeFlag = metadata.isDirectory ? O_DIRECTORY : 0
        let opened = name.withCString {
            Darwin.openat(parent, $0, O_RDONLY | typeFlag | O_NOFOLLOW | O_CLOEXEC)
        }
        guard opened >= 0 else { throw currentPOSIXError() }
        let result = ReportExportFileDescriptor(taking: opened)
        let openedMetadata = try self.metadata(for: opened)
        guard openedMetadata.identity == metadata.identity,
              openedMetadata.isDirectory == metadata.isDirectory,
              openedMetadata.isRegularFile == metadata.isRegularFile else {
            throw ReportExportError.cleanupIdentityMismatch
        }
        return result
    }

    static func removeEntry(
        _ name: String,
        relativeTo parent: Int32,
        expectedIdentity: ReportExportFileIdentity,
        flags: Int32,
        requirePrivateInvariant: Bool = true,
        beforeUnlink: @escaping @Sendable () throws -> Void = {}
    ) throws {
        try ReportExportNamespaceAuthority.shared.transaction {
            let current = try metadata(at: name, relativeTo: parent)
            guard current.identity == expectedIdentity,
                  current.owner == Darwin.geteuid(),
                  (!requirePrivateInvariant || current.hasNoUnlink) else {
                throw ReportExportError.cleanupIdentityMismatch
            }
            let opened = try openEntry(at: name, relativeTo: parent, metadata: current)
            if !current.hasNoUnlink { try setNoUnlink(true, on: opened.rawValue) }
            try beforeUnlink()
            guard try metadata(for: opened.rawValue).identity == expectedIdentity else {
                throw ReportExportError.cleanupIdentityMismatch
            }
            try setNoUnlink(false, on: opened.rawValue)
            let result = try withRemovalAllowed(in: parent) {
                name.withCString { Darwin.unlinkat(parent, $0, flags) }
            }
            if result != 0 {
                try? setNoUnlink(true, on: opened.rawValue)
                throw currentPOSIXError()
            }
        }
    }
}

extension FileManagerReportExportTemporaryFileSystem {
    func bindOrCreateDescriptorRoot(at url: URL) throws -> ReportExportDescriptorRoot {
        try bindDescriptorRoot(at: url, createIfMissing: true)
    }

    private func bindDescriptorRoot(
        at url: URL,
        createIfMissing: Bool
    ) throws -> ReportExportDescriptorRoot {
        try ReportExportNamespaceAuthority.shared.transaction {
            let entry = try ReportExportDescriptorIO.makeEntry(
                at: url,
                createIfMissing: createIfMissing
            )
            let lease = try ReportExportRootNamespaceRegistry.shared.acquire(entry.descriptor)
            do {
                try applyDescriptorSecurity(to: entry.descriptor)
            } catch {
                try? lease.release()
                throw error
            }
            return ReportExportDescriptorRoot(
                presentationURL: url,
                entry: entry,
                namespaceLease: lease
            )
        }
    }

    func createDescriptorAllocation(
        in root: ReportExportDescriptorRoot,
        directoryName: String,
        marker: Data,
        afterMkdir: @escaping @Sendable () throws -> Void = {},
        afterSecurity: @escaping @Sendable () throws -> Void = {}
    ) throws -> ReportExportDescriptorAllocation {
        try ReportExportNamespaceAuthority.shared.transaction {
            try root.validate()
            let result = try ReportExportDescriptorIO.withRemovalAllowed(
                in: root.descriptor.rawValue
            ) {
                directoryName.withCString {
                    Darwin.mkdirat(root.descriptor.rawValue, $0, S_IRWXU)
                }
            }
            guard result == 0 else { throw ReportExportDescriptorIO.currentPOSIXError() }
            do {
                try afterMkdir()
                let descriptor = try ReportExportDescriptorIO.openDirectory(
                    at: directoryName,
                    relativeTo: root.descriptor.rawValue
                )
                try ReportExportDescriptorIO.establishPrivateDirectory(descriptor.rawValue)
                try afterSecurity()
                let metadata = try ReportExportDescriptorIO.metadata(for: descriptor.rawValue)
                return ReportExportDescriptorAllocation(
                    root: root,
                    presentationURL: root.presentationURL.appendingPathComponent(
                        directoryName,
                        isDirectory: true
                    ),
                    entryName: directoryName,
                    descriptor: descriptor,
                    identity: metadata.identity,
                    marker: marker
                )
            } catch {
                let removalResult = directoryName.withCString {
                    Darwin.unlinkat(root.descriptor.rawValue, $0, AT_REMOVEDIR)
                }
                if removalResult != 0, errno != ENOENT {
                    throw ReportExportDescriptorCreationResidue(
                        root: root,
                        entryName: directoryName,
                        originalError: error
                    )
                }
                try root.releaseNamespaceLease()
                throw error
            }
        }
    }

    func applyDescriptorSecurity(to descriptor: ReportExportFileDescriptor) throws {
        let before = try ReportExportDescriptorIO.metadata(for: descriptor.rawValue)
        let wasProtected = before.hasNoUnlink
        if wasProtected {
            try ReportExportDescriptorIO.setNamespaceProtection(
                false,
                on: descriptor.rawValue
            )
        }
        do {
            #if targetEnvironment(simulator)
            _ = descriptor
            #else
            guard Darwin.fcntl(
                descriptor.rawValue,
                F_SETPROTECTIONCLASS,
                ReportExportDarwinProtectionClass.complete.rawValue
            ) == 0 else { throw ReportExportDescriptorIO.currentPOSIXError() }
            let appliedProtectionClass = Darwin.fcntl(
                descriptor.rawValue,
                F_GETPROTECTIONCLASS
            )
            guard appliedProtectionClass >= 0 else {
                throw ReportExportDescriptorIO.currentPOSIXError()
            }
            guard appliedProtectionClass == ReportExportDarwinProtectionClass.complete.rawValue else {
                throw ReportExportError.temporaryStorageFailed
            }

            var excluded: UInt8 = 1
            let result = "com.apple.MobileBackup".withCString { attribute in
                withUnsafePointer(to: &excluded) { value in
                    Darwin.fsetxattr(
                        descriptor.rawValue,
                        attribute,
                        value,
                        MemoryLayout<UInt8>.size,
                        0,
                        0
                    )
                }
            }
            guard result == 0 || errno == ENOTSUP || errno == EOPNOTSUPP else {
                throw ReportExportDescriptorIO.currentPOSIXError()
            }
            #endif
            guard try ReportExportDescriptorIO.metadata(for: descriptor.rawValue).identity
                    == before.identity else {
                throw ReportExportError.unsafeTemporaryPath
            }
            if wasProtected {
                try ReportExportDescriptorIO.setNamespaceProtection(
                    true,
                    on: descriptor.rawValue
                )
            }
        } catch {
            if wasProtected {
                try? ReportExportDescriptorIO.setNamespaceProtection(
                    true,
                    on: descriptor.rawValue
                )
            }
            throw error
        }
    }

    func applyPublishedFileSecurity(
        to descriptor: ReportExportFileDescriptor,
        privateInvariant: Bool
    ) throws {
        guard Darwin.fchmod(descriptor.rawValue, S_IRUSR | S_IWUSR) == 0 else {
            throw ReportExportDescriptorIO.currentPOSIXError()
        }
        try applyDescriptorSecurity(to: descriptor)
        if privateInvariant {
            try ReportExportDescriptorIO.setNoUnlink(true, on: descriptor.rawValue)
        }
        let current = try ReportExportDescriptorIO.metadata(for: descriptor.rawValue)
        guard current.isRegularFile,
              current.owner == Darwin.geteuid(),
              current.permissions == (S_IRUSR | S_IWUSR),
              (!privateInvariant || current.hasNoUnlink) else {
            throw ReportExportError.unsafeTemporaryPath
        }
    }

    func writeDescriptorData(
        _ data: Data,
        relativePath: String,
        allocation: ReportExportDescriptorAllocation,
        beforeOperation: @escaping @Sendable () throws -> Void,
        beforeStageUnlink: @escaping @Sendable () throws -> Void = {},
        beforeStageUnlinkOperation: @escaping @Sendable () throws -> Void = {}
    ) throws -> URL {
        try ReportExportWorkspace.validate(relativePath: relativePath)
        let components = relativePath.split(separator: "/").map(String.init)
        let chain = try openDescriptorParent(
            components: Array(components.dropLast()),
            allocation: allocation,
            createIfMissing: true
        )
        let fileName = components.last!
        do {
            _ = try ReportExportDescriptorIO.metadata(
                at: fileName,
                relativeTo: chain.finalDescriptor.rawValue
            )
            throw ReportExportError.temporaryStorageFailed
        } catch let error as POSIXError where error.code == .ENOENT {
            // Expected absent destination.
        }
        try beforeOperation()
        try ReportExportDescriptorIO.validate(allocation: allocation, chain: chain)

        let partialName = ".\(fileName).\(UUID().uuidString.lowercased()).partial"
        let parentURL = components.dropLast().reduce(allocation.presentationURL) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        let staging = try ReportExportDescriptorIO.createAnonymousFile(
            in: chain.finalDescriptor.rawValue,
            parentURL: parentURL,
            visibleName: partialName,
            privateParent: true,
            beforeUnlink: beforeStageUnlink,
            beforeUnlinkOperation: beforeStageUnlinkOperation
        )
        try applyDescriptorSecurity(to: staging)
        try ReportExportDescriptorIO.write(data, to: staging.rawValue)
        try ReportExportNamespaceAuthority.shared.transaction {
            try ReportExportDescriptorIO.validate(allocation: allocation, chain: chain)
            let stageMetadata = try ReportExportDescriptorIO.metadata(for: staging.rawValue)
            guard stageMetadata.isRegularFile, stageMetadata.linkCount == 0 else {
                throw ReportExportError.unsafeTemporaryPath
            }
            do {
                try ReportExportDescriptorIO.withCreationAllowed(
                    in: chain.finalDescriptor.rawValue
                ) {
                    try ReportExportDescriptorIO.clone(
                        sourceDescriptor: staging.rawValue,
                        to: fileName,
                        in: chain.finalDescriptor.rawValue
                    )
                }
            } catch let error as POSIXError where error.code == .EEXIST {
                throw ReportExportError.temporaryStorageFailed
            }
            let publishedMetadata = try ReportExportDescriptorIO.metadata(
                at: fileName,
                relativeTo: chain.finalDescriptor.rawValue
            )
            do {
                let published = try ReportExportDescriptorIO.openRegularFile(
                    at: fileName,
                    relativeTo: chain.finalDescriptor.rawValue
                )
                guard try ReportExportDescriptorIO.metadata(for: published.rawValue).identity
                        == publishedMetadata.identity else {
                    throw ReportExportError.unsafeTemporaryPath
                }
                try applyPublishedFileSecurity(to: published, privateInvariant: true)
            } catch {
                try? ReportExportDescriptorIO.removeEntry(
                    fileName,
                    relativeTo: chain.finalDescriptor.rawValue,
                    expectedIdentity: publishedMetadata.identity,
                    flags: 0,
                    requirePrivateInvariant: false
                )
                throw error
            }
            try ReportExportDescriptorIO.validate(allocation: allocation, chain: chain)
        }
        return allocation.presentationURL.appendingPathComponent(relativePath)
    }

    func descriptorZIPDestination(
        relativePath: String,
        allocation: ReportExportDescriptorAllocation
    ) throws -> StoredZIPDestinationBinding {
        try ReportExportWorkspace.validate(relativePath: relativePath)
        let components = relativePath.split(separator: "/").map(String.init)
        let chain = try openDescriptorParent(
            components: Array(components.dropLast()),
            allocation: allocation,
            createIfMissing: true
        )
        let fileName = components.last!
        try ReportExportDescriptorIO.validate(allocation: allocation, chain: chain)
        return StoredZIPDestinationBinding(
            url: allocation.presentationURL.appendingPathComponent(relativePath),
            fileName: fileName,
            parentDescriptor: chain.finalDescriptor,
            requiresPrivateInvariant: true,
            validate: {
                try ReportExportDescriptorIO.validate(allocation: allocation, chain: chain)
            }
        )
    }

    /// Creates standalone payload staging only inside ReportsKit's private
    /// temporary allocation namespace. Once the file is descriptor-anonymous,
    /// the allocation is removed before any sensitive bytes are written.
    func createPrivateAnonymousStagingFile(
        visibleName: String,
        registry: ReportExportStageResidueRegistry = .shared,
        afterOpenBeforeMetadata: @escaping @Sendable (URL, String) throws -> Void = { _, _ in },
        beforeUnlink: @escaping @Sendable (URL, String) throws -> Void = { _, _ in },
        beforeUnlinkOperation: @escaping @Sendable (URL, String) throws -> Void = { _, _ in }
    ) throws -> ReportExportFileDescriptor {
        let allocation = try ReportExportTemporaryStore().allocate()
        let binding: StoredZIPDestinationBinding
        do {
            binding = try allocation.workspace.zipDestination(
                relativePath: "stage-anchor"
            )
        } catch {
            _ = allocation.cleanup()
            throw error
        }
        let parentURL = allocation.directoryURL
        let descriptor = try ReportExportDescriptorIO.createAnonymousFile(
            in: binding.parentDescriptor.rawValue,
            parentURL: parentURL,
            visibleName: visibleName,
            privateParent: true,
            registry: registry,
            afterOpenBeforeMetadata: {
                try afterOpenBeforeMetadata(parentURL, visibleName)
            },
            beforeUnlink: {
                try beforeUnlink(parentURL, visibleName)
            },
            beforeUnlinkOperation: {
                try beforeUnlinkOperation(parentURL, visibleName)
            },
            afterResidueResolution: {
                _ = allocation.cleanup()
            }
        )
        guard allocation.cleanup() else {
            throw ReportExportError.temporaryStorageFailed
        }
        return descriptor
    }

    func standaloneZIPDestination(at url: URL) throws -> StoredZIPDestinationBinding {
        guard url.isFileURL else { throw StoredZIPWriterError.destinationExists }
        let parentURL = url.deletingLastPathComponent()
        let entry = try ReportExportDescriptorIO.makeEntry(at: parentURL, createIfMissing: false)
        let fileName = url.lastPathComponent
        try ReportExportWorkspace.validate(relativePath: fileName)
        return StoredZIPDestinationBinding(
            url: url,
            fileName: fileName,
            parentDescriptor: entry.descriptor,
            validate: { try entry.validate() }
        )
    }

    func readDescriptorMarker(
        allocation: ReportExportDescriptorAllocation,
        afterRead: @escaping @Sendable () throws -> Void
    ) throws -> Data {
        try ReportExportDescriptorIO.validate(allocation: allocation)
        let (data, identity) = try ReportExportDescriptorIO.readFile(
            at: ".allocation-id",
            relativeTo: allocation.descriptor.rawValue
        )
        try afterRead()
        try ReportExportDescriptorIO.validate(allocation: allocation)
        let current = try ReportExportDescriptorIO.metadata(
            at: ".allocation-id",
            relativeTo: allocation.descriptor.rawValue
        )
        guard current.identity == identity, current.isRegularFile else {
            throw ReportExportError.cleanupIdentityMismatch
        }
        return data
    }

    func cleanupDescriptorAllocation(
        _ allocation: ReportExportDescriptorAllocation,
        afterMarkerRead: @escaping @Sendable () throws -> Void,
        beforeRecursiveCleanup: @escaping @Sendable () throws -> Void,
        beforeEntryBoundary: @escaping @Sendable (ReportExportDescriptorBoundary) throws -> Void = { _ in }
    ) throws -> ReportExportDescriptorCleanupResult {
        guard let currentName = allocation.currentEntryName else {
            try allocation.root.releaseNamespaceLease()
            return .removed
        }
        do {
            try allocation.root.validate()
            let current = try ReportExportDescriptorIO.metadata(
                at: currentName,
                relativeTo: allocation.root.descriptor.rawValue
            )
            guard current.identity == allocation.identity, current.isDirectory else {
                return .stale
            }
        } catch let error as POSIXError where error.code == .ENOENT {
            allocation.markRemoved()
            try allocation.root.releaseNamespaceLease()
            return .removed
        }

        if allocation.wasMarkerPublished, !allocation.isQuarantined {
            let marker = try readDescriptorMarker(
                allocation: allocation,
                afterRead: afterMarkerRead
            )
            guard marker == allocation.marker else {
                return .stale
            }
        }
        try beforeRecursiveCleanup()
        try ReportExportDescriptorIO.validate(allocation: allocation)
        let quarantineName: String
        if allocation.isQuarantined {
            quarantineName = currentName
        } else {
            quarantineName = try ReportExportNamespaceAuthority.shared.transaction {
                let quarantine = ".cleanup-\(UUID().uuidString.lowercased())"
                let current = try ReportExportDescriptorIO.metadata(
                    at: currentName,
                    relativeTo: allocation.root.descriptor.rawValue
                )
                guard current.identity == allocation.identity,
                      current.hasNoUnlink else {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                try ReportExportDescriptorIO.setNoUnlink(
                    false,
                    on: allocation.descriptor.rawValue
                )
                let renamed = try ReportExportDescriptorIO.withRemovalAllowed(
                    in: allocation.root.descriptor.rawValue
                ) {
                    currentName.withCString { source in
                        quarantine.withCString { destination in
                            Darwin.renameatx_np(
                                allocation.root.descriptor.rawValue,
                                source,
                                allocation.root.descriptor.rawValue,
                                destination,
                                UInt32(RENAME_EXCL)
                            )
                        }
                    }
                }
                if renamed != 0 {
                    try? ReportExportDescriptorIO.setNoUnlink(
                        true,
                        on: allocation.descriptor.rawValue
                    )
                    throw ReportExportDescriptorIO.currentPOSIXError()
                }
                try ReportExportDescriptorIO.setNoUnlink(
                    true,
                    on: allocation.descriptor.rawValue
                )
                let moved = try ReportExportDescriptorIO.metadata(
                    at: quarantine,
                    relativeTo: allocation.root.descriptor.rawValue
                )
                guard moved.identity == allocation.identity else {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                let reopened = try ReportExportDescriptorIO.openDirectory(
                    at: quarantine,
                    relativeTo: allocation.root.descriptor.rawValue
                )
                guard try ReportExportDescriptorIO.metadata(for: reopened.rawValue).identity
                        == allocation.identity else {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                return quarantine
            }
            allocation.markQuarantined(as: quarantineName)
        }
        try ReportExportDescriptorIO.removeContents(
            of: allocation.descriptor.rawValue,
            beforeBoundary: beforeEntryBoundary
        )
        try ReportExportDescriptorIO.removeEntry(
            quarantineName,
            relativeTo: allocation.root.descriptor.rawValue,
            expectedIdentity: allocation.identity,
            flags: AT_REMOVEDIR
        )
        allocation.markRemoved()
        try allocation.root.releaseNamespaceLease()
        return .removed
    }

    func recoverDescriptorAllocation(
        _ record: ReportExportCleanupRecoveryRecord
    ) throws -> ReportExportDescriptorCleanupResult {
        let root: ReportExportDescriptorRoot
        do {
            root = try bindDescriptorRoot(
                at: record.rootDirectory,
                createIfMissing: false
            )
        } catch let error as POSIXError where error.code == .ENOENT {
            return .removed
        }
        guard root.identity == record.rootIdentity else {
            try root.releaseNamespaceLease()
            return .stale
        }
        let owned: ReportExportFileDescriptor
        do {
            owned = try ReportExportDescriptorIO.openDirectory(
                at: record.ownedEntryName,
                relativeTo: root.descriptor.rawValue
            )
        } catch let error as POSIXError where error.code == .ENOENT {
            try root.releaseNamespaceLease()
            return .removed
        }
        let metadata = try ReportExportDescriptorIO.metadata(for: owned.rawValue)
        guard metadata.identity == record.ownedIdentity else {
            try root.releaseNamespaceLease()
            return .stale
        }
        let allocation = ReportExportDescriptorAllocation(
            root: root,
            presentationURL: record.rootDirectory.appendingPathComponent(
                record.ownedEntryName,
                isDirectory: true
            ),
            entryName: record.ownedEntryName,
            descriptor: owned,
            identity: record.ownedIdentity,
            marker: record.marker
        )
        if record.requiresMarker { allocation.markMarkerPublished() }
        if record.ownedEntryName.hasPrefix(".cleanup-") {
            allocation.markQuarantined(as: record.ownedEntryName)
        }
        return try cleanupDescriptorAllocation(
            allocation,
            afterMarkerRead: {},
            beforeRecursiveCleanup: {}
        )
    }

    private func openDescriptorParent(
        components: [String],
        allocation: ReportExportDescriptorAllocation,
        createIfMissing: Bool
    ) throws -> ReportExportDescriptorDirectoryChain {
        try ReportExportNamespaceAuthority.shared.transaction {
            try ReportExportDescriptorIO.validate(allocation: allocation)
            var parent = allocation.descriptor
            var entries: [ReportExportDescriptorEntry] = []
            for component in components {
                var wasCreated = false
                do {
                    let metadata = try ReportExportDescriptorIO.metadata(
                        at: component,
                        relativeTo: parent.rawValue
                    )
                    guard metadata.isDirectory, !metadata.isSymbolicLink else {
                        throw ReportExportError.unsafeTemporaryPath
                    }
                } catch let error as POSIXError where error.code == .ENOENT {
                    guard createIfMissing else { throw error }
                    let result = try ReportExportDescriptorIO.withRemovalAllowed(
                        in: parent.rawValue
                    ) {
                        component.withCString {
                            Darwin.mkdirat(parent.rawValue, $0, S_IRWXU)
                        }
                    }
                    guard result == 0 else {
                        throw ReportExportDescriptorIO.currentPOSIXError()
                    }
                    wasCreated = true
                }
                do {
                    let child = try ReportExportDescriptorIO.openDirectory(
                        at: component,
                        relativeTo: parent.rawValue
                    )
                    try ReportExportDescriptorIO.establishPrivateDirectory(child.rawValue)
                    try applyDescriptorSecurity(to: child)
                    let metadata = try ReportExportDescriptorIO.metadata(for: child.rawValue)
                    let entry = ReportExportDescriptorEntry(
                        parent: parent,
                        name: component,
                        descriptor: child,
                        identity: metadata.identity
                    )
                    entries.append(entry)
                    parent = child
                } catch {
                    if wasCreated {
                        _ = component.withCString {
                            Darwin.unlinkat(parent.rawValue, $0, AT_REMOVEDIR)
                        }
                    }
                    throw error
                }
            }
            return ReportExportDescriptorDirectoryChain(entries: entries, finalDescriptor: parent)
        }
    }
}
