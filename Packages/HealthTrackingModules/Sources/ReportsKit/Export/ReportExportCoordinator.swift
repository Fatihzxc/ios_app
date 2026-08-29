import Darwin
import Foundation

public enum ReportExportFormat: String, CaseIterable, Equatable, Sendable {
    case csv
    case json
    case bothZip
}

public struct ReportExportRequest: Equatable, Sendable {
    public let interval: ReportDateInterval
    public let modules: Set<ExportModuleV1>
    public let format: ReportExportFormat
    public let includesPhotos: Bool

    public init(
        interval: ReportDateInterval,
        modules: Set<ExportModuleV1>,
        format: ReportExportFormat,
        includesPhotos: Bool
    ) {
        self.interval = interval
        self.modules = modules
        self.format = format
        self.includesPhotos = includesPhotos
    }
}

public enum ReportExportError: Error, Equatable, Sendable {
    case invalidInterval
    case photosRequireZIP
    case snapshotMismatch
    case temporaryStorageFailed
    case unsafeTemporaryPath
    case cleanupIdentityMismatch
}

public enum ReportExportPhotoPayloadV1: Sendable {
    case available(Data)
    case missing
    case corrupt
}

public protocol ReportExportPhotoByteProviding: Sendable {
    func jpegData(for photoID: UUID) async throws -> ReportExportPhotoPayloadV1
}

public struct MissingReportExportPhotoProvider: ReportExportPhotoByteProviding {
    public init() {}
    public func jpegData(for photoID: UUID) async throws -> ReportExportPhotoPayloadV1 {
        .missing
    }
}

@MainActor
public protocol ReportExportGenerating: AnyObject, Sendable {
    func generate(_ request: ReportExportRequest) async throws -> ExportArtifactToken
}

public protocol ReportExportTemporaryStoring: AnyObject, Sendable {
    func allocate() throws -> ReportExportAllocation
}

struct ReportExportFileIdentity: Equatable, Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}

protocol ReportExportTemporaryFileSystem: AnyObject, Sendable {
    func createRootDirectory(at url: URL) throws
    func createExclusiveDirectory(at url: URL) throws
    func createDirectory(at url: URL) throws
    func applyCompleteFileProtection(at url: URL) throws
    func excludeFromBackup(at url: URL) throws
    func canonicalURL(for url: URL) throws -> URL
    func isSymbolicLink(at url: URL) throws -> Bool
    func fileIdentity(at url: URL) throws -> ReportExportFileIdentity?
    func exists(at url: URL) -> Bool
    func writeAtomically(_ data: Data, to url: URL) throws
    func read(_ url: URL) throws -> Data
    func removeItemIfExists(at url: URL) throws
}

protocol ReportExportCleanupScheduling: AnyObject, Sendable {
    func schedule(
        afterNanoseconds: UInt64,
        operation: @escaping @Sendable () -> Void
    )
}

final class SystemReportExportCleanupScheduler:
    ReportExportCleanupScheduling, @unchecked Sendable {
    func schedule(
        afterNanoseconds: UInt64,
        operation: @escaping @Sendable () -> Void
    ) {
        Task.detached {
            do { try await Task.sleep(nanoseconds: afterNanoseconds) } catch { return }
            guard !Task.isCancelled else { return }
            operation()
        }
    }
}

final class ReportExportLifetimeCleanupRegistry: @unchecked Sendable {
    static let shared = ReportExportLifetimeCleanupRegistry()

    private struct Entry {
        let cleanupID: UUID
        let directory: URL
        let operation: @Sendable () throws -> Void
        let terminalRecovery: (@Sendable () -> ReportExportCleanupRecoveryRecord?)?
        var attempts: Int
        var scheduledToken: UUID?
        var isRunning: Bool
    }

    private let lock = NSLock()
    private let scheduler: any ReportExportCleanupScheduling
    private var entries: [UUID: Entry] = [:]
    private var recoveries: [UUID: ReportExportCleanupRecoveryRecord] = [:]
    private var recoveryOrder: [UUID] = []
    private var reservations: Set<UUID> = []
    private let maximumRetryAttempts = 8
    private let maximumRecoveryRecords = 64
    private let retryDelays: [UInt64] = [
        20_000_000, 50_000_000, 100_000_000, 250_000_000,
        500_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000,
    ]

    convenience init() { self.init(scheduler: SystemReportExportCleanupScheduler()) }

    init(scheduler: any ReportExportCleanupScheduling) {
        self.scheduler = scheduler
    }

    func reserve(cleanupID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if entries[cleanupID] != nil || recoveries[cleanupID] != nil
            || reservations.contains(cleanupID) { return true }
        guard entries.count + recoveries.count + reservations.count
                < maximumRecoveryRecords else { return false }
        reservations.insert(cleanupID)
        return true
    }

    func releaseReservation(cleanupID: UUID) {
        lock.lock()
        reservations.remove(cleanupID)
        lock.unlock()
    }

    @discardableResult
    func register(
        cleanupID: UUID,
        directory: URL,
        operation: @escaping @Sendable () throws -> Void,
        terminalRecovery: (@Sendable () -> ReportExportCleanupRecoveryRecord?)? = nil
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard entries[cleanupID] == nil else { return true }
        if reservations.remove(cleanupID) == nil {
            guard entries.count + recoveries.count + reservations.count
                    < maximumRecoveryRecords else { return false }
        }
        entries[cleanupID] = Entry(
            cleanupID: cleanupID,
            directory: directory,
            operation: operation,
            terminalRecovery: terminalRecovery,
            attempts: 0,
            scheduledToken: nil,
            isRunning: false
        )
        return true
    }

    @discardableResult
    func retain(
        cleanupID: UUID,
        directory: URL,
        operation: @escaping @Sendable () throws -> Void,
        terminalRecovery: (@Sendable () -> ReportExportCleanupRecoveryRecord?)? = nil
    ) -> Bool {
        let retained = register(
            cleanupID: cleanupID,
            directory: directory,
            operation: operation,
            terminalRecovery: terminalRecovery
        )
        if retained { scheduleIfNeeded(cleanupID) }
        return retained
    }

    func didClean(cleanupID: UUID) {
        lock.lock()
        entries.removeValue(forKey: cleanupID)
        reservations.remove(cleanupID)
        lock.unlock()
    }

    func retryPendingNow() {
        lock.lock()
        let identifiers = Array(entries.keys)
        lock.unlock()
        for cleanupID in identifiers { retry(cleanupID: cleanupID, scheduleToken: nil) }
    }

    func recoveryRecords(for rootDirectory: URL) -> [ReportExportCleanupRecoveryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return recoveryOrder.compactMap { recoveries[$0] }.filter {
            $0.rootDirectory.standardizedFileURL == rootDirectory.standardizedFileURL
        }
    }

    func didRecover(cleanupID: UUID) {
        lock.lock()
        recoveries.removeValue(forKey: cleanupID)
        recoveryOrder.removeAll { $0 == cleanupID }
        reservations.remove(cleanupID)
        lock.unlock()
    }

    private func scheduleIfNeeded(_ cleanupID: UUID) {
        lock.lock()
        guard var entry = entries[cleanupID], entry.scheduledToken == nil,
              !entry.isRunning, entry.attempts < maximumRetryAttempts else {
            lock.unlock()
            return
        }
        let index = min(entry.attempts, retryDelays.count - 1)
        let scheduleToken = UUID()
        entry.scheduledToken = scheduleToken
        entries[cleanupID] = entry
        lock.unlock()
        scheduler.schedule(afterNanoseconds: retryDelays[index]) { [weak self] in
            self?.retry(cleanupID: cleanupID, scheduleToken: scheduleToken)
        }
    }

    private func retry(cleanupID: UUID, scheduleToken: UUID?) {
        lock.lock()
        guard var entry = entries[cleanupID], !entry.isRunning else {
            lock.unlock()
            return
        }
        if let scheduleToken, entry.scheduledToken != scheduleToken {
            lock.unlock()
            return
        }
        entry.scheduledToken = nil
        entry.isRunning = true
        entries[cleanupID] = entry
        lock.unlock()

        do {
            try entry.operation()
            lock.lock()
            entries.removeValue(forKey: cleanupID)
            lock.unlock()
        } catch {
            var terminalRecovery: (@Sendable () -> ReportExportCleanupRecoveryRecord?)?
            var shouldSchedule = false
            lock.lock()
            if var current = entries[cleanupID] {
                current.isRunning = false
                current.attempts += 1
                if current.attempts >= maximumRetryAttempts {
                    terminalRecovery = current.terminalRecovery
                    entries.removeValue(forKey: cleanupID)
                    reservations.insert(cleanupID)
                } else {
                    entries[cleanupID] = current
                    shouldSchedule = true
                }
            }
            lock.unlock()
            if let recovery = terminalRecovery?() {
                rememberRecovery(recovery)
            } else if terminalRecovery != nil {
                releaseReservation(cleanupID: cleanupID)
            } else {
                releaseReservation(cleanupID: cleanupID)
            }
            if shouldSchedule { scheduleIfNeeded(cleanupID) }
        }
    }

    private func rememberRecovery(_ recovery: ReportExportCleanupRecoveryRecord) {
        lock.lock()
        reservations.remove(recovery.cleanupID)
        if recoveries[recovery.cleanupID] == nil {
            recoveryOrder.append(recovery.cleanupID)
        }
        recoveries[recovery.cleanupID] = recovery
        lock.unlock()
    }
}

private final class ReportExportCleanupState: @unchecked Sendable {
    private let lock = NSLock()
    private var didClean = false
    private var action: (@Sendable () throws -> Void)?

    init(action: @escaping @Sendable () throws -> Void) { self.action = action }

    var isClean: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didClean
    }

    func perform() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didClean else { return true }
        do {
            guard let action else { return false }
            try action()
            didClean = true
            self.action = nil
            return true
        } catch {
            return false
        }
    }
}

private actor ReportExportCleanupWorker {
    static let shared = ReportExportCleanupWorker()
    func perform(_ state: ReportExportCleanupState) -> Bool { state.perform() }
}

private actor ReportExportLifecycleWorker {
    private let store: any ReportExportTemporaryStoring

    init(store: any ReportExportTemporaryStoring) { self.store = store }
    func allocate() throws -> ReportExportAllocation { try store.allocate() }
    func cleanup(_ allocation: ReportExportAllocation) -> Bool { allocation.cleanup() }
}

public final class ExportArtifactToken: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let shareURLs: [URL]
    private let countLock = NSLock()
    private var storedCleanupCallCount = 0
    private let cleanupState: ReportExportCleanupState

    public var cleanupCallCount: Int {
        countLock.lock()
        defer { countLock.unlock() }
        return storedCleanupCallCount
    }

    init(
        id: UUID = UUID(),
        shareURLs: [URL],
        cleanup: @escaping @Sendable () throws -> Void
    ) {
        self.id = id
        self.shareURLs = shareURLs
        cleanupState = ReportExportCleanupState(action: cleanup)
    }

    @discardableResult
    /// Performs synchronous cleanup and may block on filesystem work. UI code
    /// should use the module's asynchronous lifecycle path (`beginCleanup`).
    public func cleanup() -> Bool {
        guard !cleanupState.isClean else { return true }
        countLock.lock()
        storedCleanupCallCount += 1
        countLock.unlock()
        return cleanupState.perform()
    }

    func beginCleanup() -> Task<Bool, Never> {
        guard !cleanupState.isClean else { return Task { true } }
        countLock.lock()
        storedCleanupCallCount += 1
        countLock.unlock()
        let state = cleanupState
        return Task {
            await ReportExportCleanupWorker.shared.perform(state)
        }
    }
}

struct ReportExportWorkspace: Sendable {
    let directoryURL: URL
    private let writeAction: @Sendable (Data, String) throws -> URL
    private let validateAction: @Sendable () throws -> Void
    private let destinationBindingAction: @Sendable (String) throws
        -> StoredZIPDestinationBinding

    init(
        directoryURL: URL,
        write: @escaping @Sendable (Data, String) throws -> URL,
        validate: @escaping @Sendable () throws -> Void = {},
        destinationBinding: (@Sendable (String) throws -> StoredZIPDestinationBinding)? = nil
    ) {
        self.directoryURL = directoryURL
        writeAction = write
        validateAction = validate
        if let destinationBinding {
            destinationBindingAction = destinationBinding
        } else {
            destinationBindingAction = { relativePath in
                try Self.validate(relativePath: relativePath)
                return try FileManagerReportExportTemporaryFileSystem()
                    .standaloneZIPDestination(
                        at: directoryURL.appendingPathComponent(relativePath)
                    )
            }
        }
    }

    func write(_ data: Data, relativePath: String) throws -> URL {
        try writeAction(data, relativePath)
    }

    func destinationURL(relativePath: String) throws -> URL {
        try Self.validate(relativePath: relativePath)
        try validateAction()
        let destination = directoryURL.appendingPathComponent(relativePath)
        guard destination.standardizedFileURL.path.hasPrefix(
            directoryURL.standardizedFileURL.path + "/"
        ) else { throw ReportExportError.unsafeTemporaryPath }
        return destination
    }

    func validateCurrentOwnership() throws { try validateAction() }

    func zipDestination(relativePath: String) throws -> StoredZIPDestinationBinding {
        try Self.validate(relativePath: relativePath)
        try validateAction()
        return try destinationBindingAction(relativePath)
    }

    static func validate(relativePath: String) throws {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"), !relativePath.contains(":"),
              !relativePath.contains("\0"),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw ReportExportError.unsafeTemporaryPath
        }
    }
}

public final class ReportExportAllocation: @unchecked Sendable {
    public let directoryURL: URL
    let workspace: ReportExportWorkspace
    private let cleanupState: ReportExportCleanupState

    init(
        directoryURL: URL,
        write: @escaping @Sendable (Data, String) throws -> URL,
        validate: @escaping @Sendable () throws -> Void = {},
        destinationBinding: (@Sendable (String) throws -> StoredZIPDestinationBinding)? = nil,
        cleanup: @escaping @Sendable () throws -> Void
    ) {
        self.directoryURL = directoryURL
        workspace = ReportExportWorkspace(
            directoryURL: directoryURL,
            write: write,
            validate: validate,
            destinationBinding: destinationBinding
        )
        cleanupState = ReportExportCleanupState(action: cleanup)
    }

    public func write(_ data: Data, relativePath: String) throws -> URL {
        guard !cleanupState.isClean else { throw ReportExportError.temporaryStorageFailed }
        return try workspace.write(data, relativePath: relativePath)
    }

    public func makeArtifactToken(shareURLs: [URL]) -> ExportArtifactToken {
        ExportArtifactToken(shareURLs: shareURLs) { [cleanupState] in
            guard cleanupState.perform() else { throw ReportExportError.temporaryStorageFailed }
        }
    }

    @discardableResult
    /// Performs synchronous cleanup and may block; UI flows hand artifact
    /// cleanup to the non-MainActor cleanup worker instead.
    public func cleanup() -> Bool { cleanupState.perform() }

}

final class FileManagerReportExportTemporaryFileSystem:
    ReportExportTemporaryFileSystem, @unchecked Sendable {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func createRootDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createExclusiveDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func applyCompleteFileProtection(at url: URL) throws {
        #if !targetEnvironment(simulator)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #endif
    }

    func excludeFromBackup(at url: URL) throws {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    func canonicalURL(for url: URL) throws -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    func isSymbolicLink(at url: URL) throws -> Bool {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else {
            if errno == ENOENT { return false }
            throw Self.currentPOSIXError()
        }
        return status.st_mode & S_IFMT == S_IFLNK
    }

    func fileIdentity(at url: URL) throws -> ReportExportFileIdentity? {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else {
            if errno == ENOENT { return nil }
            throw Self.currentPOSIXError()
        }
        return ReportExportFileIdentity(
            device: UInt64(truncatingIfNeeded: status.st_dev),
            inode: UInt64(truncatingIfNeeded: status.st_ino)
        )
    }

    func exists(at url: URL) -> Bool {
        var status = stat()
        return Darwin.lstat(url.path, &status) == 0
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        let destination = try standaloneZIPDestination(at: url)
        try ReportExportNamespaceAuthority.shared.transaction {
            let lease = try destination.acquireNamespaceLease()
            do {
                try lease.validate()
                guard try !destination.destinationExists() else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try lease.release()
            } catch let operationError {
                do { try lease.release() } catch { throw error }
                throw operationError
            }
        }
        let staging = try ReportExportDescriptorIO.createAnonymousFile(
            in: destination.parentDescriptor.rawValue,
            parentURL: url.deletingLastPathComponent(),
            visibleName: ".\(url.lastPathComponent).\(UUID().uuidString.lowercased()).partial",
            privateParent: false
        )
        try applyDescriptorSecurity(to: staging)
        try ReportExportDescriptorIO.write(data, to: staging.rawValue)
        try ReportExportNamespaceAuthority.shared.transaction {
            let lease = try destination.acquireNamespaceLease()
            do {
                try lease.validate()
                do {
                    try ReportExportDescriptorIO.withRemovalAllowed(
                        in: destination.parentDescriptor.rawValue
                    ) {
                        try ReportExportDescriptorIO.clone(
                            sourceDescriptor: staging.rawValue,
                            to: destination.fileName,
                            in: destination.parentDescriptor.rawValue
                        )
                    }
                } catch let error as POSIXError where error.code == .EEXIST {
                    throw CocoaError(.fileWriteFileExists)
                }
                let metadata = try ReportExportDescriptorIO.metadata(
                    at: destination.fileName,
                    relativeTo: destination.parentDescriptor.rawValue
                )
                do {
                    let published = try ReportExportDescriptorIO.openRegularFile(
                        at: destination.fileName,
                        relativeTo: destination.parentDescriptor.rawValue
                    )
                    guard try ReportExportDescriptorIO.metadata(for: published.rawValue).identity
                            == metadata.identity else {
                        throw ReportExportError.unsafeTemporaryPath
                    }
                    try applyPublishedFileSecurity(to: published, privateInvariant: false)
                } catch {
                    try? ReportExportDescriptorIO.removeEntry(
                        destination.fileName,
                        relativeTo: destination.parentDescriptor.rawValue,
                        expectedIdentity: metadata.identity,
                        flags: 0,
                        requirePrivateInvariant: false
                    )
                    throw error
                }
                try lease.release()
            } catch let operationError {
                do { try lease.release() } catch { throw error }
                throw operationError
            }
        }
    }

    func read(_ url: URL) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Self.currentPOSIXError() }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG else {
            let error = Self.currentPOSIXError()
            _ = Darwin.close(descriptor)
            throw error
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            let data = try handle.readToEnd() ?? Data()
            try handle.close()
            return data
        } catch {
            try? handle.close()
            throw error
        }
    }

    func removeItemIfExists(at url: URL) throws {
        guard exists(at: url) else { return }
        try fileManager.removeItem(at: url)
    }

    private static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private struct ReportExportOwnedPathBoundary: Sendable {
    enum State: Equatable { case missing, exact, replaced }

    let rootDirectory: URL
    let canonicalRoot: URL
    let rootIdentity: ReportExportFileIdentity
    let ownedDirectory: URL
    let canonicalOwned: URL
    let ownedIdentity: ReportExportFileIdentity

    func currentState(
        using fileSystem: any ReportExportTemporaryFileSystem
    ) throws -> State {
        guard let currentRootIdentity = try fileSystem.fileIdentity(at: rootDirectory) else {
            return .missing
        }
        guard try !fileSystem.isSymbolicLink(at: rootDirectory),
              currentRootIdentity == rootIdentity,
              try fileSystem.canonicalURL(for: rootDirectory) == canonicalRoot else {
            throw ReportExportError.unsafeTemporaryPath
        }
        guard let currentOwnedIdentity = try fileSystem.fileIdentity(at: ownedDirectory) else {
            return .missing
        }
        guard try !fileSystem.isSymbolicLink(at: ownedDirectory) else {
            throw ReportExportError.unsafeTemporaryPath
        }
        guard currentOwnedIdentity == ownedIdentity else { return .replaced }
        guard try fileSystem.canonicalURL(for: ownedDirectory) == canonicalOwned else {
            throw ReportExportError.unsafeTemporaryPath
        }
        return .exact
    }

    func requireCurrentOwnership(
        using fileSystem: any ReportExportTemporaryFileSystem
    ) throws {
        guard try currentState(using: fileSystem) == .exact else {
            throw ReportExportError.cleanupIdentityMismatch
        }
    }

    func prepareParent(
        for relativePath: String,
        using fileSystem: any ReportExportTemporaryFileSystem
    ) throws -> URL {
        try ReportExportWorkspace.validate(relativePath: relativePath)
        try requireCurrentOwnership(using: fileSystem)
        let components = relativePath.split(separator: "/").map(String.init)
        var parent = ownedDirectory
        for component in components.dropLast() {
            parent.appendPathComponent(component, isDirectory: true)
            if fileSystem.exists(at: parent) {
                try validateExistingParent(parent, using: fileSystem)
            } else {
                try fileSystem.createDirectory(at: parent)
                try validateExistingParent(parent, using: fileSystem)
            }
            try requireCurrentOwnership(using: fileSystem)
        }
        return parent
    }

    private func validateExistingParent(
        _ parent: URL,
        using fileSystem: any ReportExportTemporaryFileSystem
    ) throws {
        guard try !fileSystem.isSymbolicLink(at: parent),
              try fileSystem.fileIdentity(at: parent) != nil else {
            throw ReportExportError.unsafeTemporaryPath
        }
        let canonicalParent = try fileSystem.canonicalURL(for: parent)
        guard canonicalParent.path == canonicalOwned.path
                || canonicalParent.path.hasPrefix(canonicalOwned.path + "/") else {
            throw ReportExportError.unsafeTemporaryPath
        }
    }
}

public final class ReportExportTemporaryStore:
    ReportExportTemporaryStoring, @unchecked Sendable {
    private let rootDirectory: URL
    private let fileSystem: any ReportExportTemporaryFileSystem
    private let makeDirectoryID: @Sendable () -> UUID
    private let cleanupRegistry: ReportExportLifetimeCleanupRegistry
    private let maximumDirectoryAttempts = 8

    public convenience init() {
        self.init(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("FOHealthExports", isDirectory: true),
            fileSystem: FileManagerReportExportTemporaryFileSystem(),
            makeDirectoryID: { UUID() },
            cleanupRegistry: .shared
        )
    }

    init(
        rootDirectory: URL,
        fileSystem: any ReportExportTemporaryFileSystem,
        makeDirectoryID: @escaping @Sendable () -> UUID,
        cleanupRegistry: ReportExportLifetimeCleanupRegistry = .shared
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileSystem = fileSystem
        self.makeDirectoryID = makeDirectoryID
        self.cleanupRegistry = cleanupRegistry
    }

    public func allocate() throws -> ReportExportAllocation {
        cleanupRegistry.retryPendingNow()
        retryTerminalRecoveries()
        if let descriptorFileSystem = fileSystem
            as? any ReportExportDescriptorTemporaryFileSystem {
            return try allocateDescriptor(using: descriptorFileSystem)
        }
        return try allocateLegacy()
    }

    private func allocateDescriptor(
        using fileSystem: any ReportExportDescriptorTemporaryFileSystem
    ) throws -> ReportExportAllocation {
        let backend = fileSystem.descriptorBackend
        let root = try backend.bindOrCreateDescriptorRoot(at: rootDirectory)
        let cleanupID = UUID()
        guard cleanupRegistry.reserve(cleanupID: cleanupID) else {
            try? root.releaseNamespaceLease()
            throw ReportExportError.temporaryStorageFailed
        }
        var ownsReservation = true
        defer {
            if ownsReservation {
                cleanupRegistry.releaseReservation(cleanupID: cleanupID)
            }
        }
        let descriptorAllocation: ReportExportDescriptorAllocation
        var createdAllocation: ReportExportDescriptorAllocation?
        for _ in 0..<maximumDirectoryAttempts {
            let directoryID = makeDirectoryID()
            let marker = Data(UUID().uuidString.lowercased().utf8)
            do {
                createdAllocation = try backend.createDescriptorAllocation(
                    in: root,
                    directoryName: directoryID.uuidString.lowercased(),
                    marker: marker,
                    afterMkdir: {
                        try fileSystem.reachDescriptorBoundary(.allocationDirectoryCreated)
                    },
                    afterSecurity: {
                        try fileSystem.reachDescriptorBoundary(.allocationDirectorySecured)
                    }
                )
                break
            } catch let residue as ReportExportDescriptorCreationResidue {
                try retainDescriptorCreationResidue(
                    residue,
                    cleanupID: cleanupID,
                    backend: backend
                )
                ownsReservation = false
                throw residue.originalError
            } catch where Self.isCollision(error) {
                continue
            }
        }
        guard let createdAllocation else {
            try? root.releaseNamespaceLease()
            throw ReportExportError.temporaryStorageFailed
        }
        descriptorAllocation = createdAllocation

        let registry = cleanupRegistry
        let cleanupOperation: @Sendable () throws -> Void = {
            let result = try backend.cleanupDescriptorAllocation(
                descriptorAllocation,
                afterMarkerRead: {
                    try fileSystem.reachDescriptorBoundary(.markerRead)
                },
                beforeRecursiveCleanup: {
                    try fileSystem.reachDescriptorBoundary(.recursiveCleanup)
                },
                beforeEntryBoundary: { boundary in
                    try fileSystem.reachDescriptorBoundary(boundary)
                }
            )
            guard case .removed = result else {
                throw ReportExportError.cleanupIdentityMismatch
            }
        }
        let terminalRecovery: @Sendable () -> ReportExportCleanupRecoveryRecord? = {
            descriptorAllocation.recoveryRecord(cleanupID: cleanupID)
        }
        guard registry.register(
            cleanupID: cleanupID,
            directory: descriptorAllocation.presentationURL,
            operation: cleanupOperation,
            terminalRecovery: terminalRecovery
        ) else {
            throw ReportExportError.temporaryStorageFailed
        }
        ownsReservation = false

        do {
            try backend.applyDescriptorSecurity(to: descriptorAllocation.descriptor)
            _ = try backend.writeDescriptorData(
                descriptorAllocation.marker,
                relativePath: ".allocation-id",
                allocation: descriptorAllocation,
                beforeOperation: {
                    try fileSystem.reachDescriptorBoundary(.markerPublication)
                }
            )
            descriptorAllocation.markMarkerPublished()
            try ReportExportDescriptorIO.validate(allocation: descriptorAllocation)

            let cleanupWithRetention: @Sendable () throws -> Void = {
                do {
                    try cleanupOperation()
                    registry.didClean(cleanupID: cleanupID)
                } catch {
                    registry.retain(
                        cleanupID: cleanupID,
                        directory: descriptorAllocation.presentationURL,
                        operation: cleanupOperation,
                        terminalRecovery: terminalRecovery
                    )
                    throw error
                }
            }
            return ReportExportAllocation(
                directoryURL: descriptorAllocation.presentationURL,
                write: { data, relativePath in
                    try backend.writeDescriptorData(
                        data,
                        relativePath: relativePath,
                        allocation: descriptorAllocation,
                        beforeOperation: {
                            try fileSystem.reachDescriptorBoundary(.payloadWrite)
                        },
                        beforeStageUnlink: {
                            try fileSystem.reachDescriptorBoundary(.payloadStageCreated)
                        },
                        beforeStageUnlinkOperation: {
                            try fileSystem.reachDescriptorBoundary(.payloadStageBeforeUnlink)
                        }
                    )
                },
                validate: {
                    try ReportExportDescriptorIO.validate(allocation: descriptorAllocation)
                },
                destinationBinding: { relativePath in
                    try backend.descriptorZIPDestination(
                        relativePath: relativePath,
                        allocation: descriptorAllocation
                    )
                },
                cleanup: cleanupWithRetention
            )
        } catch {
            do {
                try cleanupOperation()
                registry.didClean(cleanupID: cleanupID)
            } catch {
                registry.retain(
                    cleanupID: cleanupID,
                    directory: descriptorAllocation.presentationURL,
                    operation: cleanupOperation,
                    terminalRecovery: terminalRecovery
                )
            }
            throw error
        }
    }

    private func retainDescriptorCreationResidue(
        _ residue: ReportExportDescriptorCreationResidue,
        cleanupID: UUID,
        backend: FileManagerReportExportTemporaryFileSystem
    ) throws {
        let identityState = ReportExportLegacyCleanupIdentityState()
        let registry = cleanupRegistry
        let directory = residue.root.presentationURL.appendingPathComponent(
            residue.entryName,
            isDirectory: true
        )
        let cleanupOperation: @Sendable () throws -> Void = {
            let bound: (ReportExportFileDescriptor, ReportExportFileIdentity)? = try ReportExportNamespaceAuthority.shared.transaction {
                try residue.root.validate()
                let current: ReportExportDescriptorIO.Metadata
                do {
                    current = try ReportExportDescriptorIO.metadata(
                        at: residue.entryName,
                        relativeTo: residue.root.descriptor.rawValue
                    )
                } catch let error as POSIXError where error.code == .ENOENT {
                    return nil
                }
                guard current.isDirectory,
                      current.owner == Darwin.geteuid(),
                      identityState.bindOrValidate(current.identity) else {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                let owned = try ReportExportDescriptorIO.openDirectory(
                    at: residue.entryName,
                    relativeTo: residue.root.descriptor.rawValue
                )
                guard try ReportExportDescriptorIO.metadata(for: owned.rawValue).identity
                        == current.identity else {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                try ReportExportDescriptorIO.establishPrivateDirectory(owned.rawValue)
                return (owned, current.identity)
            }
            guard let bound else {
                try residue.root.releaseNamespaceLease()
                return
            }
            try backend.applyDescriptorSecurity(to: bound.0)
            try ReportExportDescriptorIO.removeContents(of: bound.0.rawValue)
            try ReportExportDescriptorIO.removeEntry(
                residue.entryName,
                relativeTo: residue.root.descriptor.rawValue,
                expectedIdentity: bound.1,
                flags: AT_REMOVEDIR
            )
            try residue.root.releaseNamespaceLease()
        }
        let terminalRecovery: @Sendable () -> ReportExportCleanupRecoveryRecord? = {
            guard let identity = identityState.identity else { return nil }
            return ReportExportCleanupRecoveryRecord(
                cleanupID: cleanupID,
                rootDirectory: residue.root.presentationURL,
                rootIdentity: residue.root.identity,
                ownedEntryName: residue.entryName,
                ownedIdentity: identity,
                marker: Data(),
                requiresMarker: false
            )
        }
        guard registry.register(
            cleanupID: cleanupID,
            directory: directory,
            operation: cleanupOperation,
            terminalRecovery: terminalRecovery
        ) else {
            throw ReportExportError.temporaryStorageFailed
        }
        do {
            try cleanupOperation()
            registry.didClean(cleanupID: cleanupID)
        } catch {
            registry.retain(
                cleanupID: cleanupID,
                directory: directory,
                operation: cleanupOperation,
                terminalRecovery: terminalRecovery
            )
        }
    }

    private func allocateLegacy() throws -> ReportExportAllocation {
        try fileSystem.createRootDirectory(at: rootDirectory)
        guard try !fileSystem.isSymbolicLink(at: rootDirectory),
              let rootIdentity = try fileSystem.fileIdentity(at: rootDirectory) else {
            throw ReportExportError.unsafeTemporaryPath
        }
        let canonicalRoot = try fileSystem.canonicalURL(for: rootDirectory)
        try fileSystem.applyCompleteFileProtection(at: rootDirectory)
        try fileSystem.excludeFromBackup(at: rootDirectory)

        let cleanupID = UUID()
        guard cleanupRegistry.reserve(cleanupID: cleanupID) else {
            throw ReportExportError.temporaryStorageFailed
        }
        var ownsReservation = true
        defer {
            if ownsReservation {
                cleanupRegistry.releaseReservation(cleanupID: cleanupID)
            }
        }

        var ownedDirectory: URL?
        var allocationID: UUID?
        for _ in 0..<maximumDirectoryAttempts {
            let candidateID = makeDirectoryID()
            let candidate = rootDirectory.appendingPathComponent(
                candidateID.uuidString.lowercased(), isDirectory: true
            )
            do {
                try fileSystem.createExclusiveDirectory(at: candidate)
                ownedDirectory = candidate
                allocationID = UUID()
                break
            } catch where Self.isCollision(error) {
                continue
            }
        }
        guard let ownedDirectory, let allocationID else {
            throw ReportExportError.temporaryStorageFailed
        }

        let markerURL = ownedDirectory.appendingPathComponent(".allocation-id")
        let marker = Data(allocationID.uuidString.lowercased().utf8)
        let fileSystem = self.fileSystem
        let registry = cleanupRegistry
        let markerState = ReportExportMarkerState()
        let identityState = ReportExportLegacyCleanupIdentityState()
        let recoveryRootDirectory = rootDirectory
        let cleanupOperation: @Sendable () throws -> Void = {
            guard let currentRoot = try fileSystem.fileIdentity(at: recoveryRootDirectory),
                  currentRoot == rootIdentity,
                  try !fileSystem.isSymbolicLink(at: recoveryRootDirectory) else {
                throw ReportExportError.cleanupIdentityMismatch
            }
            guard try !fileSystem.isSymbolicLink(at: ownedDirectory) else {
                throw ReportExportError.cleanupIdentityMismatch
            }
            guard let currentOwned = try fileSystem.fileIdentity(at: ownedDirectory) else {
                if fileSystem.exists(at: ownedDirectory) {
                    throw ReportExportError.cleanupIdentityMismatch
                }
                return
            }
            guard identityState.bindOrValidate(currentOwned) else {
                throw ReportExportError.cleanupIdentityMismatch
            }
            let canonicalOwned = try fileSystem.canonicalURL(for: ownedDirectory)
            guard canonicalOwned.deletingLastPathComponent() == canonicalRoot else {
                throw ReportExportError.cleanupIdentityMismatch
            }
            if markerState.wasPublished,
               try fileSystem.read(markerURL) != marker { return }
            guard try fileSystem.fileIdentity(at: recoveryRootDirectory) == rootIdentity,
                  try fileSystem.fileIdentity(at: ownedDirectory) == currentOwned else {
                throw ReportExportError.cleanupIdentityMismatch
            }
            try fileSystem.removeItemIfExists(at: ownedDirectory)
        }
        let terminalRecovery: @Sendable () -> ReportExportCleanupRecoveryRecord? = {
            guard let ownedIdentity = identityState.identity else { return nil }
            return ReportExportCleanupRecoveryRecord(
                cleanupID: cleanupID,
                rootDirectory: recoveryRootDirectory,
                rootIdentity: rootIdentity,
                ownedEntryName: ownedDirectory.lastPathComponent,
                ownedIdentity: ownedIdentity,
                marker: marker,
                requiresMarker: markerState.wasPublished
            )
        }
        let setupCleanup = ReportExportPendingCleanup(
            cleanupID: cleanupID,
            directory: ownedDirectory,
            operation: cleanupOperation,
            terminalRecovery: terminalRecovery
        )
        guard registry.register(
            cleanupID: cleanupID,
            directory: ownedDirectory,
            operation: cleanupOperation,
            terminalRecovery: terminalRecovery
        ) else {
            throw ReportExportError.temporaryStorageFailed
        }
        ownsReservation = false

        do {
            guard try !fileSystem.isSymbolicLink(at: ownedDirectory),
                  let ownedIdentity = try fileSystem.fileIdentity(at: ownedDirectory) else {
                throw ReportExportError.unsafeTemporaryPath
            }
            guard identityState.bindOrValidate(ownedIdentity) else {
                throw ReportExportError.unsafeTemporaryPath
            }
            let canonicalOwned = try fileSystem.canonicalURL(for: ownedDirectory)
            guard canonicalOwned.deletingLastPathComponent() == canonicalRoot else {
                throw ReportExportError.unsafeTemporaryPath
            }
            let boundary = ReportExportOwnedPathBoundary(
                rootDirectory: rootDirectory,
                canonicalRoot: canonicalRoot,
                rootIdentity: rootIdentity,
                ownedDirectory: ownedDirectory,
                canonicalOwned: canonicalOwned,
                ownedIdentity: ownedIdentity
            )
            try boundary.requireCurrentOwnership(using: fileSystem)
            try fileSystem.writeAtomically(marker, to: markerURL)
            markerState.markPublished()
            try boundary.requireCurrentOwnership(using: fileSystem)

            try fileSystem.applyCompleteFileProtection(at: ownedDirectory)
            try fileSystem.excludeFromBackup(at: ownedDirectory)
            let cleanupWithRetention: @Sendable () throws -> Void = {
                do {
                    try cleanupOperation()
                    registry.didClean(cleanupID: cleanupID)
                } catch {
                    registry.retain(
                        cleanupID: cleanupID,
                        directory: ownedDirectory,
                        operation: cleanupOperation,
                        terminalRecovery: terminalRecovery
                    )
                    throw error
                }
            }

            return ReportExportAllocation(
                directoryURL: ownedDirectory,
                write: { data, relativePath in
                    let parent = try boundary.prepareParent(
                        for: relativePath,
                        using: fileSystem
                    )
                    let destination = ownedDirectory.appendingPathComponent(relativePath)
                    guard destination.standardizedFileURL.path.hasPrefix(
                        ownedDirectory.standardizedFileURL.path + "/"
                    ), parent == destination.deletingLastPathComponent()
                    else { throw ReportExportError.unsafeTemporaryPath }
                    guard !fileSystem.exists(at: destination) else {
                        throw ReportExportError.temporaryStorageFailed
                    }
                    try boundary.requireCurrentOwnership(using: fileSystem)
                    try fileSystem.writeAtomically(data, to: destination)
                    _ = try boundary.prepareParent(for: relativePath, using: fileSystem)
                    return destination
                },
                validate: { try boundary.requireCurrentOwnership(using: fileSystem) },
                cleanup: cleanupWithRetention
            )
        } catch {
            do {
                try setupCleanup.operation()
                cleanupRegistry.didClean(cleanupID: setupCleanup.cleanupID)
            } catch {
                cleanupRegistry.retain(
                    cleanupID: setupCleanup.cleanupID,
                    directory: setupCleanup.directory,
                    operation: setupCleanup.operation,
                    terminalRecovery: setupCleanup.terminalRecovery
                )
            }
            throw error
        }
    }

    private func retryTerminalRecoveries() {
        for record in cleanupRegistry.recoveryRecords(for: rootDirectory) {
            do {
                if let descriptorFileSystem = fileSystem
                    as? any ReportExportDescriptorTemporaryFileSystem {
                    _ = try descriptorFileSystem.descriptorBackend
                        .recoverDescriptorAllocation(record)
                } else {
                    try recoverLegacy(record)
                }
                cleanupRegistry.didRecover(cleanupID: record.cleanupID)
            } catch {
                continue
            }
        }
    }

    private func recoverLegacy(_ record: ReportExportCleanupRecoveryRecord) throws {
        guard let rootIdentity = try fileSystem.fileIdentity(at: record.rootDirectory),
              rootIdentity == record.rootIdentity,
              try !fileSystem.isSymbolicLink(at: record.rootDirectory) else { return }
        let owned = record.rootDirectory.appendingPathComponent(
            record.ownedEntryName,
            isDirectory: true
        )
        guard let ownedIdentity = try fileSystem.fileIdentity(at: owned),
              ownedIdentity == record.ownedIdentity,
              try !fileSystem.isSymbolicLink(at: owned) else { return }
        if record.requiresMarker {
            let marker = owned.appendingPathComponent(".allocation-id")
            guard try fileSystem.read(marker) == record.marker else { return }
        }
        guard try fileSystem.fileIdentity(at: record.rootDirectory) == record.rootIdentity,
              try fileSystem.fileIdentity(at: owned) == record.ownedIdentity else { return }
        try fileSystem.removeItemIfExists(at: owned)
    }

    private static func isCollision(_ error: Error) -> Bool {
        if let error = error as? POSIXError, error.code == .EEXIST { return true }
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.Code.fileWriteFileExists.rawValue
    }
}

private struct ReportExportPendingCleanup: Sendable {
    let cleanupID: UUID
    let directory: URL
    let operation: @Sendable () throws -> Void
    let terminalRecovery: @Sendable () -> ReportExportCleanupRecoveryRecord?
}

private final class ReportExportMarkerState: @unchecked Sendable {
    private let lock = NSLock()
    private var published = false

    var wasPublished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return published
    }

    func markPublished() {
        lock.lock()
        published = true
        lock.unlock()
    }
}

private final class ReportExportLegacyCleanupIdentityState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedIdentity: ReportExportFileIdentity?

    var identity: ReportExportFileIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return storedIdentity
    }

    func bindOrValidate(_ candidate: ReportExportFileIdentity) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let storedIdentity { return storedIdentity == candidate }
        storedIdentity = candidate
        return true
    }
}

@MainActor
public final class ReportExportCoordinator: ReportExportGenerating {
    private let repository: any ReportsExportRepository
    private let artifactWorker: ReportExportArtifactWorker
    private let lifecycleWorker: ReportExportLifecycleWorker

    public init(
        repository: any ReportsExportRepository,
        csvEncoder: RFC4180CSVEncoder = RFC4180CSVEncoder(),
        jsonEncoder: JSONExportEncoderV1 = JSONExportEncoderV1(),
        zipWriter: StoredZIPWriter = StoredZIPWriter(),
        photoProvider: any ReportExportPhotoByteProviding = MissingReportExportPhotoProvider(),
        temporaryStore: any ReportExportTemporaryStoring = ReportExportTemporaryStore()
    ) {
        self.repository = repository
        artifactWorker = ReportExportArtifactWorker(
            csvEncoder: csvEncoder,
            jsonEncoder: jsonEncoder,
            zipWriter: zipWriter,
            photoProvider: photoProvider
        )
        lifecycleWorker = ReportExportLifecycleWorker(store: temporaryStore)
    }

    public func generate(_ request: ReportExportRequest) async throws -> ExportArtifactToken {
        guard request.interval.start < request.interval.endExclusive,
              request.interval.start.timeIntervalSinceReferenceDate.isFinite,
              request.interval.endExclusive.timeIntervalSinceReferenceDate.isFinite else {
            throw ReportExportError.invalidInterval
        }
        guard !request.includesPhotos || request.format == .bothZip else {
            throw ReportExportError.photosRequireZIP
        }
        try Task.checkCancellation()
        let snapshot = try await repository.fetchExportSnapshot(
            in: request.interval, modules: request.modules
        )
        guard snapshot.interval == request.interval,
              Set(snapshot.selectedModules) == request.modules else {
            throw ReportExportError.snapshotMismatch
        }
        try Task.checkCancellation()
        let allocation = try await lifecycleWorker.allocate()
        do {
            let shareURLs = try await artifactWorker.generateArtifacts(
                snapshot: snapshot,
                request: request,
                workspace: allocation.workspace
            )
            try Task.checkCancellation()
            return allocation.makeArtifactToken(shareURLs: shareURLs)
        } catch {
            _ = await lifecycleWorker.cleanup(allocation)
            throw error
        }
    }

}

private actor ReportExportArtifactWorker {
    private struct PersistedPayload: Sendable {
        let path: String
        let url: URL
        let byteSize: UInt64
        let sha256: String
        let mediaType: String
    }

    private let csvEncoder: RFC4180CSVEncoder
    private let jsonEncoder: JSONExportEncoderV1
    private let zipWriter: StoredZIPWriter
    private let photoProvider: any ReportExportPhotoByteProviding

    init(
        csvEncoder: RFC4180CSVEncoder,
        jsonEncoder: JSONExportEncoderV1,
        zipWriter: StoredZIPWriter,
        photoProvider: any ReportExportPhotoByteProviding
    ) {
        self.csvEncoder = csvEncoder
        self.jsonEncoder = jsonEncoder
        self.zipWriter = zipWriter
        self.photoProvider = photoProvider
    }

    func generateArtifacts(
        snapshot: ExportSnapshotV1,
        request: ReportExportRequest,
        workspace: ReportExportWorkspace
    ) async throws -> [URL] {
        try Task.checkCancellation()
        switch request.format {
        case .csv:
            return try snapshot.tables.map { table in
                try persist(
                    csvEncoder.encode(table),
                    path: "\(table.module.rawValue).csv",
                    mediaType: "text/csv",
                    workspace: workspace
                ).url
            }
        case .json:
            return [try persist(
                jsonEncoder.encode(snapshot),
                path: "export.json",
                mediaType: "application/json",
                workspace: workspace
            ).url]
        case .bothZip:
            return [try await makeZIP(
                snapshot: snapshot,
                request: request,
                workspace: workspace
            )]
        }
    }

    private func makeZIP(
        snapshot: ExportSnapshotV1,
        request: ReportExportRequest,
        workspace: ReportExportWorkspace
    ) async throws -> URL {
        var payloads: [PersistedPayload] = []
        payloads.append(try persist(
            jsonEncoder.encode(snapshot),
            path: "json/export.json",
            mediaType: "application/json",
            workspace: workspace
        ))
        for table in snapshot.tables {
            let path = "csv/\(table.module.rawValue).csv"
            payloads.append(try persist(
                csvEncoder.encode(table),
                path: path,
                mediaType: "text/csv",
                workspace: workspace
            ))
        }

        var photoStatuses: [ExportManifestPhotoV1] = []
        if request.includesPhotos {
            for photoID in photoCandidateIDs(snapshot) {
                try Task.checkCancellation()
                let identifier = photoID.uuidString.lowercased()
                let result = try await persistPhoto(
                    photoID: photoID,
                    identifier: identifier,
                    workspace: workspace
                )
                if let payload = result.payload { payloads.append(payload) }
                photoStatuses.append(result.status)
            }
        }
        try Task.checkCancellation()

        let manifest = ExportManifestV1(
            interval: .init(
                start: try CanonicalExportScalarV1.timestamp(request.interval.start),
                endExclusive: try CanonicalExportScalarV1.timestamp(request.interval.endExclusive)
            ),
            selectedModules: snapshot.selectedModules.map(\.rawValue),
            format: request.format.rawValue,
            includesPhotos: request.includesPhotos,
            payloads: payloads.map {
                .init(
                    relativePath: $0.path,
                    byteSize: $0.byteSize,
                    sha256: $0.sha256,
                    mediaType: $0.mediaType
                )
            },
            photos: photoStatuses
        )
        let manifestURL = try workspace.write(
            manifest.encoded(),
            relativePath: "manifest.json"
        )
        var entries = payloads.map {
            StoredZIPEntry(relativePath: $0.path, sourceURL: $0.url)
        }
        entries.append(.init(relativePath: "manifest.json", sourceURL: manifestURL))
        let destination = try workspace.zipDestination(relativePath: "fo-health-export.zip")
        try await zipWriter.writeStored(entries: entries, to: destination)
        try workspace.validateCurrentOwnership()
        return destination.url
    }

    private func persistPhoto(
        photoID: UUID,
        identifier: String,
        workspace: ReportExportWorkspace
    ) async throws -> (payload: PersistedPayload?, status: ExportManifestPhotoV1) {
        let result = try await photoProvider.jpegData(for: photoID)
        switch result {
        case let .available(data) where Self.isJPEG(data):
            let path = "photos/\(identifier).jpg"
            return (
                try persist(
                    data,
                    path: path,
                    mediaType: "image/jpeg",
                    workspace: workspace
                ),
                .init(photoID: identifier, status: .included, relativePath: path)
            )
        case .available, .corrupt:
            return (nil, .init(photoID: identifier, status: .corrupt))
        case .missing:
            return (nil, .init(photoID: identifier, status: .missing))
        }
    }

    private func persist(
        _ data: Data,
        path: String,
        mediaType: String,
        workspace: ReportExportWorkspace
    ) throws -> PersistedPayload {
        try Task.checkCancellation()
        let byteSize = UInt64(data.count)
        let digest = ReportExportSHA256.hexDigest(data)
        try Task.checkCancellation()
        let url = try workspace.write(data, relativePath: path)
        try Task.checkCancellation()
        return PersistedPayload(
            path: path,
            url: url,
            byteSize: byteSize,
            sha256: digest,
            mediaType: mediaType
        )
    }

    private func photoCandidateIDs(_ snapshot: ExportSnapshotV1) -> [UUID] {
        var result = Set<UUID>()
        for table in snapshot.tables where table.module == .photos {
            for row in table.rows {
                guard row.cells.first(where: { $0.columnName == "record_type" })?.value
                        == .text(ExportRecordTypeV1.progressPhoto.rawValue),
                      row.cells.first(where: {
                          $0.columnName == "progress_photo_image_available"
                      })?.value == .boolean(true),
                      case let .uuid(identifier)? = row.cells.first(where: {
                          $0.columnName == "id"
                      })?.value else { continue }
                result.insert(identifier)
            }
        }
        return result.sorted { $0.uuidString.lowercased() < $1.uuidString.lowercased() }
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.count >= 4
            && data[data.startIndex] == 0xff
            && data[data.index(after: data.startIndex)] == 0xd8
            && data[data.index(data.endIndex, offsetBy: -2)] == 0xff
            && data[data.index(before: data.endIndex)] == 0xd9
    }
}
