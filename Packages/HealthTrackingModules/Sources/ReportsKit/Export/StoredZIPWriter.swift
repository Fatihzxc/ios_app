import Darwin
import Foundation

public struct StoredZIPEntry: Equatable, Sendable {
    public let relativePath: String
    public let sourceURL: URL

    public init(relativePath: String, sourceURL: URL) {
        self.relativePath = relativePath
        self.sourceURL = sourceURL
    }
}

public enum StoredZIPLimit: String, Equatable, Sendable {
    case entrySize
    case nameLength
    case entryCount
    case offset
    case centralDirectorySize
    case centralDirectoryOffset
}

public struct StoredZIPLimits: Equatable, Sendable {
    public let maxEntrySize: UInt64
    public let maxNameLength: Int
    public let maxEntryCount: Int
    public let maxOffset: UInt64
    public let maxCentralDirectorySize: UInt64
    public let maxCentralDirectoryOffset: UInt64
    public let chunkSize: Int

    public init(
        maxEntrySize: UInt64 = UInt64(UInt32.max),
        maxNameLength: Int = Int(UInt16.max),
        maxEntryCount: Int = Int(UInt16.max),
        maxOffset: UInt64 = UInt64(UInt32.max),
        maxCentralDirectorySize: UInt64 = UInt64(UInt32.max),
        maxCentralDirectoryOffset: UInt64 = UInt64(UInt32.max),
        chunkSize: Int = 64 * 1_024
    ) {
        self.maxEntrySize = min(maxEntrySize, UInt64(UInt32.max))
        self.maxNameLength = min(maxNameLength, Int(UInt16.max))
        self.maxEntryCount = min(maxEntryCount, Int(UInt16.max))
        self.maxOffset = min(maxOffset, UInt64(UInt32.max))
        self.maxCentralDirectorySize = min(maxCentralDirectorySize, UInt64(UInt32.max))
        self.maxCentralDirectoryOffset = min(maxCentralDirectoryOffset, UInt64(UInt32.max))
        self.chunkSize = max(1, chunkSize)
    }
}

public enum StoredZIPWriterError: Error, Equatable, Sendable {
    case unsafeRelativePath(String)
    case duplicateEntry(String)
    case invalidSource(URL)
    case destinationExists
    case destinationAliasesInput
    case zip32LimitExceeded(StoredZIPLimit)
    case sourceChanged(URL)
    case unableToCreatePartial
}

public struct StoredZIPWriter: Sendable {
    public typealias ChunkObserver = @Sendable (Int) async throws -> Void
    typealias StagingObserver = @Sendable (URL, String) throws -> Void

    private let limits: StoredZIPLimits
    private let chunkObserver: ChunkObserver?
    private let stagingObserver: StagingObserver?
    private let initialMetadataObserver: StagingObserver?
    private let unlinkOperationObserver: StagingObserver?
    private let namespaceRegistry: ReportExportVisibleDirectoryRegistry
    private let stageResidueRegistry: ReportExportStageResidueRegistry

    public init(
        limits: StoredZIPLimits = StoredZIPLimits(),
        chunkObserver: ChunkObserver? = nil
    ) {
        self.limits = limits
        self.chunkObserver = chunkObserver
        stagingObserver = nil
        initialMetadataObserver = nil
        unlinkOperationObserver = nil
        namespaceRegistry = .shared
        stageResidueRegistry = .shared
    }

    init(
        limits: StoredZIPLimits = StoredZIPLimits(),
        chunkObserver: ChunkObserver? = nil,
        stagingObserver: @escaping StagingObserver,
        unlinkOperationObserver: StagingObserver? = nil,
        namespaceRegistry: ReportExportVisibleDirectoryRegistry = .shared,
        stageResidueRegistry: ReportExportStageResidueRegistry = .shared
    ) {
        self.limits = limits
        self.chunkObserver = chunkObserver
        self.stagingObserver = stagingObserver
        initialMetadataObserver = nil
        self.unlinkOperationObserver = unlinkOperationObserver
        self.namespaceRegistry = namespaceRegistry
        self.stageResidueRegistry = stageResidueRegistry
    }

    init(
        limits: StoredZIPLimits = StoredZIPLimits(),
        chunkObserver: ChunkObserver? = nil,
        initialMetadataObserver: @escaping StagingObserver,
        namespaceRegistry: ReportExportVisibleDirectoryRegistry = .shared,
        stageResidueRegistry: ReportExportStageResidueRegistry = .shared
    ) {
        self.limits = limits
        self.chunkObserver = chunkObserver
        stagingObserver = nil
        self.initialMetadataObserver = initialMetadataObserver
        unlinkOperationObserver = nil
        self.namespaceRegistry = namespaceRegistry
        self.stageResidueRegistry = stageResidueRegistry
    }

    public func writeStored(entries: [StoredZIPEntry], to destination: URL) async throws {
        let binding = try FileManagerReportExportTemporaryFileSystem()
            .standaloneZIPDestination(at: destination)
        try await writeStored(entries: entries, to: binding)
    }

    func writeStored(
        entries: [StoredZIPEntry],
        to destination: StoredZIPDestinationBinding
    ) async throws {
        let plan = try ReportExportNamespaceAuthority.shared.transaction {
            let lease = try destination.acquireNamespaceLease(registry: namespaceRegistry)
            do {
                try lease.validate()
                let result = try validate(entries: entries, destination: destination)
                try lease.release()
                return result
            } catch let operationError {
                do { try lease.release() } catch { throw error }
                throw operationError
            }
        }
        try await writeStored(entries: plan, to: destination)
    }

    private func writeStored(
        entries plan: [PlannedEntry],
        to destination: StoredZIPDestinationBinding
    ) async throws {
        let partialName = ".\(destination.fileName).\(UUID().uuidString.lowercased()).partial"
        let stageObserver = stagingObserver
        let metadataObserver = initialMetadataObserver
        let unlinkObserver = unlinkOperationObserver
        let staging: ReportExportFileDescriptor
        do {
            if destination.requiresPrivateInvariant {
                let parentURL = destination.url.deletingLastPathComponent()
                staging = try ReportExportDescriptorIO.createAnonymousFile(
                    in: destination.parentDescriptor.rawValue,
                    parentURL: parentURL,
                    visibleName: partialName,
                    privateParent: true,
                    registry: stageResidueRegistry,
                    afterOpenBeforeMetadata: {
                        try metadataObserver?(parentURL, partialName)
                    },
                    beforeUnlink: {
                        try stageObserver?(parentURL, partialName)
                    },
                    beforeUnlinkOperation: {
                        try unlinkObserver?(parentURL, partialName)
                    }
                )
            } else {
                staging = try FileManagerReportExportTemporaryFileSystem()
                    .createPrivateAnonymousStagingFile(
                        visibleName: partialName,
                        registry: stageResidueRegistry,
                        afterOpenBeforeMetadata: { parent, name in
                            try metadataObserver?(parent, name)
                        },
                        beforeUnlink: { parent, name in
                            try stageObserver?(parent, name)
                        },
                        beforeUnlinkOperation: { parent, name in
                            try unlinkObserver?(parent, name)
                        }
                    )
            }
        } catch {
            throw StoredZIPWriterError.unableToCreatePartial
        }
        try FileManagerReportExportTemporaryFileSystem().applyDescriptorSecurity(to: staging)
        let output = FileHandle(fileDescriptor: staging.rawValue, closeOnDealloc: false)

        do {
            var centralRecords: [CentralRecord] = []
            centralRecords.reserveCapacity(plan.count)
            var offset: UInt64 = 0

            for entry in plan {
                try Task.checkCancellation()
                let localOffset = offset
                let localHeader = Self.localHeader(name: entry.nameBytes)
                try output.write(contentsOf: localHeader)
                offset += UInt64(localHeader.count)

                let source = try Self.openVerifiedSource(entry)
                var accumulator = CRC32.Accumulator()
                var actualSize: UInt64 = 0
                do {
                    while true {
                        try Task.checkCancellation()
                        guard let chunk = try source.read(upToCount: limits.chunkSize),
                              !chunk.isEmpty else { break }
                        let chunkSize = UInt64(chunk.count)
                        if chunkSize > limits.maxEntrySize
                            || actualSize > limits.maxEntrySize - chunkSize {
                            throw StoredZIPWriterError.zip32LimitExceeded(.entrySize)
                        }
                        actualSize += UInt64(chunk.count)
                        accumulator.update(chunk)
                        try output.write(contentsOf: chunk)
                        offset += UInt64(chunk.count)
                        try await chunkObserver?(chunk.count)
                    }
                    try source.close()
                } catch {
                    try? source.close()
                    throw error
                }
                guard actualSize == entry.expectedSize else {
                    throw StoredZIPWriterError.sourceChanged(entry.sourceURL)
                }

                let descriptor = Self.dataDescriptor(
                    crc32: accumulator.checksum,
                    size: UInt32(actualSize)
                )
                try output.write(contentsOf: descriptor)
                offset += UInt64(descriptor.count)
                centralRecords.append(CentralRecord(
                    nameBytes: entry.nameBytes,
                    crc32: accumulator.checksum,
                    size: UInt32(actualSize),
                    localOffset: UInt32(localOffset)
                ))
            }

            try Task.checkCancellation()
            let centralOffset = offset
            for record in centralRecords {
                let bytes = Self.centralHeader(record)
                try output.write(contentsOf: bytes)
                offset += UInt64(bytes.count)
            }
            let centralSize = offset - centralOffset
            let end = Self.endOfCentralDirectory(
                count: UInt16(centralRecords.count),
                centralSize: UInt32(centralSize),
                centralOffset: UInt32(centralOffset)
            )
            try output.write(contentsOf: end)
            try output.synchronize()
            try Task.checkCancellation()
            try await chunkObserver?(0)
            try Task.checkCancellation()
            try ReportExportNamespaceAuthority.shared.transaction {
                let namespaceLease = try destination.acquireNamespaceLease(
                    registry: namespaceRegistry
                )
                do {
                    try namespaceLease.validate()
                    try destination.validate()
                    try namespaceLease.validate()
                    let stageMetadata = try ReportExportDescriptorIO.metadata(
                        for: staging.rawValue
                    )
                    guard stageMetadata.isRegularFile, stageMetadata.linkCount == 0 else {
                        throw StoredZIPWriterError.unableToCreatePartial
                    }
                    do {
                        try ReportExportDescriptorIO.withCreationAllowed(
                            in: destination.parentDescriptor.rawValue
                        ) {
                            try ReportExportDescriptorIO.clone(
                                sourceDescriptor: staging.rawValue,
                                to: destination.fileName,
                                in: destination.parentDescriptor.rawValue
                            )
                        }
                    } catch let error as POSIXError where error.code == .EEXIST {
                        throw StoredZIPWriterError.destinationExists
                    }
                    let publishedMetadata = try ReportExportDescriptorIO.metadata(
                        at: destination.fileName,
                        relativeTo: destination.parentDescriptor.rawValue
                    )
                    do {
                        let published = try ReportExportDescriptorIO.openRegularFile(
                            at: destination.fileName,
                            relativeTo: destination.parentDescriptor.rawValue
                        )
                        guard try ReportExportDescriptorIO.metadata(for: published.rawValue).identity
                                == publishedMetadata.identity else {
                            throw StoredZIPWriterError.unableToCreatePartial
                        }
                        try FileManagerReportExportTemporaryFileSystem()
                            .applyPublishedFileSecurity(
                                to: published,
                                privateInvariant: destination.requiresPrivateInvariant
                            )
                    } catch {
                        try? ReportExportDescriptorIO.removeEntry(
                            destination.fileName,
                            relativeTo: destination.parentDescriptor.rawValue,
                            expectedIdentity: publishedMetadata.identity,
                            flags: 0,
                            requirePrivateInvariant: false
                        )
                        throw error
                    }
                    try namespaceLease.release()
                } catch let operationError {
                    do { try namespaceLease.release() } catch { throw error }
                    throw operationError
                }
            }
        } catch {
            throw error
        }
    }

    private func validate(
        entries: [StoredZIPEntry],
        destination: StoredZIPDestinationBinding
    ) throws -> [PlannedEntry] {
        try destination.validate()
        if try destination.destinationExists() {
            throw StoredZIPWriterError.destinationExists
        }
        guard entries.count <= limits.maxEntryCount else {
            throw StoredZIPWriterError.zip32LimitExceeded(.entryCount)
        }

        let canonicalDestination = destination.url.standardizedFileURL.resolvingSymlinksInPath()
        var names = Set<String>()
        var plan: [PlannedEntry] = []
        plan.reserveCapacity(entries.count)
        for entry in entries {
            try Self.validate(relativePath: entry.relativePath)
            guard names.insert(entry.relativePath).inserted else {
                throw StoredZIPWriterError.duplicateEntry(entry.relativePath)
            }
            let nameBytes = Data(entry.relativePath.utf8)
            guard nameBytes.count <= limits.maxNameLength else {
                throw StoredZIPWriterError.zip32LimitExceeded(.nameLength)
            }

            guard let sourceMetadata = Self.metadata(at: entry.sourceURL) else {
                throw StoredZIPWriterError.invalidSource(entry.sourceURL)
            }
            guard entry.sourceURL.isFileURL,
                  sourceMetadata.isRegularFile,
                  sourceMetadata.size >= 0 else {
                throw StoredZIPWriterError.invalidSource(entry.sourceURL)
            }
            let expectedSize = UInt64(sourceMetadata.size)
            guard expectedSize <= limits.maxEntrySize else {
                throw StoredZIPWriterError.zip32LimitExceeded(.entrySize)
            }
            let canonicalSource = entry.sourceURL.standardizedFileURL.resolvingSymlinksInPath()
            guard canonicalSource != canonicalDestination else {
                throw StoredZIPWriterError.destinationAliasesInput
            }
            plan.append(PlannedEntry(
                relativePath: entry.relativePath,
                nameBytes: nameBytes,
                sourceURL: entry.sourceURL,
                expectedSize: expectedSize,
                expectedIdentity: sourceMetadata.identity
            ))
        }
        plan.sort { Self.utf8OrderedBefore($0.nameBytes, $1.nameBytes) }

        var localOffset: UInt64 = 0
        for entry in plan {
            guard localOffset <= limits.maxOffset else {
                throw StoredZIPWriterError.zip32LimitExceeded(.offset)
            }
            let recordSize = UInt64(30 + entry.nameBytes.count + 16) + entry.expectedSize
            guard localOffset <= limits.maxOffset,
                  recordSize <= limits.maxOffset,
                  localOffset <= limits.maxOffset - recordSize else {
                throw StoredZIPWriterError.zip32LimitExceeded(.offset)
            }
            localOffset += recordSize
        }
        guard localOffset <= limits.maxCentralDirectoryOffset else {
            throw StoredZIPWriterError.zip32LimitExceeded(.centralDirectoryOffset)
        }
        let centralSize = plan.reduce(UInt64(0)) {
            $0 + UInt64(46 + $1.nameBytes.count)
        }
        guard centralSize <= limits.maxCentralDirectorySize else {
            throw StoredZIPWriterError.zip32LimitExceeded(.centralDirectorySize)
        }
        guard localOffset <= UInt64(UInt32.max), centralSize <= UInt64(UInt32.max) else {
            throw StoredZIPWriterError.zip32LimitExceeded(.offset)
        }
        return plan
    }

    private static func validate(relativePath: String) throws {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.contains(":"),
              !relativePath.contains("\0"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw StoredZIPWriterError.unsafeRelativePath(relativePath)
        }
    }

    private static func metadata(at url: URL) -> StoredZIPFileMetadata? {
        guard url.isFileURL else { return nil }
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else { return nil }
        return StoredZIPFileMetadata(status)
    }

    private static func openVerifiedSource(_ entry: PlannedEntry) throws -> FileHandle {
        let descriptor = Darwin.open(
            entry.sourceURL.path,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw StoredZIPWriterError.sourceChanged(entry.sourceURL)
        }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            let error = currentPOSIXError()
            _ = Darwin.close(descriptor)
            throw error
        }
        let metadata = StoredZIPFileMetadata(status)
        guard metadata.isRegularFile,
              metadata.size >= 0,
              UInt64(metadata.size) == entry.expectedSize,
              metadata.identity == entry.expectedIdentity else {
            _ = Darwin.close(descriptor)
            throw StoredZIPWriterError.sourceChanged(entry.sourceURL)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private static func utf8OrderedBefore(_ lhs: Data, _ rhs: Data) -> Bool {
        lhs.lexicographicallyPrecedes(rhs)
    }

    private static func localHeader(name: Data) -> Data {
        var data = Data()
        data.appendLittleEndian(UInt32(0x0403_4b50))
        data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(UInt16(0x0808))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0x0021))
        data.appendLittleEndian(UInt32(0))
        data.appendLittleEndian(UInt32(0))
        data.appendLittleEndian(UInt32(0))
        data.appendLittleEndian(UInt16(name.count))
        data.appendLittleEndian(UInt16(0))
        data.append(name)
        return data
    }

    private static func dataDescriptor(crc32: UInt32, size: UInt32) -> Data {
        var data = Data()
        data.appendLittleEndian(UInt32(0x08074b50))
        data.appendLittleEndian(crc32)
        data.appendLittleEndian(size)
        data.appendLittleEndian(size)
        return data
    }

    private static func centralHeader(_ record: CentralRecord) -> Data {
        var data = Data()
        data.appendLittleEndian(UInt32(0x0201_4b50))
        data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(UInt16(0x0808))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0x0021))
        data.appendLittleEndian(record.crc32)
        data.appendLittleEndian(record.size)
        data.appendLittleEndian(record.size)
        data.appendLittleEndian(UInt16(record.nameBytes.count))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt32(0))
        data.appendLittleEndian(record.localOffset)
        data.append(record.nameBytes)
        return data
    }

    private static func endOfCentralDirectory(
        count: UInt16,
        centralSize: UInt32,
        centralOffset: UInt32
    ) -> Data {
        var data = Data()
        data.appendLittleEndian(UInt32(0x0605_4b50))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(count)
        data.appendLittleEndian(count)
        data.appendLittleEndian(centralSize)
        data.appendLittleEndian(centralOffset)
        data.appendLittleEndian(UInt16(0))
        return data
    }
}

private struct PlannedEntry {
    let relativePath: String
    let nameBytes: Data
    let sourceURL: URL
    let expectedSize: UInt64
    let expectedIdentity: StoredZIPFileIdentity
}

private struct CentralRecord {
    let nameBytes: Data
    let crc32: UInt32
    let size: UInt32
    let localOffset: UInt32
}

private struct StoredZIPFileIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64

    init(_ status: stat) {
        device = UInt64(truncatingIfNeeded: status.st_dev)
        inode = UInt64(truncatingIfNeeded: status.st_ino)
    }
}

private struct StoredZIPFileMetadata: Sendable {
    let identity: StoredZIPFileIdentity
    let mode: mode_t
    let size: off_t

    init(_ status: stat) {
        identity = StoredZIPFileIdentity(status)
        mode = status.st_mode
        size = status.st_size
    }

    var isRegularFile: Bool { mode & S_IFMT == S_IFREG }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
