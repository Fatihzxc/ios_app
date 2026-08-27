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

public final class FileCloudPhotoAssetTemporaryStore: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager
    private let makeID: @Sendable () -> UUID

    public init(
        directory: URL,
        fileManager: FileManager = .default,
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.makeID = makeID
    }

    public func createUploadFile(bytes: Data) throws -> URL {
        let url = try makeOwnedURL()
        try writeProtected(bytes, to: url)
        return url
    }

    public func copyDownloadedFile(from source: URL) throws -> URL {
        let destination = try makeOwnedURL()
        do {
            try fileManager.copyItem(at: source, to: destination)
            #if !targetEnvironment(simulator)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: destination.path
            )
            #endif
            return destination
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    public func readFile(at url: URL) throws -> Data {
        guard isOwned(url) else {
            throw CocoaError(.fileReadNoPermission)
        }
        return try Data(contentsOf: url)
    }

    public func removeFile(at url: URL) {
        guard isOwned(url) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func makeOwnedURL() throws -> URL {
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
        return directory.appendingPathComponent(
            makeID().uuidString.lowercased() + ".asset"
        )
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

    private func isOwned(_ url: URL) -> Bool {
        let ownedRoot = directory.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(ownedRoot)
    }
}

public actor NoOpCloudPhotoAssetCoordinator: CloudPhotoAssetSynchronizing {
    public static let shared = NoOpCloudPhotoAssetCoordinator()

    public init() {}

    public func synchronize() async -> CloudPhotoAssetSyncOutcome {
        .synchronized
    }
}
