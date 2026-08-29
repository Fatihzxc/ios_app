import Foundation
import Observation

@MainActor
public protocol ProgressPhotoComparisonTemporaryStoring: AnyObject, Sendable {
    func writeOneUseJPEG(_ data: Data) throws -> ProgressPhotoOneUseArtifact
}

@MainActor
protocol ProgressPhotoComparisonTemporaryFileSystem: AnyObject {
    func createDirectory(at url: URL) throws
    func createExclusiveDirectory(at url: URL) throws
    func applyCompleteFileProtection(at url: URL) throws
    func writeAtomically(_ data: Data, to url: URL) throws
    func removeItemIfExists(at url: URL) throws
}

@MainActor
protocol ProgressPhotoComparisonCleanupScheduling: AnyObject {
    func schedule(
        afterNanoseconds delay: UInt64,
        operation: @escaping @MainActor () -> Void
    )
}

@MainActor
final class SystemProgressPhotoComparisonCleanupScheduler:
    ProgressPhotoComparisonCleanupScheduling {
    func schedule(
        afterNanoseconds delay: UInt64,
        operation: @escaping @MainActor () -> Void
    ) {
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            operation()
        }
    }
}

@MainActor
final class ProgressPhotoComparisonLifetimeCleanupRegistry {
    static let shared = ProgressPhotoComparisonLifetimeCleanupRegistry()

    private struct Entry {
        let token: UUID
        let rootDirectory: URL
        let ownedDirectory: URL
        let cleanup: @MainActor () throws -> Void
        var failedAttempts: Int
    }

    private let scheduler: any ProgressPhotoComparisonCleanupScheduling
    private var entries: [URL: Entry] = [:]
    private var scheduledTokens: [URL: UUID] = [:]
    private let retryDelaysNanoseconds: [UInt64] = [
        20_000_000,
        50_000_000,
        100_000_000,
        250_000_000,
        500_000_000,
        1_000_000_000,
        2_000_000_000,
        5_000_000_000,
        10_000_000_000,
        30_000_000_000,
    ]

    convenience init() {
        self.init(scheduler: SystemProgressPhotoComparisonCleanupScheduler())
    }

    init(scheduler: any ProgressPhotoComparisonCleanupScheduling) {
        self.scheduler = scheduler
    }

    func retainOwnedDirectory(
        _ ownedDirectory: URL,
        under rootDirectory: URL,
        cleanup: @escaping @MainActor () throws -> Void
    ) {
        let root = rootDirectory.standardizedFileURL
        let directory = ownedDirectory.standardizedFileURL
        guard Self.isExactOwnedChild(directory, under: root) else { return }

        if entries[directory] == nil {
            entries[directory] = Entry(
                token: UUID(),
                rootDirectory: root,
                ownedDirectory: directory,
                cleanup: cleanup,
                failedAttempts: 1
            )
        }
        scheduleRetryIfNeeded(for: directory)
    }

    func didCleanOwnedDirectory(
        _ ownedDirectory: URL,
        under rootDirectory: URL
    ) {
        let root = rootDirectory.standardizedFileURL
        let directory = ownedDirectory.standardizedFileURL
        guard Self.isExactOwnedChild(directory, under: root) else { return }
        entries.removeValue(forKey: directory)
        scheduledTokens.removeValue(forKey: directory)
    }

    private func scheduleRetryIfNeeded(for directory: URL) {
        guard let entry = entries[directory],
              scheduledTokens[directory] == nil else {
            return
        }
        let delayIndex = min(
            max(entry.failedAttempts - 1, 0),
            retryDelaysNanoseconds.count - 1
        )
        scheduledTokens[directory] = entry.token
        scheduler.schedule(
            afterNanoseconds: retryDelaysNanoseconds[delayIndex]
        ) { [weak self] in
            self?.retry(directory, token: entry.token)
        }
    }

    private func retry(_ directory: URL, token: UUID) {
        guard scheduledTokens[directory] == token else { return }
        scheduledTokens.removeValue(forKey: directory)
        guard var entry = entries[directory],
              entry.token == token,
              Self.isExactOwnedChild(
                entry.ownedDirectory,
                under: entry.rootDirectory
              ) else {
            entries.removeValue(forKey: directory)
            return
        }
        do {
            try entry.cleanup()
            entries.removeValue(forKey: directory)
        } catch {
            entry.failedAttempts += 1
            entries[directory] = entry
            scheduleRetryIfNeeded(for: directory)
        }
    }

    private static func isExactOwnedChild(
        _ directory: URL,
        under rootDirectory: URL
    ) -> Bool {
        guard directory.deletingLastPathComponent().standardizedFileURL
                == rootDirectory,
              let identifier = UUID(uuidString: directory.lastPathComponent) else {
            return false
        }
        return rootDirectory.appendingPathComponent(
            identifier.uuidString.lowercased(),
            isDirectory: true
        ).standardizedFileURL == directory
    }
}

@MainActor
public final class ProgressPhotoOneUseArtifact: Identifiable {
    public let id: UUID
    public let fileURL: URL
    private var didCleanUp = false
    private let cleanupAction: @MainActor () throws -> Void

    init(
        id: UUID = UUID(),
        fileURL: URL,
        cleanup: @escaping @MainActor () throws -> Void
    ) {
        self.id = id
        self.fileURL = fileURL
        cleanupAction = cleanup
    }

    @discardableResult
    public func cleanup() -> Bool {
        guard !didCleanUp else { return true }
        do {
            try cleanupAction()
            didCleanUp = true
            return true
        } catch {
            return false
        }
    }
}

@MainActor
final class FileManagerProgressPhotoComparisonTemporaryFileSystem:
    ProgressPhotoComparisonTemporaryFileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func createExclusiveDirectory(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
    }

    func applyCompleteFileProtection(at url: URL) throws {
        #if !targetEnvironment(simulator)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #endif
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        #if targetEnvironment(simulator)
        try data.write(to: url, options: .atomic)
        #else
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #endif
    }

    func removeItemIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

@MainActor
public final class ProgressPhotoComparisonTemporaryStore:
    ProgressPhotoComparisonTemporaryStoring {
    private let rootDirectory: URL
    private let fileSystem: any ProgressPhotoComparisonTemporaryFileSystem
    private let makeDirectoryID: @MainActor () -> UUID
    private let lifetimeCleanupRegistry: ProgressPhotoComparisonLifetimeCleanupRegistry
    private var pendingOwnedDirectories: [URL] = []
    private let maximumDirectoryAttempts = 8

    public convenience init() {
        self.init(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("FOAppProgressPhotoShares", isDirectory: true),
            fileSystem: FileManagerProgressPhotoComparisonTemporaryFileSystem(),
            makeDirectoryID: { UUID() },
            lifetimeCleanupRegistry: .shared
        )
    }

    init(
        rootDirectory: URL,
        fileSystem: any ProgressPhotoComparisonTemporaryFileSystem,
        makeDirectoryID: @escaping @MainActor () -> UUID,
        lifetimeCleanupRegistry: ProgressPhotoComparisonLifetimeCleanupRegistry = .shared
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileSystem = fileSystem
        self.makeDirectoryID = makeDirectoryID
        self.lifetimeCleanupRegistry = lifetimeCleanupRegistry
    }

    public func writeOneUseJPEG(_ data: Data) throws -> ProgressPhotoOneUseArtifact {
        guard !data.isEmpty else {
            throw ProgressPhotoComparisonShareError.temporaryStorageFailed
        }
        guard retryPendingOwnedDirectoryCleanup() else {
            throw ProgressPhotoComparisonShareError.temporaryStorageFailed
        }
        var allocatedOwnedDirectory: URL?
        do {
            try fileSystem.createDirectory(at: rootDirectory)
            try fileSystem.applyCompleteFileProtection(at: rootDirectory)
            let ownedDirectory = try allocateExclusiveOwnedDirectory()
            allocatedOwnedDirectory = ownedDirectory
            let fileURL = ownedDirectory.appendingPathComponent("comparison.jpg")
            try fileSystem.applyCompleteFileProtection(at: ownedDirectory)
            try fileSystem.writeAtomically(data, to: fileURL)
            let cleanupFileSystem = fileSystem
            let cleanupRegistry = lifetimeCleanupRegistry
            let cleanupRootDirectory = rootDirectory
            return ProgressPhotoOneUseArtifact(fileURL: fileURL) { [weak self] in
                do {
                    try cleanupFileSystem.removeItemIfExists(at: ownedDirectory)
                    self?.pendingOwnedDirectories.removeAll { $0 == ownedDirectory }
                    cleanupRegistry.didCleanOwnedDirectory(
                        ownedDirectory,
                        under: cleanupRootDirectory
                    )
                } catch {
                    self?.rememberPendingOwnedDirectory(ownedDirectory)
                    cleanupRegistry.retainOwnedDirectory(
                        ownedDirectory,
                        under: cleanupRootDirectory
                    ) { [weak self] in
                        try cleanupFileSystem.removeItemIfExists(at: ownedDirectory)
                        self?.pendingOwnedDirectories.removeAll {
                            $0 == ownedDirectory
                        }
                    }
                    throw error
                }
            }
        } catch {
            if let allocatedOwnedDirectory {
                do {
                    try fileSystem.removeItemIfExists(at: allocatedOwnedDirectory)
                } catch {
                    rememberPendingOwnedDirectory(allocatedOwnedDirectory)
                    retainLifetimeCleanup(for: allocatedOwnedDirectory)
                }
            }
            throw ProgressPhotoComparisonShareError.temporaryStorageFailed
        }
    }

    private func allocateExclusiveOwnedDirectory() throws -> URL {
        for _ in 0..<maximumDirectoryAttempts {
            let candidate = rootDirectory.appendingPathComponent(
                makeDirectoryID().uuidString.lowercased(),
                isDirectory: true
            )
            do {
                try fileSystem.createExclusiveDirectory(at: candidate)
                return candidate
            } catch where Self.isDirectoryCollision(error) {
                continue
            }
        }
        throw ProgressPhotoComparisonShareError.temporaryStorageFailed
    }

    private func retryPendingOwnedDirectoryCleanup() -> Bool {
        let pending = pendingOwnedDirectories
        pendingOwnedDirectories.removeAll(keepingCapacity: true)
        for directory in pending {
            do {
                try fileSystem.removeItemIfExists(at: directory)
                lifetimeCleanupRegistry.didCleanOwnedDirectory(
                    directory,
                    under: rootDirectory
                )
            } catch {
                rememberPendingOwnedDirectory(directory)
                retainLifetimeCleanup(for: directory)
            }
        }
        return pendingOwnedDirectories.isEmpty
    }

    private func rememberPendingOwnedDirectory(_ directory: URL) {
        guard !pendingOwnedDirectories.contains(directory) else { return }
        pendingOwnedDirectories.append(directory)
    }

    private func retainLifetimeCleanup(for directory: URL) {
        let cleanupFileSystem = fileSystem
        lifetimeCleanupRegistry.retainOwnedDirectory(
            directory,
            under: rootDirectory
        ) { [weak self] in
            try cleanupFileSystem.removeItemIfExists(at: directory)
            self?.pendingOwnedDirectories.removeAll { $0 == directory }
        }
    }

    private static func isDirectoryCollision(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.Code.fileWriteFileExists.rawValue
    }
}

public enum ProgressPhotoComparisonSharePhase: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case failed
}

@MainActor
@Observable
public final class ProgressPhotoComparisonShareCoordinator {
    public private(set) var phase: ProgressPhotoComparisonSharePhase = .idle
    public private(set) var artifact: ProgressPhotoOneUseArtifact?

    @ObservationIgnored
    private let renderer: any ProgressPhotoComparisonRendering
    @ObservationIgnored
    private let temporaryStore: any ProgressPhotoComparisonTemporaryStoring
    @ObservationIgnored
    private var generation: UInt64 = 0
    @ObservationIgnored
    private var pendingCleanupArtifacts: [ProgressPhotoOneUseArtifact] = []

    public init(
        renderer: any ProgressPhotoComparisonRendering =
            UIKitProgressPhotoComparisonRenderer(),
        temporaryStore: any ProgressPhotoComparisonTemporaryStoring =
            ProgressPhotoComparisonTemporaryStore()
    ) {
        self.renderer = renderer
        self.temporaryStore = temporaryStore
    }

    public var hasRetryableError: Bool {
        phase == .failed
    }

    public func share(
        _ descriptorProvider: @MainActor () throws ->
            ProgressPhotoComparisonShareDescriptor
    ) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let operationGeneration = generation
        guard cleanupCurrentAndPendingArtifacts() else {
            phase = .failed
            return
        }
        phase = .preparing
        do {
            let descriptor = try descriptorProvider()
            try ensureCurrent(operationGeneration)
            let renderedData = try await renderer.render(descriptor)
            try ensureCurrent(operationGeneration)
            let artifact = try temporaryStore.writeOneUseJPEG(renderedData)
            do {
                try ensureCurrent(operationGeneration)
            } catch {
                retainIfCleanupFails(artifact)
                throw error
            }
            self.artifact = artifact
            phase = .ready
        } catch is CancellationError {
            guard operationGeneration == generation else { return }
            phase = cleanupCurrentAndPendingArtifacts() ? .idle : .failed
        } catch {
            guard operationGeneration == generation else { return }
            _ = cleanupCurrentAndPendingArtifacts()
            phase = .failed
        }
    }

    public func activityDidFinish(
        artifactID: UUID,
        completed: Bool,
        error: Error?
    ) {
        guard artifact?.id == artifactID else { return }
        _ = completed
        generation += 1
        let cleaned = cleanupCurrentAndPendingArtifacts()
        phase = error == nil && cleaned ? .idle : .failed
    }

    public func presentationDidFail(artifactID: UUID) {
        guard artifact?.id == artifactID else { return }
        generation += 1
        _ = cleanupCurrentAndPendingArtifacts()
        phase = .failed
    }

    public func dismiss() {
        generation += 1
        phase = cleanupCurrentAndPendingArtifacts() ? .idle : .failed
    }

    private func ensureCurrent(_ operationGeneration: UInt64) throws {
        try Task.checkCancellation()
        guard generation == operationGeneration else { throw CancellationError() }
    }

    private func cleanupCurrentAndPendingArtifacts() -> Bool {
        let pending = pendingCleanupArtifacts
        pendingCleanupArtifacts.removeAll(keepingCapacity: true)
        for artifact in pending where !artifact.cleanup() {
            pendingCleanupArtifacts.append(artifact)
        }
        if let artifact {
            self.artifact = nil
            retainIfCleanupFails(artifact)
        }
        return pendingCleanupArtifacts.isEmpty
    }

    private func retainIfCleanupFails(_ artifact: ProgressPhotoOneUseArtifact) {
        if artifact.cleanup() {
            pendingCleanupArtifacts.removeAll { $0.id == artifact.id }
        } else {
            guard !pendingCleanupArtifacts.contains(where: { $0.id == artifact.id }) else {
                return
            }
            pendingCleanupArtifacts.append(artifact)
        }
    }
}
