import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

public struct CappedPhotoFileReader: Sendable {
    public init() {}

    public func readData(
        at url: URL,
        maximumBytes: Int
    ) async throws -> Data {
        precondition(maximumBytes > 0 && maximumBytes < Int.max)
        return try await Task.detached(priority: .userInitiated) {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(
                    forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]
                )
            } catch {
                throw PhotoSelectionLoadError.fileUnavailable
            }
            guard let fileSize = values.fileSize else {
                throw PhotoSelectionLoadError.fileUnavailable
            }
            guard fileSize <= maximumBytes else {
                throw PhotoSelectionLoadError.inputTooLarge(
                    maximumBytes: maximumBytes
                )
            }

            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: url)
            } catch {
                throw PhotoSelectionLoadError.fileUnavailable
            }
            defer { try? handle.close() }
            let bytes: Data
            do {
                bytes = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            } catch {
                throw PhotoSelectionLoadError.fileUnavailable
            }
            guard bytes.count <= maximumBytes else {
                throw PhotoSelectionLoadError.inputTooLarge(
                    maximumBytes: maximumBytes
                )
            }
            return bytes
        }.value
    }
}

public final class CappedPhotoStagingStore: @unchecked Sendable {
    private static let copyChunkBytes = 64 * 1_024

    private let stagingRoot: URL
    private let removeItemOperation: @Sendable (URL) throws -> Void
    private let lock = NSLock()
    private var isPrepared = false
    private var pendingRemovalDirectories = Set<URL>()

    public init(
        stagingRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ProgressPhotoPickerStaging",
                isDirectory: true
            ),
        removeItem: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.removeItem(at: $0)
        }
    ) {
        self.stagingRoot = stagingRoot
        removeItemOperation = removeItem
    }

    public func prepare() async {
        await Task.detached(priority: .utility) { [self] in
            prepareIgnoringErrors()
        }.value
    }

    public func stageFile(
        at sourceURL: URL,
        maximumBytes: Int
    ) throws -> URL {
        precondition(maximumBytes > 0 && maximumBytes < Int.max)
        lock.lock()
        defer { lock.unlock() }

        try prepareLocked()
        if let fileSize = try? sourceURL.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize, fileSize > maximumBytes {
            throw PhotoSelectionLoadError.inputTooLarge(
                maximumBytes: maximumBytes
            )
        }

        let directory = stagingRoot.appendingPathComponent(
            UUID().uuidString.lowercased(),
            isDirectory: true
        )
        let destination = directory.appendingPathComponent("selection")
        do {
            try createProtectedDirectory(at: directory)
            try createProtectedEmptyFile(at: destination)
            try copyWithHardCap(
                from: sourceURL,
                to: destination,
                maximumBytes: maximumBytes
            )
            return destination
        } catch {
            scheduleOrPerformRemovalLocked(directory)
            if let selectionError = error as? PhotoSelectionLoadError {
                throw selectionError
            }
            throw PhotoSelectionLoadError.fileUnavailable
        }
    }

    public func removeStagedFile(at fileURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        let directory = fileURL.deletingLastPathComponent()
        guard directory.deletingLastPathComponent() == stagingRoot else {
            return
        }
        scheduleOrPerformRemovalLocked(directory)
    }

    private func prepareLocked() throws {
        let fileManager = FileManager.default
        if !isPrepared {
            if fileManager.fileExists(atPath: stagingRoot.path) {
                try removeItemOperation(stagingRoot)
            }
            try createProtectedDirectory(at: stagingRoot)
            isPrepared = true
        }
        retryPendingRemovalsLocked()
    }

    private func prepareIgnoringErrors() {
        lock.lock()
        defer { lock.unlock() }
        try? prepareLocked()
    }

    private func scheduleOrPerformRemovalLocked(_ directory: URL) {
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try removeItemOperation(directory)
            }
            pendingRemovalDirectories.remove(directory)
        } catch {
            pendingRemovalDirectories.insert(directory)
        }
    }

    private func retryPendingRemovalsLocked() {
        for directory in pendingRemovalDirectories.sorted(by: {
            $0.path < $1.path
        }) {
            scheduleOrPerformRemovalLocked(directory)
        }
    }

    private func createProtectedDirectory(at url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        #if !targetEnvironment(simulator)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #endif
    }

    private func createProtectedEmptyFile(at url: URL) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if !targetEnvironment(simulator)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: attributes
        ) else {
            throw PhotoSelectionLoadError.fileUnavailable
        }
    }

    private func copyWithHardCap(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumBytes: Int
    ) throws {
        let source: FileHandle
        let destination: FileHandle
        do {
            source = try FileHandle(forReadingFrom: sourceURL)
            destination = try FileHandle(forWritingTo: destinationURL)
        } catch {
            throw PhotoSelectionLoadError.fileUnavailable
        }
        defer {
            try? source.close()
            try? destination.close()
        }

        var copiedBytes = 0
        while true {
            let remaining = maximumBytes - copiedBytes
            let readCount = min(Self.copyChunkBytes, remaining + 1)
            let chunk: Data
            do {
                chunk = try source.read(upToCount: readCount) ?? Data()
            } catch {
                throw PhotoSelectionLoadError.fileUnavailable
            }
            guard !chunk.isEmpty else { return }
            guard chunk.count <= remaining else {
                throw PhotoSelectionLoadError.inputTooLarge(
                    maximumBytes: maximumBytes
                )
            }
            do {
                try destination.write(contentsOf: chunk)
            } catch {
                throw PhotoSelectionLoadError.fileUnavailable
            }
            copiedBytes += chunk.count
        }
    }
}

@MainActor
public struct SystemPhotosPickerView: View {
    @State private var selection: PhotosPickerItem?
    private let title: String
    private let accessState: PhotoLibraryAccessState
    private let onSelection: @MainActor ((any PhotoSelectionLoading)?) -> Void

    public init(
        title: String,
        accessState: PhotoLibraryAccessState = .authorized,
        onSelection: @escaping @MainActor ((any PhotoSelectionLoading)?) -> Void
    ) {
        self.title = title
        self.accessState = accessState
        self.onSelection = onSelection
    }

    public var body: some View {
        PhotosPicker(
            selection: $selection,
            matching: .images
        ) {
            Label(title, systemImage: "photo.on.rectangle.angled")
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("photos.picker")
        .photoLibraryAccessEvidence(accessState)
        .disabled(!SystemPhotoPickerAvailability.isEnabled(for: accessState))
        .onChange(of: selection) { _, item in
            guard let item else { return }
            onSelection(
                PhotosPickerItemLoader(
                    item: item,
                    reader: CappedPhotoFileReader()
                )
            )
            selection = nil
        }
        .task {
            await ImportedPhotoFile.prepareStaging()
        }
    }
}

private extension View {
    @ViewBuilder
    func photoLibraryAccessEvidence(_ accessState: PhotoLibraryAccessState) -> some View {
        #if DEBUG
        accessibilityValue(accessState.rawValue)
        #else
        self
        #endif
    }
}

@MainActor
private final class PhotosPickerItemLoader: PhotoSelectionLoading {
    private let item: PhotosPickerItem
    private let reader: CappedPhotoFileReader

    init(item: PhotosPickerItem, reader: CappedPhotoFileReader) {
        self.item = item
        self.reader = reader
    }

    func loadData(maximumBytes: Int) async throws -> Data? {
        guard let imported = try await item.loadTransferable(
            type: ImportedPhotoFile.self
        ) else { return nil }
        do {
            let bytes = try await reader.readData(
                at: imported.fileURL,
                maximumBytes: maximumBytes
            )
            await imported.removeTemporaryCopy()
            return bytes
        } catch {
            await imported.removeTemporaryCopy()
            throw error
        }
    }
}

private struct ImportedPhotoFile: Transferable, Sendable {
    let fileURL: URL
    private static let stagingStore = CappedPhotoStagingStore()

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let destination = try stagingStore.stageFile(
                at: received.file,
                maximumBytes: PhotoAssetPolicy.production.maximumInputBytes
            )
            return ImportedPhotoFile(fileURL: destination)
        }
    }

    static func prepareStaging() async {
        await stagingStore.prepare()
    }

    func removeTemporaryCopy() async {
        let fileURL = fileURL
        await Task.detached(priority: .utility) {
            Self.stagingStore.removeStagedFile(at: fileURL)
        }.value
    }
}
