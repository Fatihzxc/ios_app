import Foundation

public enum PhotoAssetCleanupJournalError: Error, Equatable, Sendable {
    case invalidContents
    case storageUnavailable
}

public protocol PhotoAssetCleanupJournaling: AnyObject, Sendable {
    func loadPendingAssetIDs() async throws -> Set<String>
    func addPendingAssetID(_ assetID: String) async throws
    func removePendingAssetID(_ assetID: String) async throws
}

public actor FilePhotoAssetCleanupJournal: PhotoAssetCleanupJournaling {
    private let explicitApplicationSupportDirectory: URL?
    private let fileManager = FileManager.default

    public init(
        applicationSupportDirectory: URL? = nil
    ) {
        explicitApplicationSupportDirectory = applicationSupportDirectory
    }

    public func loadPendingAssetIDs() async throws -> Set<String> {
        let url = try journalURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        do {
            let values = try JSONDecoder().decode(
                [String].self,
                from: Data(contentsOf: url)
            )
            guard values.allSatisfy(isOpaquePhotoAssetID) else {
                throw PhotoAssetCleanupJournalError.invalidContents
            }
            return Set(values)
        } catch let error as PhotoAssetCleanupJournalError {
            throw error
        } catch {
            throw PhotoAssetCleanupJournalError.invalidContents
        }
    }

    public func addPendingAssetID(_ assetID: String) async throws {
        guard isOpaquePhotoAssetID(assetID) else {
            throw PhotoAssetCleanupJournalError.invalidContents
        }
        var pending = try await loadPendingAssetIDs()
        pending.insert(assetID)
        try persist(pending)
    }

    public func removePendingAssetID(_ assetID: String) async throws {
        guard isOpaquePhotoAssetID(assetID) else {
            throw PhotoAssetCleanupJournalError.invalidContents
        }
        var pending = try await loadPendingAssetIDs()
        pending.remove(assetID)
        try persist(pending)
    }

    private func journalURL() throws -> URL {
        let applicationSupport: URL
        if let explicitApplicationSupportDirectory {
            applicationSupport = explicitApplicationSupportDirectory
        } else if let resolved = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            applicationSupport = resolved
        } else {
            throw PhotoAssetCleanupJournalError.storageUnavailable
        }
        return applicationSupport
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent("cleanup-journal.json")
    }

    private func persist(_ pending: Set<String>) throws {
        let url = try journalURL()
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(pending.sorted())
            #if targetEnvironment(simulator)
            try data.write(to: url, options: .atomic)
            #else
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtection]
            )
            #endif
        } catch let error as PhotoAssetCleanupJournalError {
            throw error
        } catch {
            throw PhotoAssetCleanupJournalError.storageUnavailable
        }
    }
}
