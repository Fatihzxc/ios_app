import Darwin
import Foundation
@testable import ReportsKit
import XCTest

final class StoredZIPWriterTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoredZIPWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory,
           FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testCRC32IEEEEmptyAndKnownVector() {
        XCTAssertEqual(CRC32.checksum(Data()), 0x0000_0000)
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xcbf4_3926)

        var accumulator = CRC32.Accumulator()
        accumulator.update(Data("1234".utf8))
        accumulator.update(Data("56789".utf8))
        XCTAssertEqual(accumulator.checksum, 0xcbf4_3926)
    }

    func testWritesCanonicalStoredHeadersDescriptorsCentralDirectoryAndSortedUTF8Names() async throws {
        let zed = try source("zed.txt", bytes: Data("z".utf8))
        let turkish = try source("turkish.txt", bytes: Data("ölçüm".utf8))
        let output = temporaryDirectory.appendingPathComponent("canonical.zip")

        try await StoredZIPWriter().writeStored(entries: [
            .init(relativePath: "z/zed.txt", sourceURL: zed),
            .init(relativePath: "a/ölçüm.txt", sourceURL: turkish),
        ], to: output)

        let archive = try Data(contentsOf: output)
        let parsed = try parseArchive(archive)
        XCTAssertEqual(parsed.localNames, ["a/ölçüm.txt", "z/zed.txt"])
        XCTAssertEqual(parsed.centralNames, parsed.localNames)
        XCTAssertEqual(parsed.payloads, [Data("ölçüm".utf8), Data("z".utf8)])
        XCTAssertEqual(parsed.localFlags, [0x0808, 0x0808])
        XCTAssertEqual(parsed.centralFlags, [0x0808, 0x0808])
        XCTAssertEqual(parsed.methods, [0, 0])
        XCTAssertEqual(parsed.times, [0, 0])
        XCTAssertEqual(parsed.dates, [0x0021, 0x0021])
        XCTAssertEqual(parsed.localZeroFields, [true, true])
        XCTAssertEqual(parsed.descriptorSignatures, [0x0807_4b50, 0x0807_4b50])
        XCTAssertEqual(parsed.descriptorCRCs, [0x3b0b_4df9, 0x62d2_77af])
        XCTAssertEqual(parsed.descriptorCompressedSizes, [8, 1])
        XCTAssertEqual(parsed.descriptorUncompressedSizes, [8, 1])
        XCTAssertEqual(parsed.centralMethods, [0, 0])
        XCTAssertEqual(parsed.centralTimes, [0, 0])
        XCTAssertEqual(parsed.centralDates, [0x0021, 0x0021])
        XCTAssertEqual(parsed.centralCRCs, parsed.descriptorCRCs)
        XCTAssertEqual(parsed.centralCompressedSizes, parsed.descriptorCompressedSizes)
        XCTAssertEqual(parsed.centralUncompressedSizes, parsed.descriptorUncompressedSizes)
        XCTAssertEqual(parsed.centralLocalOffsets, [0, 68])
        XCTAssertEqual(parsed.commentLength, 0)
        XCTAssertEqual(parsed.entryCount, 2)
        XCTAssertEqual(parsed.centralDirectoryOffset, 124)
        XCTAssertEqual(parsed.centralDirectorySize, 115)
        XCTAssertEqual(parsed.centralDirectoryOffset, parsed.actualCentralDirectoryOffset)
        XCTAssertEqual(parsed.centralDirectorySize, parsed.actualCentralDirectorySize)
    }

    func testRejectsDuplicateTraversalAbsoluteBackslashColonNULAndMalformedNamesBeforeOutput() async throws {
        let source = try source("input.txt", bytes: Data("x".utf8))
        let invalidNames = [
            "", "/absolute", "leading//empty", "dot/./name", "parent/../name",
            "back\\slash", "C:drive", "colon:name", "nul\0name",
        ]
        for (index, name) in invalidNames.enumerated() {
            let output = temporaryDirectory.appendingPathComponent("invalid-\(index).zip")
            do {
                try await StoredZIPWriter().writeStored(
                    entries: [.init(relativePath: name, sourceURL: source)],
                    to: output
                )
                XCTFail("Expected unsafe path rejection: \(name.debugDescription)")
            } catch let error as StoredZIPWriterError {
                XCTAssertEqual(error, .unsafeRelativePath(name))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(try partialArtifacts(for: output).isEmpty)
        }

        let duplicateOutput = temporaryDirectory.appendingPathComponent("duplicate.zip")
        do {
            try await StoredZIPWriter().writeStored(entries: [
                .init(relativePath: "same.txt", sourceURL: source),
                .init(relativePath: "same.txt", sourceURL: source),
            ], to: duplicateOutput)
            XCTFail("Expected duplicate rejection")
        } catch let error as StoredZIPWriterError {
            XCTAssertEqual(error, .duplicateEntry("same.txt"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicateOutput.path))
    }

    func testRejectsSourceSymlinkDirectoryDestinationSymlinkAndDestinationAliasingInput() async throws {
        let source = try source("regular.txt", bytes: Data("regular".utf8))
        let directorySource = temporaryDirectory.appendingPathComponent("directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directorySource, withIntermediateDirectories: false)
        let sourceSymlink = temporaryDirectory.appendingPathComponent("source-link")
        try FileManager.default.createSymbolicLink(at: sourceSymlink, withDestinationURL: source)

        for (index, invalidSource) in [sourceSymlink, directorySource].enumerated() {
            let output = temporaryDirectory.appendingPathComponent("source-invalid-\(index).zip")
            await assertThrowsStoredZIP(
                entries: [.init(relativePath: "entry.txt", sourceURL: invalidSource)],
                output: output
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }

        let destinationSymlink = temporaryDirectory.appendingPathComponent("destination-link.zip")
        try FileManager.default.createSymbolicLink(at: destinationSymlink, withDestinationURL: source)
        await assertThrowsStoredZIP(
            entries: [.init(relativePath: "entry.txt", sourceURL: source)],
            output: destinationSymlink
        )

        await assertThrowsStoredZIP(
            entries: [.init(relativePath: "entry.txt", sourceURL: source)],
            output: source
        )
        XCTAssertEqual(try Data(contentsOf: source), Data("regular".utf8))
    }

    func testSourceDescriptorRejectsValidationToOpenSymlinkSwap() async throws {
        let first = try source("first.txt", bytes: Data("first".utf8))
        let original = try source("original.txt", bytes: Data("safe".utf8))
        let replacement = try source("replacement.txt", bytes: Data("evil".utf8))
        let parked = temporaryDirectory.appendingPathComponent("parked-original.txt")
        let output = temporaryDirectory.appendingPathComponent("source-swap.zip")
        let swapper = SourcePathSwapper(
            source: original,
            parked: parked,
            replacement: replacement
        )
        let writer = StoredZIPWriter(
            limits: .init(chunkSize: 64),
            chunkObserver: { _ in try swapper.replaceSourceWithSymlinkOnce() }
        )

        do {
            try await writer.writeStored(entries: [
                .init(relativePath: "a-first.txt", sourceURL: first),
                .init(relativePath: "z-original.txt", sourceURL: original),
            ], to: output)
            XCTFail("Expected the descriptor-bound source to reject the post-validation swap")
        } catch let error as StoredZIPWriterError {
            XCTAssertTrue(
                error == .sourceChanged(original) || error == .invalidSource(original),
                "Unexpected source-swap error: \(error)"
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: parked), Data("safe".utf8))
        XCTAssertEqual(try Data(contentsOf: replacement), Data("evil".utf8))
    }

    func testRejectsEveryInjectableZIP32LimitBeforeTruncation() async throws {
        let one = try source("one.bin", bytes: Data([0x01]))
        let two = try source("two.bin", bytes: Data([0x02]))
        let fixtures: [(String, StoredZIPLimits, [StoredZIPEntry])] = [
            ("entry-size", .init(maxEntrySize: 0), [.init(relativePath: "one", sourceURL: one)]),
            ("name-length", .init(maxNameLength: 2), [.init(relativePath: "long", sourceURL: one)]),
            ("entry-count", .init(maxEntryCount: 1), [
                .init(relativePath: "one", sourceURL: one),
                .init(relativePath: "two", sourceURL: two),
            ]),
            ("offset", .init(maxOffset: 20), [.init(relativePath: "one", sourceURL: one)]),
            ("central-size", .init(maxCentralDirectorySize: 1), [.init(relativePath: "one", sourceURL: one)]),
            ("central-offset", .init(maxCentralDirectoryOffset: 20), [.init(relativePath: "one", sourceURL: one)]),
        ]

        for (name, limits, entries) in fixtures {
            let output = temporaryDirectory.appendingPathComponent("limit-\(name).zip")
            do {
                try await StoredZIPWriter(limits: limits).writeStored(entries: entries, to: output)
                XCTFail("Expected limit rejection for \(name)")
            } catch let error as StoredZIPWriterError {
                if case .zip32LimitExceeded = error {
                    // Expected.
                } else {
                    XCTFail("Wrong error for \(name): \(error)")
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testCancellationAndStreamingFailureRemovePartialAndNeverPublishDestination() async throws {
        let source = try source("large.bin", bytes: Data(repeating: 0x5a, count: 33))
        let cancellationOutput = temporaryDirectory.appendingPathComponent("cancelled.zip")
        let cancellingWriter = StoredZIPWriter(
            limits: .init(chunkSize: 4),
            chunkObserver: { _ in throw CancellationError() }
        )

        do {
            try await cancellingWriter.writeStored(
                entries: [.init(relativePath: "large.bin", sourceURL: source)],
                to: cancellationOutput
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancellationOutput.path))
        XCTAssertTrue(try partialArtifacts(for: cancellationOutput).isEmpty)

        let failureOutput = temporaryDirectory.appendingPathComponent("failure.zip")
        let failingWriter = StoredZIPWriter(
            limits: .init(chunkSize: 4),
            chunkObserver: { _ in throw FixtureError.injectedIO }
        )
        do {
            try await failingWriter.writeStored(
                entries: [.init(relativePath: "large.bin", sourceURL: source)],
                to: failureOutput
            )
            XCTFail("Expected injected streaming failure")
        } catch FixtureError.injectedIO {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: failureOutput.path))
        XCTAssertTrue(try partialArtifacts(for: failureOutput).isEmpty)
    }

    func testPartialRemovalFailureRetriesAutomaticallyWithoutAnotherArchive() async throws {
        let lockedDirectory = temporaryDirectory.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(
            at: lockedDirectory,
            withIntermediateDirectories: false
        )
        let source = try self.source("partial-source.bin", bytes: Data(repeating: 0x41, count: 16))
        let failedOutput = lockedDirectory.appendingPathComponent("failed.zip")
        let writer = StoredZIPWriter(
            limits: .init(chunkSize: 4),
            chunkObserver: { _ in
                guard chmod(lockedDirectory.path, S_IRUSR | S_IXUSR) == 0 else {
                    throw FixtureError.permissionChangeFailed
                }
                throw FixtureError.injectedIO
            }
        )

        do {
            try await writer.writeStored(
                entries: [.init(relativePath: "payload.bin", sourceURL: source)],
                to: failedOutput
            )
            XCTFail("Expected injected streaming failure")
        } catch FixtureError.injectedIO {
            // The anonymous staging descriptor closes without a pathname artifact.
        }
        XCTAssertEqual(chmod(lockedDirectory.path, S_IRWXU), 0)
        for _ in 0..<200 where !(try partialArtifacts(for: failedOutput).isEmpty) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(try partialArtifacts(for: failedOutput).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedOutput.path))
    }

    func testStageUnlinkFailureStopsBeforeSensitiveWriteAndAutomaticallyCleansZeroBytePartial() async throws {
        let privateBytes = Data("must-never-reach-a-visible-partial".utf8)
        let source = try self.source("unlink-failure-source.bin", bytes: privateBytes)
        let output = temporaryDirectory.appendingPathComponent("unlink-failure.zip")
        try setUserAppendOnly(true, at: temporaryDirectory)
        defer { try? setUserAppendOnly(false, at: temporaryDirectory) }

        do {
            try await StoredZIPWriter().writeStored(
                entries: [.init(relativePath: "private.bin", sourceURL: source)],
                to: output
            )
            XCTFail("Expected visible-stage unlink failure")
        } catch let error as StoredZIPWriterError {
            XCTAssertEqual(error, .unableToCreatePartial)
        }

        let zeroByteResidue = try partialArtifacts(for: output)
        XCTAssertEqual(zeroByteResidue.count, 1)
        XCTAssertEqual(try zeroByteResidue.map { try Data(contentsOf: $0).count }, [0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))

        try setUserAppendOnly(false, at: temporaryDirectory)
        for _ in 0..<200 where !(try partialArtifacts(for: output).isEmpty) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(try partialArtifacts(for: output).isEmpty)
    }

    func testStageHardLinkBeforeUnlinkFailsBeforeBytesAndCleansExactZeroByteInode() async throws {
        let privateBytes = Data("hard-link-must-never-observe-archive-bytes".utf8)
        let source = try self.source("hard-link-source.bin", bytes: privateBytes)
        let output = temporaryDirectory.appendingPathComponent("hard-link-output.zip")
        let linkedResidue = temporaryDirectory.appendingPathComponent("linked-zero-byte-stage")
        let writer = StoredZIPWriter(stagingObserver: { parent, visibleName in
            let visible = parent.appendingPathComponent(visibleName)
            guard Darwin.link(visible.path, linkedResidue.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        })

        do {
            try await writer.writeStored(
                entries: [.init(relativePath: "private.bin", sourceURL: source)],
                to: output
            )
            XCTFail("Expected linked staging identity rejection")
        } catch let error as StoredZIPWriterError {
            XCTAssertEqual(error, .unableToCreatePartial)
        }

        XCTAssertEqual(try Data(contentsOf: linkedResidue), Data())
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        for _ in 0..<200 where FileManager.default.fileExists(atPath: linkedResidue.path) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkedResidue.path))
    }

    func testStageMoveBetweenOpenAndUnlinkIsRejectedBeforePrivateBytesAreWritten() async throws {
        let sourceBytes = Data("stage-move-private-source".utf8)
        let source = try self.source("stage-move-source.bin", bytes: sourceBytes)
        let output = temporaryDirectory.appendingPathComponent("stage-move-output.zip")
        let parked = temporaryDirectory.appendingPathComponent("stage-move-parked")
        let probe = StageMoveBeforeUnlinkProbe(parked: parked)
        let writer = StoredZIPWriter(stagingObserver: { parent, visibleName in
            probe.attemptMove(parent.appendingPathComponent(visibleName))
        })

        do {
            try await writer.writeStored(
                entries: [.init(relativePath: "private.bin", sourceURL: source)],
                to: output
            )
        } catch let error as StoredZIPWriterError {
            XCTAssertEqual(error, .unableToCreatePartial)
        }

        XCTAssertTrue(probe.wasRejected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: parked.path))
        if FileManager.default.fileExists(atPath: output.path) {
            XCTAssertNotNil(try Data(contentsOf: output).range(of: sourceBytes))
        }
    }

    func testStreamsBoundedChunksAndEquivalentTreesProduceIdenticalBytes() async throws {
        let source = try source("stream.bin", bytes: Data((0..<29).map(UInt8.init)))
        let recorder = ChunkRecorder()
        let writer = StoredZIPWriter(
            limits: .init(chunkSize: 5),
            chunkObserver: { size in await recorder.record(size) }
        )
        let first = temporaryDirectory.appendingPathComponent("first.zip")
        let second = temporaryDirectory.appendingPathComponent("second.zip")

        try await writer.writeStored(
            entries: [.init(relativePath: "stream.bin", sourceURL: source)], to: first
        )
        try await StoredZIPWriter(limits: .init(chunkSize: 3)).writeStored(
            entries: [.init(relativePath: "stream.bin", sourceURL: source)], to: second
        )

        let sizes = await recorder.sizes
        XCTAssertEqual(sizes, [5, 5, 5, 5, 5, 4])
        XCTAssertTrue(sizes.allSatisfy { $0 <= 5 })
        XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: second))
    }

    func testNeverOverwritesExistingDestination() async throws {
        let source = try source("source.txt", bytes: Data("new".utf8))
        let output = try self.source("existing.zip", bytes: Data("old".utf8))

        do {
            try await StoredZIPWriter().writeStored(
                entries: [.init(relativePath: "source.txt", sourceURL: source)], to: output
            )
            XCTFail("Expected existing destination rejection")
        } catch let error as StoredZIPWriterError {
            XCTAssertEqual(error, .destinationExists)
        }

        XCTAssertEqual(try Data(contentsOf: output), Data("old".utf8))
        XCTAssertTrue(try partialArtifacts(for: output).isEmpty)
    }

    func testAtomicNoReplacePublicationPreservesDestinationCreatedAtPublishBoundary() async throws {
        let source = try self.source("race-source.txt", bytes: Data("archive".utf8))
        let output = temporaryDirectory.appendingPathComponent("publication-race.zip")
        let competingBytes = Data("concurrent-winner".utf8)
        let writer = StoredZIPWriter(
            chunkObserver: { observedChunkSize in
                guard observedChunkSize == 0 else { return }
                try competingBytes.write(to: output, options: .withoutOverwriting)
            }
        )

        do {
            try await writer.writeStored(
                entries: [.init(relativePath: "payload.txt", sourceURL: source)],
                to: output
            )
            XCTFail("Expected the atomic no-replace publication to lose the injected race")
        } catch let error as StoredZIPWriterError {
            XCTAssertEqual(error, .destinationExists)
        }

        XCTAssertEqual(try Data(contentsOf: output), competingBytes)
        XCTAssertTrue(
            try partialArtifacts(for: output).isEmpty
        )
    }

    func testPublicationNeverUsesReplacementStagingPathBytes() async throws {
        let safeBytes = Data("descriptor-bound-safe-payload".utf8)
        let attackerBytes = Data("attacker-staging-bytes".utf8)
        let source = try self.source("staging-race-source.txt", bytes: safeBytes)
        let output = temporaryDirectory.appendingPathComponent("staging-race.zip")
        let race = StagingNameReplacementRace(
            directory: temporaryDirectory,
            output: output,
            attackerBytes: attackerBytes
        )
        let writer = StoredZIPWriter(
            chunkObserver: { observedChunkSize in
                guard observedChunkSize == 0 else { return }
                try race.replaceDiscoverableStagingName()
            }
        )

        do {
            try await writer.writeStored(
                entries: [.init(relativePath: "payload.txt", sourceURL: source)],
                to: output
            )
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }

        let publishedBytes = try? Data(contentsOf: output)
        XCTAssertNotEqual(publishedBytes, Optional(attackerBytes))
        XCTAssertFalse(publishedBytes?.range(of: attackerBytes) != nil)
        XCTAssertTrue(publishedBytes == nil || publishedBytes?.range(of: safeBytes) != nil)
        XCTAssertTrue(race.didAttemptReplacement)
        XCTAssertFalse(race.didReplace)
        XCTAssertNil(race.replacementData)
        XCTAssertTrue(try partialArtifacts(for: output).isEmpty)
    }

    func testPublicationNeverFollowsDestinationParentSwapOutsideHeldDirectory() async throws {
        let sourceBytes = Data("held-parent-safe-payload".utf8)
        let attackerBytes = Data("attacker-parent-bytes".utf8)
        let source = try self.source("parent-race-source.txt", bytes: sourceBytes)
        let parent = temporaryDirectory.appendingPathComponent("publication-parent", isDirectory: true)
        let parkedParent = temporaryDirectory.appendingPathComponent("publication-parent-parked", isDirectory: true)
        let externalParent = temporaryDirectory.appendingPathComponent("publication-parent-external", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: false)
        try Data("external-sentinel".utf8).write(
            to: externalParent.appendingPathComponent("sentinel"),
            options: .withoutOverwriting
        )
        let output = parent.appendingPathComponent("parent-race.zip")
        let race = DestinationParentReplacementRace(
            parent: parent,
            parkedParent: parkedParent,
            externalParent: externalParent,
            output: output,
            attackerBytes: attackerBytes
        )
        let writer = StoredZIPWriter(
            chunkObserver: { observedChunkSize in
                guard observedChunkSize == 0 else { return }
                try race.swapParentAtPublicationBoundary()
            }
        )

        do {
            try await writer.writeStored(
                entries: [.init(relativePath: "payload.txt", sourceURL: source)],
                to: output
            )
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: externalParent.appendingPathComponent(output.lastPathComponent).path
            ))
        }

        let externalOutput = externalParent.appendingPathComponent(output.lastPathComponent)
        XCTAssertTrue(race.didSwapParent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: externalOutput.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: parkedParent.appendingPathComponent(output.lastPathComponent).path
        ))
        XCTAssertEqual(
            try Data(contentsOf: externalParent.appendingPathComponent("sentinel")),
            Data("external-sentinel".utf8)
        )
        XCTAssertTrue(!race.didCreateReplacement || race.replacementData == attackerBytes)
    }

    func testPublicationDoesNotExposeBytesWhenParentMovesAfterFinalValidationBeforeClone() async throws {
        let sourceBytes = Data("post-validation-private-archive-bytes".utf8)
        let source = try self.source("post-validation-source.txt", bytes: sourceBytes)
        let parent = temporaryDirectory.appendingPathComponent(
            "post-validation-parent",
            isDirectory: true
        )
        let parkedParent = temporaryDirectory.appendingPathComponent(
            "post-validation-parent-parked",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let output = parent.appendingPathComponent("post-validation.zip")
        let entry = try ReportExportDescriptorIO.makeEntry(at: parent, createIfMissing: false)
        let race = PostValidationParentMove(
            parent: parent,
            parkedParent: parkedParent,
            outputName: output.lastPathComponent
        )
        let binding = StoredZIPDestinationBinding(
            url: output,
            fileName: output.lastPathComponent,
            parentDescriptor: entry.descriptor,
            validate: {
                try entry.validate()
                race.afterSuccessfulValidation()
            }
        )

        try await StoredZIPWriter().writeStored(
            entries: [.init(relativePath: "private.txt", sourceURL: source)],
            to: binding
        )

        XCTAssertTrue(race.didAttemptMove)
        XCTAssertFalse(race.didMove)
        XCTAssertFalse(FileManager.default.fileExists(atPath: race.parkedOutput.path))
        let published = try Data(contentsOf: output)
        XCTAssertNotNil(published.range(of: sourceBytes))
    }

    func testPublicationCreateWindowKeepsParentAppendOnlyThroughDescriptorClone() throws {
        let parent = temporaryDirectory.appendingPathComponent(
            "append-only-publication-parent",
            isDirectory: true
        )
        let parked = temporaryDirectory.appendingPathComponent(
            "append-only-publication-parent-parked",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        XCTAssertEqual(Darwin.chmod(parent.path, S_IRWXU | S_IRGRP | S_IXGRP), 0)
        let sourceBytes = Data("descriptor-clone-private-bytes".utf8)
        let source = try self.source("append-only-clone-source", bytes: sourceBytes)
        let sourceValue = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        let sourceDescriptor = ReportExportFileDescriptor(taking: try XCTUnwrap(
            sourceValue >= 0 ? sourceValue : nil
        ))
        let entry = try ReportExportDescriptorIO.makeEntry(at: parent, createIfMissing: false)
        let originalMetadata = try ReportExportDescriptorIO.metadata(
            for: entry.descriptor.rawValue
        )
        let lease = try ReportExportVisibleDirectoryLease(descriptor: entry.descriptor)
        defer {
            try? lease.release()
            if FileManager.default.fileExists(atPath: parked.path),
               !FileManager.default.fileExists(atPath: parent.path) {
                try? FileManager.default.moveItem(at: parked, to: parent)
            }
        }
        var observedAppendOnly = false
        var didMoveParent = false

        try ReportExportNamespaceAuthority.shared.transaction {
            try ReportExportDescriptorIO.withRemovalAllowed(in: entry.descriptor.rawValue) {
                let metadata = try ReportExportDescriptorIO.metadata(
                    for: entry.descriptor.rawValue
                )
                observedAppendOnly = metadata.flags & UInt32(UF_APPEND) != 0
                do {
                    try FileManager.default.moveItem(at: parent, to: parked)
                    didMoveParent = true
                    try FileManager.default.moveItem(at: parked, to: parent)
                } catch {
                    // The append-only creation lease must reject the move.
                }
                try ReportExportDescriptorIO.clone(
                    sourceDescriptor: sourceDescriptor.rawValue,
                    to: "published.zip",
                    in: entry.descriptor.rawValue
                )
            }
        }
        try lease.release()
        let restoredMetadata = try ReportExportDescriptorIO.metadata(
            for: entry.descriptor.rawValue
        )

        XCTAssertTrue(observedAppendOnly)
        XCTAssertFalse(didMoveParent)
        XCTAssertEqual(restoredMetadata.permissionMode, originalMetadata.permissionMode)
        XCTAssertEqual(restoredMetadata.flags, originalMetadata.flags)
        XCTAssertEqual(
            try Data(contentsOf: parent.appendingPathComponent("published.zip")),
            sourceBytes
        )
    }

    func testPostOpenMetadataFailureRetainsAndCleansExactZeroByteStage() async throws {
        let source = try self.source(
            "post-open-metadata-source.bin",
            bytes: Data("must-not-reach-stage".utf8)
        )
        let output = temporaryDirectory.appendingPathComponent("post-open-metadata.zip")
        let location = StageLocationProbe()
        let writer = StoredZIPWriter(initialMetadataObserver: { parent, name in
            try location.record(parent: parent, visibleName: name)
            throw FixtureError.injectedIO
        })

        do {
            try await writer.writeStored(
                entries: [.init(relativePath: "payload.bin", sourceURL: source)],
                to: output
            )
            XCTFail("Expected injected post-open metadata failure")
        } catch let error as StoredZIPWriterError {
            XCTAssertEqual(error, .unableToCreatePartial)
        }
        let snapshot = try XCTUnwrap(location.snapshot)
        let destinationParent = output.deletingLastPathComponent().standardizedFileURL
            .resolvingSymlinksInPath()
        let canonicalTemporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
        let canonicalStageParent = snapshot.parent.standardizedFileURL
            .resolvingSymlinksInPath()
        XCTAssertNotEqual(canonicalStageParent, destinationParent)
        XCTAssertTrue(
            canonicalStageParent.path.hasPrefix(canonicalTemporaryRoot.path + "/")
        )
        XCTAssertTrue(snapshot.parentWasPrivateAndAppendOnly)
        XCTAssertEqual(snapshot.stageSize, 0)

        for _ in 0..<200 where FileManager.default.fileExists(
            atPath: snapshot.parent.path
        ) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.parent.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testTerminalStageRecoveryNeverDeletesASecondNameForRetainedInode() async throws {
        let parent = temporaryDirectory.appendingPathComponent(
            "terminal-stage-private-parent",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let entry = try ReportExportDescriptorIO.makeEntry(at: parent, createIfMissing: false)
        let namespaceLease = try ReportExportVisibleDirectoryLease(
            descriptor: entry.descriptor
        )
        let scheduler = ZIPManualCleanupScheduler()
        let registry = ReportExportStageResidueRegistry(scheduler: scheduler)
        let visibleName = ".terminal-stage.00000000-0000-4000-8000-000000000001.partial"
        let visibleStage = parent.appendingPathComponent(visibleName)
        let secondName = temporaryDirectory.appendingPathComponent(
            "non-owned-second-name"
        )
        defer {
            try? namespaceLease.release()
            try? FileManager.default.removeItem(at: secondName)
            try? FileManager.default.removeItem(at: parent)
        }

        XCTAssertThrowsError(
            try ReportExportDescriptorIO.createAnonymousFile(
                in: entry.descriptor.rawValue,
                parentURL: parent,
                visibleName: visibleName,
                privateParent: true,
                registry: registry,
                beforeUnlink: {
                    try createHardLink(from: visibleStage, to: secondName)
                }
            )
        )
        XCTAssertEqual(try Data(contentsOf: secondName).count, 0)

        for _ in 0..<8 {
            await scheduler.runNextBatch()
        }
        XCTAssertEqual(registry.retainedCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: visibleStage.path))

        let replacement = Data("replacement-name-must-survive".utf8)
        try ReportExportNamespaceAuthority.shared.transaction {
            try ReportExportDescriptorIO.withRemovalAllowed(
                in: entry.descriptor.rawValue
            ) {
                try replacement.write(to: visibleStage, options: .withoutOverwriting)
            }
        }
        let trigger = try registry.reserve()
        registry.release(trigger)
        XCTAssertEqual(try Data(contentsOf: visibleStage), replacement)
        XCTAssertEqual(try Data(contentsOf: secondName).count, 0)
        XCTAssertEqual(registry.retainedCount, 1)

        try FileManager.default.removeItem(at: secondName)
        let finalTrigger = try registry.reserve()
        registry.release(finalTrigger)
        await scheduler.runNextBatch()
        XCTAssertEqual(registry.retainedCount, 0)
        XCTAssertEqual(try Data(contentsOf: visibleStage), replacement)
    }

    func testStandaloneRestoreFailureRetainsExactDescriptorUntilTransientRetry() async throws {
        let parent = temporaryDirectory.appendingPathComponent(
            "transient-restore-parent",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        XCTAssertEqual(Darwin.chmod(parent.path, S_IRWXU | S_IRGRP | S_IXGRP), 0)
        let entry = try ReportExportDescriptorIO.makeEntry(at: parent, createIfMissing: false)
        let original = try ReportExportDescriptorIO.metadata(for: entry.descriptor.rawValue)
        let scheduler = ZIPManualCleanupScheduler()
        let gate = RestoreFailureGate(failingAttempt: 2)
        let registry = ReportExportVisibleDirectoryRegistry(
            scheduler: scheduler,
            beforeRestore: { try gate.check() }
        )
        let sourceBytes = Data("transient-restore-private-bytes".utf8)
        let source = try self.source("transient-restore-source", bytes: sourceBytes)
        let output = parent.appendingPathComponent("transient-restore.zip")
        let writer = StoredZIPWriter(
            initialMetadataObserver: { _, _ in },
            namespaceRegistry: registry
        )

        do {
            try await writer.writeStored(
                entries: [.init(relativePath: "payload.txt", sourceURL: source)],
                to: output
            )
            XCTFail("Expected the second namespace restoration to fail")
        } catch FixtureError.injectedIO {
            // The exact descriptor remains owned by the bounded restore registry.
        }
        let retained = try ReportExportDescriptorIO.metadata(for: entry.descriptor.rawValue)
        XCTAssertEqual(registry.retainedCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(retained.permissionMode, original.permissionMode)
        XCTAssertTrue(retained.hasNoUnlink)

        gate.allowAll()
        for _ in 0..<8 where registry.retainedCount > 0 {
            await scheduler.runNextBatch()
        }
        let restored = try ReportExportDescriptorIO.metadata(for: entry.descriptor.rawValue)
        XCTAssertEqual(registry.retainedCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(restored.permissionMode, original.permissionMode)
        XCTAssertEqual(restored.flags, original.flags)
        XCTAssertNotNil(try Data(contentsOf: output).range(of: sourceBytes))
    }

    func testStandaloneRestoreCapacityRejectsBeforeSixtyFifthDirectoryMutation() async throws {
        let scheduler = ZIPManualCleanupScheduler()
        let gate = RestoreFailureGate(failingAttempt: 1, failsPermanently: true)
        let registry = ReportExportVisibleDirectoryRegistry(
            scheduler: scheduler,
            maximumEntries: 64,
            beforeRestore: { try gate.check() }
        )
        let directories = (0..<65).map { index in
            temporaryDirectory.appendingPathComponent(
                "permanent-restore-\(index)",
                isDirectory: true
            )
        }
        defer {
            for directory in directories {
                _ = Darwin.chflags(directory.path, 0)
                _ = Darwin.chmod(directory.path, S_IRWXU)
                try? FileManager.default.removeItem(at: directory)
            }
        }

        for directory in directories.prefix(64) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false
            )
            XCTAssertEqual(
                Darwin.chmod(directory.path, S_IRWXU | S_IRGRP | S_IXGRP),
                0
            )
            let entry = try ReportExportDescriptorIO.makeEntry(
                at: directory,
                createIfMissing: false
            )
            let lease = try ReportExportVisibleDirectoryLease(
                descriptor: entry.descriptor,
                restorationRegistry: registry
            )
            try? lease.release()
        }
        for _ in 0..<8 {
            await scheduler.runNextBatch()
        }
        XCTAssertEqual(registry.retainedCount, 64)
        XCTAssertEqual(scheduler.pendingCount, 0)

        let finalDirectory = try XCTUnwrap(directories.last)
        try FileManager.default.createDirectory(
            at: finalDirectory,
            withIntermediateDirectories: false
        )
        XCTAssertEqual(
            Darwin.chmod(finalDirectory.path, S_IRWXU | S_IRGRP | S_IXGRP),
            0
        )
        let finalEntry = try ReportExportDescriptorIO.makeEntry(
            at: finalDirectory,
            createIfMissing: false
        )
        let before = try ReportExportDescriptorIO.metadata(for: finalEntry.descriptor.rawValue)
        XCTAssertThrowsError(
            try ReportExportVisibleDirectoryLease(
                descriptor: finalEntry.descriptor,
                restorationRegistry: registry
            )
        )
        let after = try ReportExportDescriptorIO.metadata(for: finalEntry.descriptor.rawValue)
        XCTAssertEqual(after.permissionMode, before.permissionMode)
        XCTAssertEqual(after.flags, before.flags)
    }

    private func source(_ name: String, bytes: Data) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try bytes.write(to: url, options: .withoutOverwriting)
        return url
    }

    private func partialArtifacts(for output: URL) throws -> [URL] {
        let prefix = ".\(output.lastPathComponent)."
        return try FileManager.default.contentsOfDirectory(
            at: output.deletingLastPathComponent(),
            includingPropertiesForKeys: [.isRegularFileKey]
        ).filter { candidate in
            let name = candidate.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(".partial") else { return false }
            let identifierStart = name.index(name.startIndex, offsetBy: prefix.count)
            let identifierEnd = name.index(name.endIndex, offsetBy: -".partial".count)
            return UUID(uuidString: String(name[identifierStart..<identifierEnd])) != nil
        }
    }

    private func setUserAppendOnly(_ enabled: Bool, at url: URL) throws {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let flags = enabled
            ? status.st_flags | UInt32(UF_APPEND)
            : status.st_flags & ~UInt32(UF_APPEND)
        guard Darwin.chflags(url.path, flags) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func assertThrowsStoredZIP(entries: [StoredZIPEntry], output: URL) async {
        do {
            try await StoredZIPWriter().writeStored(entries: entries, to: output)
            XCTFail("Expected StoredZIPWriterError")
        } catch is StoredZIPWriterError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func parseArchive(_ data: Data) throws -> ParsedArchive {
        var cursor = 0
        var localNames: [String] = []
        var payloads: [Data] = []
        var localFlags: [UInt16] = []
        var methods: [UInt16] = []
        var times: [UInt16] = []
        var dates: [UInt16] = []
        var localZeroFields: [Bool] = []
        var descriptorSignatures: [UInt32] = []
        var descriptorCRCs: [UInt32] = []
        var descriptorCompressedSizes: [UInt32] = []
        var descriptorUncompressedSizes: [UInt32] = []
        while try uint32(data, cursor) == 0x0403_4b50 {
            let flags = try uint16(data, cursor + 6)
            let method = try uint16(data, cursor + 8)
            let time = try uint16(data, cursor + 10)
            let date = try uint16(data, cursor + 12)
            let nameLength = Int(try uint16(data, cursor + 26))
            let extraLength = Int(try uint16(data, cursor + 28))
            let nameStart = cursor + 30
            let nameData = try slice(data, nameStart, nameLength)
            let name = try XCTUnwrap(String(data: nameData, encoding: .utf8))
            let expectedPayloadSize: Int
            switch name {
            case "a/ölçüm.txt": expectedPayloadSize = Data("ölçüm".utf8).count
            case "z/zed.txt": expectedPayloadSize = 1
            default: throw FixtureError.malformedArchive
            }
            let payloadStart = nameStart + nameLength + extraLength
            let descriptorStart = payloadStart + expectedPayloadSize
            localNames.append(name)
            payloads.append(try slice(data, payloadStart, expectedPayloadSize))
            localFlags.append(flags)
            methods.append(method)
            times.append(time)
            dates.append(date)
            localZeroFields.append(
                try uint32(data, cursor + 14) == 0
                    && uint32(data, cursor + 18) == 0
                    && uint32(data, cursor + 22) == 0
            )
            descriptorSignatures.append(try uint32(data, descriptorStart))
            descriptorCRCs.append(try uint32(data, descriptorStart + 4))
            descriptorCompressedSizes.append(try uint32(data, descriptorStart + 8))
            descriptorUncompressedSizes.append(try uint32(data, descriptorStart + 12))
            cursor = descriptorStart + 16
        }

        let actualCentralDirectoryOffset = cursor
        var centralNames: [String] = []
        var centralFlags: [UInt16] = []
        var centralMethods: [UInt16] = []
        var centralTimes: [UInt16] = []
        var centralDates: [UInt16] = []
        var centralCRCs: [UInt32] = []
        var centralCompressedSizes: [UInt32] = []
        var centralUncompressedSizes: [UInt32] = []
        var centralLocalOffsets: [UInt32] = []
        while try uint32(data, cursor) == 0x0201_4b50 {
            let nameLength = Int(try uint16(data, cursor + 28))
            let extraLength = Int(try uint16(data, cursor + 30))
            let commentLength = Int(try uint16(data, cursor + 32))
            centralFlags.append(try uint16(data, cursor + 8))
            centralMethods.append(try uint16(data, cursor + 10))
            centralTimes.append(try uint16(data, cursor + 12))
            centralDates.append(try uint16(data, cursor + 14))
            centralCRCs.append(try uint32(data, cursor + 16))
            centralCompressedSizes.append(try uint32(data, cursor + 20))
            centralUncompressedSizes.append(try uint32(data, cursor + 24))
            centralLocalOffsets.append(try uint32(data, cursor + 42))
            let nameData = try slice(data, cursor + 46, nameLength)
            centralNames.append(try XCTUnwrap(String(data: nameData, encoding: .utf8)))
            cursor += 46 + nameLength + extraLength + commentLength
        }

        guard try uint32(data, cursor) == 0x0605_4b50 else {
            throw FixtureError.malformedArchive
        }
        return ParsedArchive(
            localNames: localNames,
            centralNames: centralNames,
            payloads: payloads,
            localFlags: localFlags,
            centralFlags: centralFlags,
            methods: methods,
            times: times,
            dates: dates,
            localZeroFields: localZeroFields,
            descriptorSignatures: descriptorSignatures,
            descriptorCRCs: descriptorCRCs,
            descriptorCompressedSizes: descriptorCompressedSizes,
            descriptorUncompressedSizes: descriptorUncompressedSizes,
            centralMethods: centralMethods,
            centralTimes: centralTimes,
            centralDates: centralDates,
            centralCRCs: centralCRCs,
            centralCompressedSizes: centralCompressedSizes,
            centralUncompressedSizes: centralUncompressedSizes,
            centralLocalOffsets: centralLocalOffsets,
            entryCount: Int(try uint16(data, cursor + 10)),
            commentLength: Int(try uint16(data, cursor + 20)),
            centralDirectorySize: try uint32(data, cursor + 12),
            centralDirectoryOffset: try uint32(data, cursor + 16),
            actualCentralDirectorySize: UInt32(cursor - actualCentralDirectoryOffset),
            actualCentralDirectoryOffset: UInt32(actualCentralDirectoryOffset)
        )
    }

    private func uint16(_ data: Data, _ offset: Int) throws -> UInt16 {
        let bytes = try slice(data, offset, 2)
        return UInt16(bytes[bytes.startIndex])
            | UInt16(bytes[bytes.index(after: bytes.startIndex)]) << 8
    }

    private func uint32(_ data: Data, _ offset: Int) throws -> UInt32 {
        let bytes = try slice(data, offset, 4)
        return bytes.enumerated().reduce(0) { partial, pair in
            partial | UInt32(pair.element) << UInt32(pair.offset * 8)
        }
    }

    private func slice(_ data: Data, _ offset: Int, _ count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset + count <= data.count else {
            throw FixtureError.malformedArchive
        }
        return data.subdata(in: offset..<(offset + count))
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}

private func createHardLink(from source: URL, to destination: URL) throws {
    guard Darwin.link(source.path, destination.path) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private final class StageLocationProbe: @unchecked Sendable {
    struct Snapshot: Sendable {
        let parent: URL
        let stageSize: Int64
        let parentWasPrivateAndAppendOnly: Bool
    }

    private let lock = NSLock()
    private var storedSnapshot: Snapshot?

    var snapshot: Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshot
    }

    func record(parent: URL, visibleName: String) throws {
        var parentStatus = stat()
        var stageStatus = stat()
        let stage = parent.appendingPathComponent(visibleName)
        guard Darwin.lstat(parent.path, &parentStatus) == 0,
              Darwin.lstat(stage.path, &stageStatus) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let permissionMode = parentStatus.st_mode & mode_t(0o777)
        let value = Snapshot(
            parent: parent,
            stageSize: Int64(stageStatus.st_size),
            parentWasPrivateAndAppendOnly: parentStatus.st_uid == Darwin.geteuid()
                && permissionMode == S_IRWXU
                && parentStatus.st_flags & UInt32(UF_APPEND) != 0
        )
        lock.lock()
        storedSnapshot = value
        lock.unlock()
    }
}

private final class RestoreFailureGate: @unchecked Sendable {
    private let lock = NSLock()
    private let failingAttempt: Int
    private let failsPermanently: Bool
    private var attemptCount = 0
    private var allowsAll = false

    init(failingAttempt: Int, failsPermanently: Bool = false) {
        self.failingAttempt = failingAttempt
        self.failsPermanently = failsPermanently
    }

    func check() throws {
        lock.lock()
        attemptCount += 1
        let shouldFail = !allowsAll && (failsPermanently
            ? attemptCount >= failingAttempt
            : attemptCount == failingAttempt)
        lock.unlock()
        if shouldFail { throw FixtureError.injectedIO }
    }

    func allowAll() {
        lock.lock()
        allowsAll = true
        lock.unlock()
    }
}

private final class ZIPManualCleanupScheduler:
    ReportExportCleanupScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [@Sendable () -> Void] = []

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return operations.count
    }

    func schedule(
        afterNanoseconds: UInt64,
        operation: @escaping @Sendable () -> Void
    ) {
        _ = afterNanoseconds
        lock.lock()
        operations.append(operation)
        lock.unlock()
    }

    func runNextBatch() async {
        let queued = takeOperations()
        queued.forEach { $0() }
        await Task.yield()
    }

    private func takeOperations() -> [@Sendable () -> Void] {
        lock.lock()
        let queued = operations
        operations.removeAll()
        lock.unlock()
        return queued
    }
}

private actor ChunkRecorder {
    private(set) var sizes: [Int] = []
    func record(_ size: Int) {
        guard size > 0 else { return }
        sizes.append(size)
    }
}

private final class SourcePathSwapper: @unchecked Sendable {
    private let lock = NSLock()
    private let source: URL
    private let parked: URL
    private let replacement: URL
    private var didSwap = false

    init(source: URL, parked: URL, replacement: URL) {
        self.source = source
        self.parked = parked
        self.replacement = replacement
    }

    func replaceSourceWithSymlinkOnce() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !didSwap else { return }
        didSwap = true
        try FileManager.default.moveItem(at: source, to: parked)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: replacement)
    }
}

private final class StagingNameReplacementRace: @unchecked Sendable {
    private let lock = NSLock()
    private let directory: URL
    private let output: URL
    private let attackerBytes: Data
    private var replacementURL: URL?
    private var attemptedReplacement = false

    init(directory: URL, output: URL, attackerBytes: Data) {
        self.directory = directory
        self.output = output
        self.attackerBytes = attackerBytes
    }

    var didReplace: Bool {
        lock.lock()
        defer { lock.unlock() }
        return replacementURL != nil
    }

    var didAttemptReplacement: Bool {
        lock.lock()
        defer { lock.unlock() }
        return attemptedReplacement
    }

    var replacementData: Data? {
        lock.lock()
        defer { lock.unlock() }
        return replacementURL.flatMap { try? Data(contentsOf: $0) }
    }

    func replaceDiscoverableStagingName() throws {
        lock.lock()
        defer { lock.unlock() }
        guard replacementURL == nil else { return }
        attemptedReplacement = true
        let prefix = ".\(output.lastPathComponent)."
        let candidates = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ).filter {
            let name = $0.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(".partial") else { return false }
            let start = name.index(name.startIndex, offsetBy: prefix.count)
            let end = name.index(name.endIndex, offsetBy: -".partial".count)
            return UUID(uuidString: String(name[start..<end])) != nil
        }
        guard let staging = candidates.first else { return }
        let parked = directory.appendingPathComponent("parked-\(staging.lastPathComponent)")
        try FileManager.default.moveItem(at: staging, to: parked)
        try attackerBytes.write(to: staging, options: .withoutOverwriting)
        replacementURL = staging
    }
}

private final class StageMoveBeforeUnlinkProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let parked: URL
    private var rejected = false

    init(parked: URL) { self.parked = parked }

    var wasRejected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rejected
    }

    func attemptMove(_ visibleStage: URL) {
        do {
            try FileManager.default.moveItem(at: visibleStage, to: parked)
        } catch {
            lock.lock()
            rejected = true
            lock.unlock()
        }
    }
}

private final class DestinationParentReplacementRace: @unchecked Sendable {
    private let lock = NSLock()
    private let parent: URL
    private let parkedParent: URL
    private let externalParent: URL
    private let output: URL
    private let attackerBytes: Data
    private var replacementURL: URL?
    private var didSwap = false

    init(
        parent: URL,
        parkedParent: URL,
        externalParent: URL,
        output: URL,
        attackerBytes: Data
    ) {
        self.parent = parent
        self.parkedParent = parkedParent
        self.externalParent = externalParent
        self.output = output
        self.attackerBytes = attackerBytes
    }

    var didCreateReplacement: Bool {
        lock.lock()
        defer { lock.unlock() }
        return replacementURL != nil
    }

    var didSwapParent: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didSwap
    }

    var replacementData: Data? {
        lock.lock()
        defer { lock.unlock() }
        return replacementURL.flatMap { try? Data(contentsOf: $0) }
    }

    func swapParentAtPublicationBoundary() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !didSwap else { return }
        didSwap = true
        let prefix = ".\(output.lastPathComponent)."
        let stagingName = try FileManager.default.contentsOfDirectory(atPath: parent.path)
            .first { name in
                guard name.hasPrefix(prefix), name.hasSuffix(".partial") else { return false }
                let start = name.index(name.startIndex, offsetBy: prefix.count)
                let end = name.index(name.endIndex, offsetBy: -".partial".count)
                return UUID(uuidString: String(name[start..<end])) != nil
            }
        try FileManager.default.moveItem(at: parent, to: parkedParent)
        if let stagingName {
            let replacement = externalParent.appendingPathComponent(stagingName)
            try attackerBytes.write(to: replacement, options: .withoutOverwriting)
            replacementURL = replacement
        }
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: externalParent)
    }
}

private final class PostValidationParentMove: @unchecked Sendable {
    private let lock = NSLock()
    private let parent: URL
    private let parkedParent: URL
    private let outputName: String
    private var validationCount = 0
    private var attemptedMove = false
    private var moved = false

    init(parent: URL, parkedParent: URL, outputName: String) {
        self.parent = parent
        self.parkedParent = parkedParent
        self.outputName = outputName
    }

    var didAttemptMove: Bool {
        lock.lock()
        defer { lock.unlock() }
        return attemptedMove
    }

    var didMove: Bool {
        lock.lock()
        defer { lock.unlock() }
        return moved
    }

    var parkedOutput: URL { parkedParent.appendingPathComponent(outputName) }
    var replacementOutput: URL { parent.appendingPathComponent(outputName) }

    func afterSuccessfulValidation() {
        lock.lock()
        validationCount += 1
        let shouldMove = validationCount == 2
        if shouldMove { attemptedMove = true }
        lock.unlock()
        guard shouldMove else { return }
        do {
            try FileManager.default.moveItem(at: parent, to: parkedParent)
            lock.lock()
            moved = true
            lock.unlock()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: false
            )
        } catch {
            // A live private-namespace lease is expected to reject the move.
        }
    }
}

private struct ParsedArchive {
    let localNames: [String]
    let centralNames: [String]
    let payloads: [Data]
    let localFlags: [UInt16]
    let centralFlags: [UInt16]
    let methods: [UInt16]
    let times: [UInt16]
    let dates: [UInt16]
    let localZeroFields: [Bool]
    let descriptorSignatures: [UInt32]
    let descriptorCRCs: [UInt32]
    let descriptorCompressedSizes: [UInt32]
    let descriptorUncompressedSizes: [UInt32]
    let centralMethods: [UInt16]
    let centralTimes: [UInt16]
    let centralDates: [UInt16]
    let centralCRCs: [UInt32]
    let centralCompressedSizes: [UInt32]
    let centralUncompressedSizes: [UInt32]
    let centralLocalOffsets: [UInt32]
    let entryCount: Int
    let commentLength: Int
    let centralDirectorySize: UInt32
    let centralDirectoryOffset: UInt32
    let actualCentralDirectorySize: UInt32
    let actualCentralDirectoryOffset: UInt32
}

private enum FixtureError: Error {
    case malformedArchive
    case injectedIO
    case permissionChangeFailed
}
