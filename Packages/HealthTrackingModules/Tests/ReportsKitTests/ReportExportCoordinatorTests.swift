import CryptoKit
import Darwin
import Foundation
@testable import ReportsKit
import XCTest

@MainActor
final class ReportExportCoordinatorTests: XCTestCase {
    nonisolated(unsafe) private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReportExportCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory,
           FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testRejectsInvalidRequestsBeforeAllocationOrFetchAndFetchesOneExactSnapshot() async throws {
        let snapshot = try emptySnapshot(modules: [.metrics])
        let repository = ExportRepositorySpy(snapshot: snapshot)
        let store = ExportTemporaryStoreSpy(root: temporaryDirectory)
        let coordinator = ReportExportCoordinator(
            repository: repository,
            photoProvider: ExportPhotoProviderSpy(),
            temporaryStore: store
        )
        let invalidInterval = ReportDateInterval(
            start: Date(timeIntervalSince1970: 100),
            endExclusive: Date(timeIntervalSince1970: 100)
        )

        await assertGenerationError(
            coordinator,
            request: .init(interval: invalidInterval, modules: [.metrics], format: .json, includesPhotos: false),
            expected: .invalidInterval
        )
        await assertGenerationError(
            coordinator,
            request: .init(interval: interval(), modules: [.metrics], format: .json, includesPhotos: true),
            expected: .photosRequireZIP
        )
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertEqual(store.allocationCount, 0)

        let request = ReportExportRequest(
            interval: interval(), modules: [.metrics], format: .json, includesPhotos: false
        )
        let token = try await coordinator.generate(request)

        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertEqual(repository.intervals, [request.interval])
        XCTAssertEqual(repository.moduleSelections, [request.modules])
        XCTAssertEqual(store.allocationCount, 1)
        XCTAssertTrue(token.cleanup())
    }

    func testEachFormatProducesExactOrderedShareLayoutWithoutCrossFormatArtifacts() async throws {
        let modules: Set<ExportModuleV1> = [.photos, .metrics]
        let snapshot = try emptySnapshot(modules: modules)
        let repository = ExportRepositorySpy(snapshot: snapshot)
        let provider = ExportPhotoProviderSpy()
        let store = ExportTemporaryStoreSpy(root: temporaryDirectory)
        let coordinator = ReportExportCoordinator(
            repository: repository, photoProvider: provider, temporaryStore: store
        )

        let csv = try await coordinator.generate(.init(
            interval: interval(), modules: modules, format: .csv, includesPhotos: false
        ))
        XCTAssertEqual(csv.shareURLs.map(\.lastPathComponent), ["metrics.csv", "photos.csv"])
        XCTAssertEqual(try store.lastWorkspaceRelativePaths(), ["metrics.csv", "photos.csv"])
        XCTAssertTrue(csv.cleanup())

        let json = try await coordinator.generate(.init(
            interval: interval(), modules: modules, format: .json, includesPhotos: false
        ))
        XCTAssertEqual(json.shareURLs.map(\.lastPathComponent), ["export.json"])
        XCTAssertEqual(try store.lastWorkspaceRelativePaths(), ["export.json"])
        XCTAssertTrue(json.cleanup())

        let zip = try await coordinator.generate(.init(
            interval: interval(), modules: modules, format: .bothZip, includesPhotos: false
        ))
        XCTAssertEqual(zip.shareURLs.map(\.lastPathComponent), ["fo-health-export.zip"])
        let archive = try XCTUnwrap(zip.shareURLs.first)
        let payloads = try extractStoredZIP(try Data(contentsOf: archive))
        XCTAssertEqual(Array(payloads.keys).sorted(), [
            "csv/metrics.csv", "csv/photos.csv", "json/export.json", "manifest.json",
        ])
        let initialRequestedIDs = await provider.requestedIDs
        XCTAssertEqual(initialRequestedIDs, [])
        XCTAssertTrue(zip.cleanup())
        XCTAssertEqual(repository.fetchCount, 3)
    }

    func testBothZipManifestHasDeterministicHashesSizesMediaAndNoSelfHashOrPrivateState() async throws {
        let snapshot = try emptySnapshot(modules: [.metrics])
        let coordinator = ReportExportCoordinator(
            repository: ExportRepositorySpy(snapshot: snapshot),
            photoProvider: ExportPhotoProviderSpy(),
            temporaryStore: ExportTemporaryStoreSpy(root: temporaryDirectory)
        )
        let request = ReportExportRequest(
            interval: interval(), modules: [.metrics], format: .bothZip, includesPhotos: false
        )

        let first = try await coordinator.generate(request)
        let firstArchive = try Data(contentsOf: XCTUnwrap(first.shareURLs.first))
        let firstPayloads = try extractStoredZIP(firstArchive)
        let manifestData = try XCTUnwrap(firstPayloads["manifest.json"])
        let manifest = try JSONDecoder().decode(ExportManifestV1.self, from: manifestData)

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.interval.start, "2024-01-01T00:00:00.000000Z")
        XCTAssertEqual(manifest.interval.endExclusive, "2024-02-01T00:00:00.000000Z")
        XCTAssertEqual(manifest.selectedModules, ["metrics"])
        XCTAssertEqual(manifest.format, "bothZip")
        XCTAssertFalse(manifest.includesPhotos)
        XCTAssertEqual(manifest.payloads.map(\.relativePath), ["csv/metrics.csv", "json/export.json"])
        for payload in manifest.payloads {
            let bytes = try XCTUnwrap(firstPayloads[payload.relativePath])
            XCTAssertEqual(payload.byteSize, UInt64(bytes.count))
            XCTAssertEqual(payload.sha256, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
            XCTAssertTrue(["text/csv", "application/json"].contains(payload.mediaType))
        }
        XCTAssertFalse(manifest.payloads.contains { $0.relativePath == "manifest.json" })
        XCTAssertEqual(manifest.photos, [])
        let manifestText = String(decoding: manifestData, as: UTF8.self)
        XCTAssertFalse(manifestText.contains("generated"))
        XCTAssertFalse(manifestText.contains(temporaryDirectory.path))
        XCTAssertFalse(manifestText.contains("imageRef"))
        XCTAssertFalse(manifestText.contains("note"))

        let second = try await coordinator.generate(request)
        let secondArchive = try Data(contentsOf: XCTUnwrap(second.shareURLs.first))
        XCTAssertEqual(firstArchive, secondArchive)
        XCTAssertTrue(first.cleanup())
        XCTAssertTrue(second.cleanup())
    }

    func testPhotosAreExplicitZIPOnlyCandidatesAndStatusesAreCanonicalWithoutPrivateReferences() async throws {
        let includedID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        let missingID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let corruptID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let unavailableID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
        let snapshot = try photoSnapshot([
            (includedID, true, "private/path/one.jpg"),
            (missingID, true, "never export this note"),
            (corruptID, true, "opaque ref"),
            (unavailableID, false, "not called"),
            (includedID, true, "duplicate candidate"),
        ])
        let validJPEG = Data([0xff, 0xd8, 0x01, 0x02, 0xff, 0xd9])
        let provider = ExportPhotoProviderSpy(results: [
            includedID: .available(validJPEG),
            missingID: .missing,
            corruptID: .available(Data([0xff, 0xd8, 0x00])),
        ])
        let repository = ExportRepositorySpy(snapshot: snapshot)
        let coordinator = ReportExportCoordinator(
            repository: repository,
            photoProvider: provider,
            temporaryStore: ExportTemporaryStoreSpy(root: temporaryDirectory)
        )

        for format in [ReportExportFormat.csv, .json] {
            let token = try await coordinator.generate(.init(
                interval: interval(), modules: [.photos], format: format, includesPhotos: false
            ))
            XCTAssertTrue(token.cleanup())
        }
        let noPhotosZIP = try await coordinator.generate(.init(
            interval: interval(), modules: [.photos], format: .bothZip, includesPhotos: false
        ))
        let requestedBeforeOptIn = await provider.requestedIDs
        XCTAssertEqual(requestedBeforeOptIn, [])
        XCTAssertTrue(noPhotosZIP.cleanup())

        let token = try await coordinator.generate(.init(
            interval: interval(), modules: [.photos], format: .bothZip, includesPhotos: true
        ))
        let requestedAfterOptIn = await provider.requestedIDs
        XCTAssertEqual(requestedAfterOptIn, [missingID, corruptID, includedID])
        let payloads = try extractStoredZIP(try Data(contentsOf: XCTUnwrap(token.shareURLs.first)))
        XCTAssertEqual(payloads["photos/\(includedID.uuidString.lowercased()).jpg"], validJPEG)
        XCTAssertNil(payloads["photos/\(missingID.uuidString.lowercased()).jpg"])
        XCTAssertNil(payloads["photos/\(corruptID.uuidString.lowercased()).jpg"])
        XCTAssertNil(payloads["photos/\(unavailableID.uuidString.lowercased()).jpg"])
        let manifest = try JSONDecoder().decode(
            ExportManifestV1.self, from: XCTUnwrap(payloads["manifest.json"])
        )
        XCTAssertEqual(manifest.photos.map(\.photoID), [
            missingID.uuidString.lowercased(),
            corruptID.uuidString.lowercased(),
            includedID.uuidString.lowercased(),
        ])
        XCTAssertEqual(manifest.photos.map(\.status.rawValue), ["missing", "corrupt", "included"])
        XCTAssertEqual(manifest.photos.map(\.relativePath), [
            nil, nil, "photos/\(includedID.uuidString.lowercased()).jpg",
        ])
        let invalidStatusJSON = Data(#"""
        {
          "format":"bothZip",
          "includesPhotos":true,
          "interval":{"endExclusive":"2024-02-01T00:00:00.000000Z","start":"2024-01-01T00:00:00.000000Z"},
          "payloads":[],
          "photos":[{"photoID":"00000000-0000-4000-8000-000000000003","status":"exported"}],
          "schemaVersion":1,
          "selectedModules":["photos"]
        }
        """#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ExportManifestV1.self, from: invalidStatusJSON)) {
            XCTAssertTrue($0 is DecodingError)
        }
        let manifestText = String(decoding: try XCTUnwrap(payloads["manifest.json"]), as: UTF8.self)
        let archivePaths = payloads.keys.joined(separator: "|")
        XCTAssertFalse(manifestText.contains("private/path"))
        XCTAssertFalse(manifestText.contains("never export this note"))
        XCTAssertFalse(manifestText.contains("opaque ref"))
        XCTAssertFalse(archivePaths.contains("private/path"))
        XCTAssertTrue(token.cleanup())
    }

    func testZIPReleasesPhotoPayloadDataBeforeStreamingArchiveEntries() async throws {
        let photoID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
        let lifetime = PayloadDeallocationRecorder()
        var payload: Data? = trackedJPEGData(lifetime: lifetime)
        let provider = OneShotPhotoPayloadProvider(payload: try XCTUnwrap(payload))
        let observations = PayloadLifetimeObservationRecorder()
        payload = nil
        XCTAssertFalse(lifetime.isReleased, "The provider must own the no-copy fixture before use")
        let coordinator = ReportExportCoordinator(
            repository: ExportRepositorySpy(snapshot: try photoSnapshot([(photoID, true, nil)])),
            zipWriter: StoredZIPWriter(
                limits: .init(chunkSize: 1_024),
                chunkObserver: { _ in observations.record(released: lifetime.isReleased) }
            ),
            photoProvider: provider,
            temporaryStore: ExportTemporaryStoreSpy(root: temporaryDirectory)
        )

        let token = try await coordinator.generate(.init(
            interval: interval(),
            modules: [.photos],
            format: .bothZip,
            includesPhotos: true
        ))

        XCTAssertFalse(observations.releaseStates.isEmpty)
        XCTAssertTrue(observations.releaseStates.allSatisfy { $0 })
        XCTAssertTrue(lifetime.isReleased)
        XCTAssertTrue(token.cleanup())
    }

    func testUnexpectedProviderFailureAndCancellationCleanOwnedWorkspace() async throws {
        let photoID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
        let snapshot = try photoSnapshot([(photoID, true, nil)])
        let provider = ExportPhotoProviderSpy(error: FixtureError.providerFailed)
        let store = ExportTemporaryStoreSpy(root: temporaryDirectory)
        let coordinator = ReportExportCoordinator(
            repository: ExportRepositorySpy(snapshot: snapshot),
            photoProvider: provider,
            temporaryStore: store
        )

        do {
            _ = try await coordinator.generate(.init(
                interval: interval(), modules: [.photos], format: .bothZip, includesPhotos: true
            ))
            XCTFail("Expected provider error")
        } catch FixtureError.providerFailed {
            // Expected.
        }
        XCTAssertEqual(store.cleanupCount, 1)
        XCTAssertEqual(try store.lastWorkspaceRelativePaths(), [])

        let suspended = SuspendedExportPhotoProvider()
        let cancellingStore = ExportTemporaryStoreSpy(root: temporaryDirectory)
        let cancellingCoordinator = ReportExportCoordinator(
            repository: ExportRepositorySpy(snapshot: snapshot),
            photoProvider: suspended,
            temporaryStore: cancellingStore
        )
        let task = Task {
            try await cancellingCoordinator.generate(.init(
                interval: interval(), modules: [.photos], format: .bothZip, includesPhotos: true
            ))
        }
        await suspended.waitUntilRequested()
        task.cancel()
        await suspended.resume(.available(Data([0xff, 0xd8, 0xff, 0xd9])))
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertEqual(cancellingStore.cleanupCount, 1)
    }

    func testAllocationMarkerPublicationDoesNotBlockMainActorProgressOrCancellation() async throws {
        let root = temporaryDirectory.appendingPathComponent("off-main-allocation", isDirectory: true)
        let lifecycleGate = ArtifactLifecycleBlockingGate(
            boundary: .markerPublication,
            delayMicroseconds: 800_000
        )
        let fileSystem = LifecycleBlockingTemporaryFileSystem(gate: lifecycleGate)
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000120")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let viewModel = ReportExportViewModel(
            generator: ReportExportCoordinator(
                repository: ExportRepositorySpy(snapshot: try emptySnapshot(modules: [.metrics])),
                temporaryStore: store
            ),
            calendar: utcCalendar(),
            selectedModules: [.metrics],
            format: .json,
            progressDelay: { try await Task.sleep(nanoseconds: 50_000_000) }
        )
        let heartbeat = Task.detached { @Sendable [lifecycleGate, viewModel] in
            let didStart = await lifecycleGate.waitUntilStarted()
            let startedAt = DispatchTime.now().uptimeNanoseconds
            try? await Task.sleep(nanoseconds: 100_000_000)
            return await MainActor.run {
                let result = (
                    didStart: didStart,
                    elapsed: DispatchTime.now().uptimeNanoseconds - startedAt,
                    progressVisible: viewModel.isProgressVisible,
                    state: viewModel.state
                )
                viewModel.cancel()
                return result
            }
        }

        viewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_599))
        let observation = await heartbeat.value

        XCTAssertTrue(observation.didStart)
        XCTAssertLessThan(observation.elapsed, 400_000_000)
        XCTAssertTrue(observation.progressVisible)
        XCTAssertEqual(observation.state, .generating)
        XCTAssertEqual(viewModel.state, .idle)
        for _ in 0..<200 where !(try ownedChildren(of: root).isEmpty) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(try ownedChildren(of: root).isEmpty)
    }

    func testPayloadGenerationCancellationAcquiresMainActorAndCleansUUIDArtifacts() async throws {
        let root = temporaryDirectory.appendingPathComponent("off-main-payload", isDirectory: true)
        let lifecycleGate = ArtifactLifecycleBlockingGate(
            boundary: .payloadWrite,
            delayMicroseconds: 800_000
        )
        let fileSystem = LifecycleBlockingTemporaryFileSystem(gate: lifecycleGate)
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000121")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let viewModel = ReportExportViewModel(
            generator: ReportExportCoordinator(
                repository: ExportRepositorySpy(snapshot: try emptySnapshot(modules: [.metrics])),
                temporaryStore: store
            ),
            calendar: utcCalendar(),
            selectedModules: [.metrics],
            format: .json,
            progressDelay: { try await Task.sleep(nanoseconds: 50_000_000) }
        )
        let cancellation = Task.detached { @Sendable [lifecycleGate, viewModel] in
            let didStart = await lifecycleGate.waitUntilStarted()
            let startedAt = DispatchTime.now().uptimeNanoseconds
            try? await Task.sleep(nanoseconds: 100_000_000)
            return await MainActor.run {
                let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
                viewModel.cancel()
                return (didStart: didStart, elapsed: elapsed)
            }
        }

        viewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_599))
        let cancellationObservation = await cancellation.value

        XCTAssertTrue(cancellationObservation.didStart)
        XCTAssertLessThan(cancellationObservation.elapsed, 400_000_000)
        for _ in 0..<200 where !(try ownedChildren(of: root).isEmpty) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(try ownedChildren(of: root).isEmpty)
    }

    func testRecursiveCleanupDoesNotBlockMainActorAndEventuallyRemovesExactOwnedDirectory() async throws {
        let root = temporaryDirectory.appendingPathComponent("off-main-cleanup", isDirectory: true)
        let lifecycleGate = ArtifactLifecycleBlockingGate(
            boundary: .recursiveCleanup,
            delayMicroseconds: 800_000
        )
        let fileSystem = LifecycleBlockingTemporaryFileSystem(gate: lifecycleGate)
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000127")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let viewModel = ReportExportViewModel(
            generator: ReportExportCoordinator(
                repository: ExportRepositorySpy(snapshot: try emptySnapshot(modules: [.metrics])),
                temporaryStore: store
            ),
            calendar: utcCalendar(),
            selectedModules: [.metrics],
            format: .json,
            progressDelay: { try await Task.sleep(nanoseconds: 50_000_000) }
        )
        viewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_599))
        await viewModel.waitForCurrentGeneration()
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(try ownedChildren(of: root).count, 1)

        let cleanupCall = Task { @MainActor [viewModel] in
            viewModel.shareDidFinish(completed: true)
        }
        let heartbeat = Task.detached { @Sendable [lifecycleGate, viewModel] in
            let didStart = await lifecycleGate.waitUntilStarted()
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let state = await MainActor.run { viewModel.state }
            return (
                didStart: didStart,
                elapsed: DispatchTime.now().uptimeNanoseconds - startedAt,
                state: state
            )
        }
        let observation = await heartbeat.value
        await cleanupCall.value

        XCTAssertTrue(observation.didStart)
        XCTAssertLessThan(observation.elapsed, 400_000_000)
        XCTAssertEqual(observation.state, .idle)
        XCTAssertEqual(viewModel.shareURLs, [])
        for _ in 0..<200 where !(try ownedChildren(of: root).isEmpty) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(try ownedChildren(of: root).isEmpty)
    }

    func testTemporaryStoreProtectsContainedAllocationRetriesCollisionAndCleanupFailure() throws {
        let root = URL(fileURLWithPath: "/task-seven-owned-root", isDirectory: true)
        let firstID = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
        let secondID = UUID(uuidString: "00000000-0000-4000-8000-000000000102")!
        let fileSystem = ExportTemporaryFileSystemSpy()
        fileSystem.collisionIDs = [firstID]
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: sequence([firstID, secondID]),
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )

        let allocation = try store.allocate()
        let owned = root.appendingPathComponent(secondID.uuidString.lowercased(), isDirectory: true)
        XCTAssertEqual(allocation.directoryURL, owned)
        XCTAssertEqual(fileSystem.protectedURLs, [root, owned])
        XCTAssertEqual(fileSystem.backupExcludedURLs, [root, owned])
        let payload = try allocation.write(Data("payload".utf8), relativePath: "nested/payload.json")
        XCTAssertEqual(payload, owned.appendingPathComponent("nested/payload.json"))
        let token = allocation.makeArtifactToken(shareURLs: [payload])

        fileSystem.remainingRemovalFailures = 1
        XCTAssertFalse(token.cleanup())
        XCTAssertTrue(token.cleanup())
        XCTAssertEqual(fileSystem.removalAttempts, [owned, owned])
        XCTAssertFalse(fileSystem.removedURLs.contains(root))
    }

    func testTemporaryCleanupOutlivesStoreAndMarkerIdentityPreventsStaleDeletion() async throws {
        let root = URL(fileURLWithPath: "/task-seven-lifetime-root", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000103")!
        let scheduler = ManualCleanupScheduler()
        let registry = ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        let fileSystem = ExportTemporaryFileSystemSpy()
        var store: ReportExportTemporaryStore? = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: registry
        )
        let allocation = try XCTUnwrap(store).allocate()
        let owned = allocation.directoryURL
        let token = allocation.makeArtifactToken(shareURLs: [])
        fileSystem.remainingRemovalFailures = 1

        XCTAssertFalse(token.cleanup())
        store = nil
        fileSystem.replaceMarker(at: owned)
        await scheduler.runAll()

        XCTAssertEqual(fileSystem.removalAttempts, [owned])
        XCTAssertFalse(fileSystem.removedURLs.contains(owned))
        XCTAssertTrue(fileSystem.exists(at: owned), "A stale cleanup must preserve a reused path with a new marker")
    }

    func testArtifactTokenRetainsRealAllocationCleanupAfterStoreAndAllocationRelease() throws {
        let root = temporaryDirectory.appendingPathComponent("token-retention", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000104")!
        var store: ReportExportTemporaryStore? = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: FileManagerReportExportTemporaryFileSystem(),
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        var allocation: ReportExportAllocation? = try XCTUnwrap(store).allocate()
        let owned = try XCTUnwrap(allocation).directoryURL
        let token = try XCTUnwrap(allocation).makeArtifactToken(shareURLs: [])

        allocation = nil
        store = nil

        XCTAssertTrue(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(token.cleanup())
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }

    func testFileManagerAtomicWriteNeverOverwritesAndLeavesNoSidecarOnSuccessOrFailure() throws {
        let root = temporaryDirectory.appendingPathComponent("atomic-write", isDirectory: true)
        let destination = root.appendingPathComponent("export.json")
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        let fileSystem = FileManagerReportExportTemporaryFileSystem()
        try fileSystem.createRootDirectory(at: root)

        try fileSystem.writeAtomically(first, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), first)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(),
            [destination.lastPathComponent]
        )

        XCTAssertThrowsError(try fileSystem.writeAtomically(second, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), first)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(),
            [destination.lastPathComponent]
        )
    }

    func testPayloadStageUnlinkFailureStopsBeforeDataWriteAndAutomaticallyCleansResidue() async throws {
        let root = temporaryDirectory.appendingPathComponent(
            "payload-unlink-failure-root",
            isDirectory: true
        )
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000136")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        let privateBytes = Data("payload-must-not-reach-visible-staging".utf8)
        fileSystem.arm(.payloadStageBeforeUnlink) {
            let prefix = ".payload.json."
            let candidates = try FileManager.default.contentsOfDirectory(
                at: allocation.directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            guard let visible = candidates.first(where: { candidate in
                let name = candidate.lastPathComponent
                guard name.hasPrefix(prefix), name.hasSuffix(".partial") else { return false }
                let start = name.index(name.startIndex, offsetBy: prefix.count)
                let end = name.index(name.endIndex, offsetBy: -".partial".count)
                return UUID(uuidString: String(name[start..<end])) != nil
            }) else { throw FixtureError.pathInspectionFailed }
            var status = stat()
            guard Darwin.lstat(visible.path, &status) == 0,
                  Darwin.chflags(
                    visible.path,
                    status.st_flags | UInt32(UF_APPEND | UF_IMMUTABLE)
                  ) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        defer { _ = allocation.cleanup() }

        XCTAssertThrowsError(
            try allocation.write(privateBytes, relativePath: "payload.json")
        )
        let residue = try uuidPartialArtifacts(
            named: "payload.json",
            in: allocation.directoryURL
        )
        XCTAssertEqual(residue.count, 1)
        XCTAssertEqual(try residue.map { try Data(contentsOf: $0).count }, [0])

        for _ in 0..<200 where !(try uuidPartialArtifacts(
            named: "payload.json",
            in: allocation.directoryURL
        ).isEmpty) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(try uuidPartialArtifacts(
            named: "payload.json",
            in: allocation.directoryURL
        ).isEmpty)
        XCTAssertTrue(
            allocation.cleanup(),
            "The allocation must remain independently cleanup-owned after stage residue recovery"
        )
    }

    func testPayloadStageHardLinkBeforeUnlinkNeverReceivesPrivateBytesAndIsCleaned() async throws {
        let root = temporaryDirectory.appendingPathComponent(
            "payload-hard-link-root",
            isDirectory: true
        )
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000141")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        let linkedResidue = allocation.directoryURL.appendingPathComponent("linked-zero-stage")
        fileSystem.arm(.payloadStageCreated) {
            let prefix = ".payload.json."
            let candidates = try FileManager.default.contentsOfDirectory(
                at: allocation.directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            guard let visible = candidates.first(where: { candidate in
                let name = candidate.lastPathComponent
                guard name.hasPrefix(prefix), name.hasSuffix(".partial") else { return false }
                let start = name.index(name.startIndex, offsetBy: prefix.count)
                let end = name.index(name.endIndex, offsetBy: -".partial".count)
                return UUID(uuidString: String(name[start..<end])) != nil
            }) else { throw FixtureError.pathInspectionFailed }
            guard Darwin.link(visible.path, linkedResidue.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }

        XCTAssertThrowsError(
            try allocation.write(Data("private-payload".utf8), relativePath: "payload.json")
        )
        XCTAssertEqual(try Data(contentsOf: linkedResidue), Data())
        let allocationEntry = try ReportExportDescriptorIO.makeEntry(
            at: allocation.directoryURL,
            createIfMissing: false
        )
        try ReportExportNamespaceAuthority.shared.transaction {
            try ReportExportDescriptorIO.withRemovalAllowed(
                in: allocationEntry.descriptor.rawValue
            ) {
                guard Darwin.unlink(linkedResidue.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
        }
        for _ in 0..<200 where !(try uuidPartialArtifacts(
            named: "payload.json",
            in: allocation.directoryURL
        ).isEmpty) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(try uuidPartialArtifacts(
            named: "payload.json",
            in: allocation.directoryURL
        ).isEmpty)
        XCTAssertTrue(
            allocation.cleanup(),
            "The allocation must remain independently cleanup-owned after stage residue recovery"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkedResidue.path))
    }

    func testPayloadStageReplacementAtPreUnlinkBoundaryIsNeverDeleted() async throws {
        let root = temporaryDirectory.appendingPathComponent(
            "payload-pre-unlink-replacement-root",
            isDirectory: true
        )
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: {
                UUID(uuidString: "00000000-0000-4000-8000-000000000144")!
            },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(
                scheduler: ManualCleanupScheduler()
            )
        )
        let allocation = try store.allocate()
        defer { _ = allocation.cleanup() }
        let privateBytes = Data("payload-private-write".utf8)
        let replacementBytes = Data("non-owned-replacement".utf8)
        let probe = PayloadStageReplacementProbe(
            directory: allocation.directoryURL,
            outputName: "payload.json",
            replacementBytes: replacementBytes
        )
        fileSystem.arm(.payloadStageBeforeUnlink) { try probe.attemptReplacement() }

        let written: URL?
        do {
            written = try allocation.write(privateBytes, relativePath: "payload.json")
        } catch {
            written = nil
        }
        for _ in 0..<200 where probe.parkedExists {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(probe.didAttempt)
        XCTAssertTrue(probe.moveWasRejected)
        XCTAssertFalse(probe.didReplace)
        XCTAssertFalse(probe.parkedExists)
        let writtenData = try written.map { try Data(contentsOf: $0) }
        XCTAssertEqual(writtenData, privateBytes)
        if probe.didReplace {
            XCTAssertEqual(try? Data(contentsOf: probe.replacementURL), replacementBytes)
        }
    }

    func testDescriptorDirectoryEnumerationDoesNotAdvanceTheCallersCleanupCursor() throws {
        let directory = temporaryDirectory.appendingPathComponent(
            "independent-directory-cursor",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("marker".utf8).write(to: directory.appendingPathComponent(".allocation-id"))
        try Data("payload".utf8).write(to: directory.appendingPathComponent("payload.json"))
        let entry = try ReportExportDescriptorIO.makeEntry(at: directory, createIfMissing: false)
        let expected = [".allocation-id", "payload.json"]

        XCTAssertEqual(
            try ReportExportDescriptorIO.directoryNames(entry.descriptor.rawValue),
            expected
        )
        XCTAssertEqual(
            try ReportExportDescriptorIO.directoryNames(entry.descriptor.rawValue),
            expected,
            "Each enumeration must use an independent open-file description"
        )
    }

    func testPrivateNamespaceLeaseRejectsRootOwnedAndNestedMovesWhileAllocationIsLive() throws {
        let root = temporaryDirectory.appendingPathComponent(
            "private-namespace-root",
            isDirectory: true
        )
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: FileManagerReportExportTemporaryFileSystem(),
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000137")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        _ = try allocation.write(Data("private".utf8), relativePath: "nested/payload.json")
        let owned = allocation.directoryURL
        let nested = owned.appendingPathComponent("nested", isDirectory: true)

        XCTAssertEqual(try ownerAndPermissions(of: root).permissions, S_IRWXU)
        XCTAssertEqual(try ownerAndPermissions(of: root).owner, geteuid())
        XCTAssertEqual(try ownerAndPermissions(of: owned).permissions, S_IRWXU)
        XCTAssertEqual(try ownerAndPermissions(of: owned).owner, geteuid())
        XCTAssertEqual(try ownerAndPermissions(of: nested).permissions, S_IRWXU)
        XCTAssertEqual(try ownerAndPermissions(of: nested).owner, geteuid())

        XCTAssertTrue(try moveIsRejectedAndRestoreIfNeeded(
            nested,
            to: temporaryDirectory.appendingPathComponent("private-nested-parked")
        ))
        XCTAssertTrue(try moveIsRejectedAndRestoreIfNeeded(
            owned,
            to: temporaryDirectory.appendingPathComponent("private-owned-parked")
        ))
        XCTAssertTrue(try moveIsRejectedAndRestoreIfNeeded(
            root,
            to: temporaryDirectory.appendingPathComponent("private-root-parked")
        ))
        XCTAssertTrue(allocation.cleanup())
    }

    func testTemporaryStoreRetainsMarkerBoundCleanupWhenSetupFailureRemovalFails() async throws {
        let root = URL(fileURLWithPath: "/task-seven-setup-failure-root", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000105")!
        let owned = root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let scheduler = ManualCleanupScheduler()
        let registry = ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        let fileSystem = ExportTemporaryFileSystemSpy()
        fileSystem.backupExclusionFailureURL = owned
        fileSystem.remainingRemovalFailures = 1
        var store: ReportExportTemporaryStore? = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: registry
        )

        XCTAssertThrowsError(try XCTUnwrap(store).allocate()) { error in
            guard case FixtureError.setupFailed = error else {
                return XCTFail("Unexpected setup error: \(error)")
            }
        }
        XCTAssertEqual(fileSystem.backupExcludedURLs, [root, owned])
        XCTAssertEqual(fileSystem.removalAttempts, [owned])
        XCTAssertTrue(fileSystem.exists(at: owned))

        store = nil
        await scheduler.runAll()

        XCTAssertEqual(fileSystem.removalAttempts, [owned, owned])
        XCTAssertEqual(fileSystem.removedURLs, [owned])
        XCTAssertFalse(fileSystem.exists(at: owned))
    }

    func testTemporaryCleanupRetriesTransientMarkerReadFailureThenRemovesExactOwnedDirectory() throws {
        let root = URL(fileURLWithPath: "/task-seven-marker-read-root", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000106")!
        let fileSystem = ExportTemporaryFileSystemSpy()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        let owned = allocation.directoryURL
        let token = allocation.makeArtifactToken(shareURLs: [])
        fileSystem.remainingReadFailures = 1

        XCTAssertFalse(token.cleanup())
        XCTAssertEqual(fileSystem.removalAttempts, [])
        XCTAssertTrue(fileSystem.exists(at: owned))

        XCTAssertTrue(token.cleanup())
        XCTAssertEqual(fileSystem.removalAttempts, [owned])
        XCTAssertEqual(fileSystem.removedURLs, [owned])
        XCTAssertFalse(fileSystem.removedURLs.contains(root))
        XCTAssertFalse(fileSystem.exists(at: owned))
    }

    func testTemporaryWriteRejectsExistingNestedSymlinkWithoutWritingOutsideOwnedDirectory() throws {
        let root = temporaryDirectory.appendingPathComponent("nested-symlink-root", isDirectory: true)
        let external = temporaryDirectory.appendingPathComponent("nested-symlink-external", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: FileManagerReportExportTemporaryFileSystem(),
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000122")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        let nested = allocation.directoryURL.appendingPathComponent("nested", isDirectory: true)
        let escapedPayload = external.appendingPathComponent("payload.json")
        try setPrivateNamespaceProtection(false, at: allocation.directoryURL)
        try FileManager.default.createSymbolicLink(at: nested, withDestinationURL: external)
        try setPrivateNamespaceProtection(true, at: allocation.directoryURL)

        XCTAssertThrowsError(
            try allocation.write(Data("private".utf8), relativePath: "nested/payload.json")
        ) { error in
            XCTAssertEqual(error as? ReportExportError, .unsafeTemporaryPath)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: escapedPayload.path))

        try setPrivateNamespaceProtection(false, at: allocation.directoryURL)
        try FileManager.default.removeItem(at: nested)
        try setPrivateNamespaceProtection(true, at: allocation.directoryURL)
        XCTAssertTrue(allocation.cleanup())
    }

    func testTemporaryCleanupRejectsOwnedSymlinkSwapEvenWhenMarkerIsCopied() throws {
        let root = temporaryDirectory.appendingPathComponent("owned-symlink-root", isDirectory: true)
        let external = temporaryDirectory.appendingPathComponent("owned-symlink-external", isDirectory: true)
        let parked = temporaryDirectory.appendingPathComponent("parked-owned", isDirectory: true)
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: FileManagerReportExportTemporaryFileSystem(),
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000123")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        let owned = allocation.directoryURL
        let marker = try Data(contentsOf: owned.appendingPathComponent(".allocation-id"))
        let sentinel = external.appendingPathComponent("sentinel")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
        try marker.write(to: external.appendingPathComponent(".allocation-id"))
        try Data("not-owned".utf8).write(to: sentinel)
        try setPrivateNamespaceProtection(false, at: owned)
        try setPrivateNamespaceProtection(false, at: root)
        try FileManager.default.moveItem(at: owned, to: parked)
        try FileManager.default.createSymbolicLink(at: owned, withDestinationURL: external)
        try setPrivateNamespaceProtection(true, at: root)

        XCTAssertFalse(allocation.cleanup())
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("not-owned".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: parked.path))

        try setPrivateNamespaceProtection(false, at: root)
        if (try? owned.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            try FileManager.default.removeItem(at: owned)
        }
        try FileManager.default.moveItem(at: parked, to: owned)
        try setPrivateNamespaceProtection(true, at: owned)
        try setPrivateNamespaceProtection(true, at: root)
        XCTAssertTrue(allocation.cleanup())
    }

    func testTemporaryCleanupRejectsRootSymlinkSwapWithReproducedOwnedPathAndMarker() throws {
        let root = temporaryDirectory.appendingPathComponent("root-symlink-root", isDirectory: true)
        let parkedRoot = temporaryDirectory.appendingPathComponent("parked-root", isDirectory: true)
        let externalRoot = temporaryDirectory.appendingPathComponent("external-root", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000124")!
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: FileManagerReportExportTemporaryFileSystem(),
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        let owned = allocation.directoryURL
        let marker = try Data(contentsOf: owned.appendingPathComponent(".allocation-id"))
        let externalOwned = externalRoot.appendingPathComponent(id.uuidString.lowercased())
        let sentinel = externalOwned.appendingPathComponent("sentinel")
        try FileManager.default.createDirectory(at: externalOwned, withIntermediateDirectories: true)
        try marker.write(to: externalOwned.appendingPathComponent(".allocation-id"))
        try Data("not-owned".utf8).write(to: sentinel)
        try setPrivateNamespaceProtection(false, at: root)
        try FileManager.default.moveItem(at: root, to: parkedRoot)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: externalRoot)

        XCTAssertFalse(allocation.cleanup())
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("not-owned".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: parkedRoot.path))

        if (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            try FileManager.default.removeItem(at: root)
        }
        try FileManager.default.moveItem(at: parkedRoot, to: root)
        try setPrivateNamespaceProtection(true, at: root)
        XCTAssertTrue(allocation.cleanup())
    }

    func testTemporaryWriteRejectsRootSwapAtOperationBoundaryWithoutExternalWrite() throws {
        let root = temporaryDirectory.appendingPathComponent("root-write-race", isDirectory: true)
        let parkedRoot = temporaryDirectory.appendingPathComponent("root-write-race-parked", isDirectory: true)
        let externalRoot = temporaryDirectory.appendingPathComponent("root-write-race-external", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000128")!
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        let externalOwned = externalRoot.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let externalPayload = externalOwned.appendingPathComponent("payload.json")
        let sentinel = externalOwned.appendingPathComponent("sentinel")
        try FileManager.default.createDirectory(at: externalOwned, withIntermediateDirectories: true)
        try Data("external-sentinel".utf8).write(to: sentinel)
        fileSystem.arm(.payloadWrite) {
            try setPrivateNamespaceProtection(false, at: root)
            try FileManager.default.moveItem(at: root, to: parkedRoot)
            try FileManager.default.createSymbolicLink(at: root, withDestinationURL: externalRoot)
        }

        XCTAssertThrowsError(try allocation.write(Data("private".utf8), relativePath: "payload.json"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: externalPayload.path))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("external-sentinel".utf8))

        try FileManager.default.removeItem(at: root)
        try FileManager.default.moveItem(at: parkedRoot, to: root)
        try setPrivateNamespaceProtection(true, at: root)
        XCTAssertTrue(allocation.cleanup())
    }

    func testTemporaryWriteRejectsOwnedSwapAtOperationBoundaryWithoutExternalWrite() throws {
        let root = temporaryDirectory.appendingPathComponent("owned-write-race", isDirectory: true)
        let parkedOwned = temporaryDirectory.appendingPathComponent("owned-write-race-parked", isDirectory: true)
        let externalOwned = temporaryDirectory.appendingPathComponent("owned-write-race-external", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000129")!
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        let owned = allocation.directoryURL
        let externalPayload = externalOwned.appendingPathComponent("payload.json")
        let sentinel = externalOwned.appendingPathComponent("sentinel")
        try FileManager.default.createDirectory(at: externalOwned, withIntermediateDirectories: false)
        try Data("external-sentinel".utf8).write(to: sentinel)
        fileSystem.arm(.payloadWrite) {
            try setPrivateNamespaceProtection(false, at: owned)
            try setPrivateNamespaceProtection(false, at: root)
            try FileManager.default.moveItem(at: owned, to: parkedOwned)
            try FileManager.default.createSymbolicLink(at: owned, withDestinationURL: externalOwned)
            try setPrivateNamespaceProtection(true, at: root)
        }

        XCTAssertThrowsError(try allocation.write(Data("private".utf8), relativePath: "payload.json"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: externalPayload.path))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("external-sentinel".utf8))

        try setPrivateNamespaceProtection(false, at: root)
        if FileManager.default.fileExists(atPath: owned.path) {
            try FileManager.default.removeItem(at: owned)
        }
        try FileManager.default.moveItem(at: parkedOwned, to: owned)
        try setPrivateNamespaceProtection(true, at: owned)
        try setPrivateNamespaceProtection(true, at: root)
        XCTAssertTrue(allocation.cleanup())
    }

    func testTemporaryWriteRejectsNestedSwapAtOperationBoundaryWithoutExternalWrite() throws {
        let root = temporaryDirectory.appendingPathComponent("nested-write-race", isDirectory: true)
        let parkedNested = temporaryDirectory.appendingPathComponent("nested-write-race-parked", isDirectory: true)
        let externalNested = temporaryDirectory.appendingPathComponent("nested-write-race-external", isDirectory: true)
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000130")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        _ = try allocation.write(Data("seed".utf8), relativePath: "nested/seed.json")
        let nested = allocation.directoryURL.appendingPathComponent("nested", isDirectory: true)
        let externalPayload = externalNested.appendingPathComponent("payload.json")
        let sentinel = externalNested.appendingPathComponent("sentinel")
        try FileManager.default.createDirectory(at: externalNested, withIntermediateDirectories: false)
        try Data("external-sentinel".utf8).write(to: sentinel)
        fileSystem.arm(.payloadWrite) {
            try setPrivateNamespaceProtection(false, at: nested)
            try setPrivateNamespaceProtection(false, at: allocation.directoryURL)
            try FileManager.default.moveItem(at: nested, to: parkedNested)
            try FileManager.default.createSymbolicLink(at: nested, withDestinationURL: externalNested)
            try setPrivateNamespaceProtection(true, at: allocation.directoryURL)
        }

        XCTAssertThrowsError(
            try allocation.write(Data("private".utf8), relativePath: "nested/payload.json")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: externalPayload.path))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("external-sentinel".utf8))

        try setPrivateNamespaceProtection(false, at: allocation.directoryURL)
        try FileManager.default.removeItem(at: nested)
        try FileManager.default.moveItem(at: parkedNested, to: nested)
        try setPrivateNamespaceProtection(true, at: nested)
        try setPrivateNamespaceProtection(true, at: allocation.directoryURL)
        XCTAssertTrue(allocation.cleanup())
    }

    func testTemporaryCleanupRejectsOwnedReplacementAfterMarkerReadWithoutDeletingIt() throws {
        let root = temporaryDirectory.appendingPathComponent("owned-cleanup-race", isDirectory: true)
        let parkedOwned = temporaryDirectory.appendingPathComponent("owned-cleanup-race-parked", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000131")!
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        let owned = allocation.directoryURL
        let marker = try Data(contentsOf: owned.appendingPathComponent(".allocation-id"))
        let replacementMarker = owned.appendingPathComponent(".allocation-id")
        let replacementSentinel = owned.appendingPathComponent("sentinel")
        fileSystem.arm(.markerRead) {
            try setPrivateNamespaceProtection(false, at: owned)
            try setPrivateNamespaceProtection(false, at: root)
            try FileManager.default.moveItem(at: owned, to: parkedOwned)
            try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
            try marker.write(to: replacementMarker)
            try Data("replacement".utf8).write(to: replacementSentinel)
            try setPrivateNamespaceProtection(true, at: root)
        }

        XCTAssertFalse(allocation.cleanup())
        XCTAssertEqual(
            try? Data(contentsOf: replacementSentinel),
            Optional(Data("replacement".utf8))
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: parkedOwned.path))

        try setPrivateNamespaceProtection(false, at: root)
        if FileManager.default.fileExists(atPath: owned.path) {
            try FileManager.default.removeItem(at: owned)
        }
        try FileManager.default.moveItem(at: parkedOwned, to: owned)
        try setPrivateNamespaceProtection(true, at: owned)
        try setPrivateNamespaceProtection(true, at: root)
        XCTAssertTrue(allocation.cleanup())
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }

    func testTemporaryCleanupRejectsRootReplacementAfterMarkerReadWithoutDeletingIt() throws {
        let root = temporaryDirectory.appendingPathComponent("root-cleanup-race", isDirectory: true)
        let parkedRoot = temporaryDirectory.appendingPathComponent("root-cleanup-race-parked", isDirectory: true)
        let replacementRoot = temporaryDirectory.appendingPathComponent("root-cleanup-race-replacement", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000132")!
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        let marker = try Data(contentsOf: allocation.directoryURL.appendingPathComponent(".allocation-id"))
        let replacementOwned = replacementRoot.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let replacementSentinel = replacementOwned.appendingPathComponent("sentinel")
        fileSystem.arm(.markerRead) {
            try setPrivateNamespaceProtection(false, at: root)
            try FileManager.default.moveItem(at: root, to: parkedRoot)
            try FileManager.default.createDirectory(at: replacementOwned, withIntermediateDirectories: true)
            try marker.write(to: replacementOwned.appendingPathComponent(".allocation-id"))
            try Data("replacement".utf8).write(to: replacementSentinel)
            try FileManager.default.createSymbolicLink(at: root, withDestinationURL: replacementRoot)
        }

        XCTAssertFalse(allocation.cleanup())
        XCTAssertEqual(
            try? Data(contentsOf: replacementSentinel),
            Optional(Data("replacement".utf8))
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: parkedRoot.path))

        try FileManager.default.removeItem(at: root)
        try FileManager.default.moveItem(at: parkedRoot, to: root)
        try setPrivateNamespaceProtection(true, at: root)
        XCTAssertTrue(allocation.cleanup())
        XCTAssertFalse(FileManager.default.fileExists(atPath: allocation.directoryURL.path))
    }

    func testCleanupLeaseRejectsNestedMoveAtRecursiveCleanupBoundary() throws {
        let root = temporaryDirectory.appendingPathComponent(
            "recursive-lease-root",
            isDirectory: true
        )
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000138")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        _ = try allocation.write(Data("private".utf8), relativePath: "nested/payload.json")
        let nested = allocation.directoryURL.appendingPathComponent("nested", isDirectory: true)
        let parked = temporaryDirectory.appendingPathComponent(
            "recursive-lease-nested-parked",
            isDirectory: true
        )
        let move = FilesystemMoveAttempt()
        fileSystem.arm(.recursiveCleanup) {
            move.attemptAndRestore(from: nested, to: parked)
        }

        XCTAssertTrue(allocation.cleanup())
        XCTAssertTrue(move.wasRejected)
        XCTAssertFalse(move.privateBytesBecameVisibleOutside)
        XCTAssertFalse(FileManager.default.fileExists(atPath: parked.path))
    }

    func testRecursiveCleanupRejectsQuarantineReplacementBetweenMetadataAndOpen() throws {
        let root = temporaryDirectory.appendingPathComponent("cleanup-metadata-open-root")
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000144")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        _ = try allocation.write(Data("private".utf8), relativePath: "nested/payload.json")
        let probe = QuarantineMoveAttempt(
            parent: allocation.directoryURL,
            parked: temporaryDirectory.appendingPathComponent("metadata-open-parked")
        )
        fileSystem.arm(.recursiveEntryOpened) { probe.attempt() }

        XCTAssertTrue(allocation.cleanup())
        XCTAssertTrue(probe.wasRejected)
        XCTAssertFalse(probe.privateEntryBecameVisible)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probe.parkedURL.path))
    }

    func testRecursiveCleanupRejectsQuarantineReplacementBetweenMetadataAndUnlink() throws {
        let root = temporaryDirectory.appendingPathComponent("cleanup-metadata-unlink-root")
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { UUID(uuidString: "00000000-0000-4000-8000-000000000145")! },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: ManualCleanupScheduler())
        )
        let allocation = try store.allocate()
        _ = try allocation.write(Data("private".utf8), relativePath: "nested/payload.json")
        let probe = QuarantineMoveAttempt(
            parent: allocation.directoryURL,
            parked: temporaryDirectory.appendingPathComponent("metadata-unlink-parked")
        )
        fileSystem.arm(.recursiveEntryBeforeUnlink) { probe.attempt() }

        XCTAssertTrue(allocation.cleanup())
        XCTAssertTrue(probe.wasRejected)
        XCTAssertFalse(probe.privateEntryBecameVisible)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probe.parkedURL.path))
    }

    func testPartialMarkerWriteFailureRetainsExactCleanupAfterStoreRelease() async throws {
        let root = URL(fileURLWithPath: "/task-seven-partial-marker-root", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000125")!
        let owned = root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let scheduler = ManualCleanupScheduler()
        let registry = ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        let fileSystem = ExportTemporaryFileSystemSpy()
        fileSystem.failMarkerWriteAfterPartialPublication = true
        fileSystem.remainingRemovalFailures = 1
        var store: ReportExportTemporaryStore? = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: registry
        )

        XCTAssertThrowsError(try XCTUnwrap(store).allocate()) { error in
            guard case FixtureError.markerWriteFailed = error else {
                return XCTFail("Unexpected marker-write error: \(error)")
            }
        }
        XCTAssertTrue(fileSystem.exists(at: owned))
        XCTAssertEqual(fileSystem.removalAttempts, [owned])

        store = nil
        await scheduler.runAll()

        XCTAssertEqual(fileSystem.removalAttempts, [owned, owned])
        XCTAssertFalse(fileSystem.exists(at: owned))
    }

    func testReusedURLKeepsOldAndNewCleanupRetriesIndependentAfterTokenAndStoreRelease() async throws {
        let root = URL(fileURLWithPath: "/task-seven-reused-cleanup-root", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000126")!
        let owned = root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let scheduler = ManualCleanupScheduler()
        let registry = ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        let fileSystem = ExportTemporaryFileSystemSpy()
        var oldStore: ReportExportTemporaryStore? = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: registry
        )
        var oldToken: ExportArtifactToken? = try XCTUnwrap(oldStore).allocate()
            .makeArtifactToken(shareURLs: [])
        fileSystem.remainingRemovalFailures = 1
        XCTAssertFalse(try XCTUnwrap(oldToken).cleanup())
        fileSystem.forceRemoveForReuse(at: owned)
        oldToken = nil
        oldStore = nil

        var newStore: ReportExportTemporaryStore? = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: registry
        )
        var newToken: ExportArtifactToken? = try XCTUnwrap(newStore).allocate()
            .makeArtifactToken(shareURLs: [])
        fileSystem.remainingRemovalFailures = 1
        XCTAssertFalse(try XCTUnwrap(newToken).cleanup())
        newToken = nil
        newStore = nil

        await scheduler.runAll()

        XCTAssertFalse(fileSystem.exists(at: owned))
        XCTAssertEqual(fileSystem.removedURLs.filter { $0 == owned }.count, 1)
    }

    func testLifetimeCleanupRegistryStopsAfterFinitePermanentFailuresAndReleasesOperation() async {
        let scheduler = ManualCleanupScheduler()
        let registry = ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        let cleanupID = UUID(uuidString: "00000000-0000-4000-8000-000000000133")!
        let directory = URL(fileURLWithPath: "/task-seven-terminal-cleanup")
        let attemptCount = LockedInteger()
        weak var releasedProbe: CleanupLifetimeProbe?
        do {
            let probe = CleanupLifetimeProbe()
            releasedProbe = probe
            registry.retain(cleanupID: cleanupID, directory: directory) { [probe] in
                _ = probe
                attemptCount.increment()
                throw FixtureError.cleanupFailed
            }
        }

        for _ in 0..<16 {
            await scheduler.runNextBatch()
        }

        XCTAssertEqual(attemptCount.value, 8)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertNil(releasedProbe)
    }

    func testNilCreationRecoveryKeepsAllSixtyFourCapacityReservations() async {
        let scheduler = ManualCleanupScheduler()
        let registry = ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        let recoveryGate = CleanupRecoveryGate()
        let identifiers = (0..<65).map { offset in
            UUID(uuidString: String(
                format: "00000000-0000-4000-8000-%012d",
                500 + offset
            ))!
        }

        for (index, cleanupID) in identifiers.prefix(64).enumerated() {
            XCTAssertTrue(registry.reserve(cleanupID: cleanupID))
            XCTAssertTrue(registry.retain(
                cleanupID: cleanupID,
                directory: URL(
                    fileURLWithPath: "/task-seven-unidentified-residue-\(cleanupID)",
                    isDirectory: true
                ),
                operation: {
                    if index == 0, recoveryGate.isOpen { return }
                    throw FixtureError.cleanupFailed
                },
                terminalRecovery: { nil }
            ))
        }
        for _ in 0..<8 {
            await scheduler.runNextBatch()
        }

        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(registry.reserve(cleanupID: identifiers[64]))

        recoveryGate.open()
        registry.retryPendingNow()
        XCTAssertTrue(registry.reserve(cleanupID: identifiers[64]))
        registry.releaseReservation(cleanupID: identifiers[64])
    }

    func testNextAllocationRecoversTerminalMarkerOwnedDirectoryWithoutRetainedClosure() async throws {
        let root = URL(fileURLWithPath: "/task-seven-terminal-recovery-root", isDirectory: true)
        let oldID = UUID(uuidString: "00000000-0000-4000-8000-000000000134")!
        let newID = UUID(uuidString: "00000000-0000-4000-8000-000000000135")!
        let oldOwned = root.appendingPathComponent(oldID.uuidString.lowercased(), isDirectory: true)
        let scheduler = ManualCleanupScheduler()
        let registry = ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        let fileSystem = ExportTemporaryFileSystemSpy()
        var oldStore: ReportExportTemporaryStore? = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { oldID },
            cleanupRegistry: registry
        )
        var oldToken: ExportArtifactToken? = try XCTUnwrap(oldStore).allocate()
            .makeArtifactToken(shareURLs: [])
        fileSystem.remainingRemovalFailures = 100
        XCTAssertFalse(try XCTUnwrap(oldToken).cleanup())
        oldToken = nil
        oldStore = nil
        for _ in 0..<16 {
            await scheduler.runNextBatch()
        }

        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertTrue(fileSystem.exists(at: oldOwned))
        fileSystem.remainingRemovalFailures = 0
        let newStore = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { newID },
            cleanupRegistry: registry
        )
        let newAllocation = try newStore.allocate()

        XCTAssertFalse(fileSystem.exists(at: oldOwned))
        XCTAssertEqual(newAllocation.directoryURL.lastPathComponent, newID.uuidString.lowercased())
        XCTAssertTrue(newAllocation.cleanup())
    }

    func testPostMkdirPathInspectionFailureRetainsCleanupAuthorization() async throws {
        let root = URL(fileURLWithPath: "/task-seven-post-mkdir-open-root", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000139")!
        let owned = root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let scheduler = ManualCleanupScheduler()
        let fileSystem = ExportTemporaryFileSystemSpy()
        fileSystem.remainingOwnedPathInspectionFailures = 1
        fileSystem.remainingRemovalFailures = 1
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        )

        XCTAssertThrowsError(try store.allocate())
        XCTAssertTrue(fileSystem.exists(at: owned))
        await scheduler.runAll()

        XCTAssertFalse(fileSystem.exists(at: owned))
        XCTAssertEqual(fileSystem.removalAttempts, [owned, owned])
    }

    func testPostMkdirIdentityFailureRetainsCleanupAuthorization() async throws {
        let root = URL(fileURLWithPath: "/task-seven-post-mkdir-identity-root", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000140")!
        let owned = root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let scheduler = ManualCleanupScheduler()
        let fileSystem = ExportTemporaryFileSystemSpy()
        fileSystem.remainingOwnedIdentityFailures = 1
        fileSystem.remainingRemovalFailures = 1
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        )

        XCTAssertThrowsError(try store.allocate())
        XCTAssertTrue(fileSystem.exists(at: owned))
        await scheduler.runAll()

        XCTAssertFalse(fileSystem.exists(at: owned))
        XCTAssertEqual(fileSystem.removalAttempts, [owned, owned])
    }

    func testDescriptorMkdirOpenFailureRetainsExactCleanupAuthorization() async throws {
        let root = temporaryDirectory.appendingPathComponent("descriptor-open-failure-root")
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000142")!
        let owned = root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let scheduler = ManualCleanupScheduler()
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let failure = AppendOnlyDirectoryFailure(directory: root)
        fileSystem.arm(.allocationDirectoryCreated) { try failure.enableAndThrow() }
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        )

        XCTAssertThrowsError(try store.allocate())
        XCTAssertTrue(FileManager.default.fileExists(atPath: owned.path))
        try failure.clear()
        await scheduler.runAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testDescriptorPostSecurityFailureRetainsExactCleanupAuthorization() async throws {
        let root = temporaryDirectory.appendingPathComponent("descriptor-security-failure-root")
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000143")!
        let owned = root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let scheduler = ManualCleanupScheduler()
        let fileSystem = BoundaryRaceTemporaryFileSystem()
        let failure = AppendOnlyDirectoryFailure(directory: root)
        fileSystem.arm(.allocationDirectorySecured) { try failure.enableAndThrow() }
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: { id },
            cleanupRegistry: ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        )

        XCTAssertThrowsError(try store.allocate())
        XCTAssertTrue(FileManager.default.fileExists(atPath: owned.path))
        try failure.clear()
        await scheduler.runAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testCleanupRecoveryCapacityRejectsBeforeCreatingSixtyFifthOwnedDirectory() async throws {
        let root = URL(fileURLWithPath: "/task-seven-recovery-capacity-root", isDirectory: true)
        let identifiers = (0..<65).map { offset in
            UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", 200 + offset))!
        }
        let scheduler = ManualCleanupScheduler()
        let registry = ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        let fileSystem = ExportTemporaryFileSystemSpy()
        fileSystem.remainingRemovalFailures = 1_000_000
        let store = ReportExportTemporaryStore(
            rootDirectory: root,
            fileSystem: fileSystem,
            makeDirectoryID: sequence(identifiers),
            cleanupRegistry: registry
        )

        for _ in 0..<64 {
            let token = try store.allocate().makeArtifactToken(shareURLs: [])
            XCTAssertFalse(token.cleanup())
            for _ in 0..<8 { await scheduler.runNextBatch() }
        }
        let creationsBeforeCapacityFailure = fileSystem.exclusiveDirectoryCreationCount

        XCTAssertThrowsError(try store.allocate())
        XCTAssertEqual(
            fileSystem.exclusiveDirectoryCreationCount,
            creationsBeforeCapacityFailure
        )
        XCTAssertEqual(identifiers.prefix(64).filter {
            fileSystem.exists(at: root.appendingPathComponent(
                $0.uuidString.lowercased(),
                isDirectory: true
            ))
        }.count, 64)
    }

    func testViewModelDefaultsEightModulesPhotoResetAndSelectionSurvivesFailureRetryAndCleanup() async throws {
        let firstToken = ExportArtifactToken(shareURLs: [temporaryDirectory.appendingPathComponent("first.json")]) {}
        let secondToken = ExportArtifactToken(shareURLs: [temporaryDirectory.appendingPathComponent("second.json")]) {}
        let generator = QueuedExportGenerator(results: [
            .failure(FixtureError.generationFailed), .success(firstToken), .success(secondToken),
        ])
        let viewModel = ReportExportViewModel(
            generator: generator,
            calendar: utcCalendar(),
            progressDelay: { try await Task.sleep(nanoseconds: 10_000_000_000) }
        )
        XCTAssertEqual(viewModel.selectedModules, Set(ExportModuleV1.allCases))
        XCTAssertEqual(viewModel.selectedModules.count, 8)
        XCTAssertEqual(viewModel.format, .csv)
        XCTAssertFalse(viewModel.includesPhotos)

        viewModel.setFormat(.bothZip)
        viewModel.setIncludesPhotos(true)
        viewModel.toggleModule(.health)
        let preservedModules = viewModel.selectedModules
        viewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_599))
        await viewModel.waitForCurrentGeneration()
        XCTAssertEqual(viewModel.state, .failed)
        XCTAssertTrue(viewModel.canRetry)
        XCTAssertEqual(viewModel.selectedModules, preservedModules)
        XCTAssertEqual(viewModel.format, .bothZip)
        XCTAssertTrue(viewModel.includesPhotos)

        viewModel.retry()
        await viewModel.waitForCurrentGeneration()
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.shareURLs, firstToken.shareURLs)
        viewModel.shareDidFinish(completed: false)
        XCTAssertEqual(firstToken.cleanupCallCount, 1)
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.selectedModules, preservedModules)

        viewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_599))
        await viewModel.waitForCurrentGeneration()
        viewModel.viewDidDisappear()
        XCTAssertEqual(secondToken.cleanupCallCount, 1)
        viewModel.setFormat(.json)
        XCTAssertFalse(viewModel.includesPhotos)
    }

    func testViewModelDelayedProgressCancellationAndSupersessionIgnoreStaleCompletion() async throws {
        let oldToken = ExportArtifactToken(shareURLs: [temporaryDirectory.appendingPathComponent("old.zip")]) {}
        let newToken = ExportArtifactToken(shareURLs: [temporaryDirectory.appendingPathComponent("new.zip")]) {}
        let generator = SuspendedExportGenerator()
        let delay = ProgressDelayGate()
        let viewModel = ReportExportViewModel(
            generator: generator,
            calendar: utcCalendar(),
            progressDelay: { try await delay.wait() }
        )

        viewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_599))
        await generator.waitUntilCallCount(1)
        XCTAssertFalse(viewModel.isProgressVisible)
        await delay.resumeAll()
        await waitUntil { viewModel.isProgressVisible }
        viewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_599))
        await generator.waitUntilCallCount(2)
        generator.resume(call: 2, with: .success(newToken))
        await viewModel.waitForCurrentGeneration()
        XCTAssertEqual(viewModel.shareURLs, newToken.shareURLs)
        XCTAssertFalse(viewModel.isProgressVisible)

        generator.resume(call: 1, with: .success(oldToken))
        await waitUntil { oldToken.cleanupCallCount == 1 }
        XCTAssertEqual(viewModel.shareURLs, newToken.shareURLs)
        XCTAssertEqual(newToken.cleanupCallCount, 0)

        viewModel.cancel()
        XCTAssertEqual(newToken.cleanupCallCount, 1)
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(viewModel.isProgressVisible)
    }

    func testViewModelFormatChangeInvalidatesInFlightPhotoZIPAndCleansStaleCompletion() async throws {
        let staleToken = ExportArtifactToken(
            shareURLs: [temporaryDirectory.appendingPathComponent("stale-photos.zip")]
        ) {}
        let generator = SuspendedExportGenerator()
        let viewModel = ReportExportViewModel(
            generator: generator,
            calendar: utcCalendar(),
            progressDelay: { try await Task.sleep(nanoseconds: 10_000_000_000) }
        )
        viewModel.setFormat(.bothZip)
        viewModel.setIncludesPhotos(true)
        viewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_599))
        await generator.waitUntilCallCount(1)

        XCTAssertEqual(generator.requests.first?.format, .bothZip)
        XCTAssertEqual(generator.requests.first?.includesPhotos, true)
        XCTAssertEqual(viewModel.state, .generating)

        viewModel.setFormat(.json)

        XCTAssertEqual(viewModel.format, .json)
        XCTAssertFalse(viewModel.includesPhotos)
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.shareURLs, [])
        XCTAssertFalse(viewModel.isProgressVisible)

        generator.resume(call: 1, with: .success(staleToken))
        await waitUntil { staleToken.cleanupCallCount == 1 }

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.shareURLs, [])
        XCTAssertEqual(generator.callCount, 1)
    }

    func testViewModelModuleChangeCleansReadyArtifactAndRequiresExplicitRegeneration() async throws {
        let readyToken = ExportArtifactToken(
            shareURLs: [temporaryDirectory.appendingPathComponent("ready.json")]
        ) {}
        let generator = QueuedExportGenerator(results: [.success(readyToken)])
        let viewModel = ReportExportViewModel(
            generator: generator,
            calendar: utcCalendar(),
            progressDelay: { try await Task.sleep(nanoseconds: 10_000_000_000) }
        )
        viewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_599))
        await viewModel.waitForCurrentGeneration()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertTrue(viewModel.selectedModules.contains(.health))
        XCTAssertEqual(generator.requests.count, 1)

        viewModel.setFormat(.csv)
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(readyToken.cleanupCallCount, 0)

        viewModel.toggleModule(.health)

        XCTAssertFalse(viewModel.selectedModules.contains(.health))
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.shareURLs, [])
        XCTAssertEqual(readyToken.cleanupCallCount, 1)
        XCTAssertEqual(generator.requests.count, 1)
        XCTAssertTrue(viewModel.canGenerate)
    }

    func testViewModelDropsPermanentlyFailingTokensAfterRegistryHandoffAndRemainsResponsive() async throws {
        let scheduler = ManualCleanupScheduler()
        let registry = ReportExportLifetimeCleanupRegistry(scheduler: scheduler)
        let generator = RegistryHandoffCleanupGenerator(registry: registry)
        let viewModel = ReportExportViewModel(
            generator: generator,
            calendar: utcCalendar(),
            selectedModules: [.metrics],
            format: .json,
            progressDelay: { try await Task.sleep(nanoseconds: 10_000_000_000) }
        )

        for expectedCount in 1...12 {
            viewModel.generate(referenceDate: Date(timeIntervalSince1970: 1_706_745_599))
            await viewModel.waitForCurrentGeneration()
            XCTAssertEqual(viewModel.state, .ready)
            viewModel.shareDidFinish(completed: true)
            await waitUntil { generator.cleanupHandoffCount >= expectedCount }
        }
        for _ in 0..<200 where generator.liveTokenCount > 1 {
            await Task.yield()
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        viewModel.setPreset(.threeMonths)
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        XCTAssertLessThan(elapsed, 400_000_000)
        XCTAssertLessThanOrEqual(generator.liveTokenCount, 1)
        XCTAssertLessThanOrEqual(scheduler.pendingCount, 64)
        XCTAssertEqual(viewModel.state, .idle)
    }

    private func interval() -> ReportDateInterval {
        ReportDateInterval(
            start: Date(timeIntervalSince1970: 1_704_067_200),
            endExclusive: Date(timeIntervalSince1970: 1_706_745_600)
        )
    }

    private func emptySnapshot(modules: Set<ExportModuleV1>) throws -> ExportSnapshotV1 {
        try ExportSnapshotV1(
            interval: interval(),
            selectedModules: modules,
            tables: ExportModuleV1.allCases.filter(modules.contains).map {
                try ExportTableV1(module: $0, columns: ExportSchemaV1.columns(for: $0), rows: [])
            }
        )
    }

    private func photoSnapshot(_ fixtures: [(UUID, Bool, String?)]) throws -> ExportSnapshotV1 {
        let columns = ExportSchemaV1.columns(for: .photos)
        let rows = try fixtures.enumerated().map { index, fixture in
            let timestamp = Date(timeIntervalSince1970: 1_704_067_300 + Double(index))
            let cells = columns.map { column -> ExportNamedCellV1 in
                let value: ExportCellV1
                switch column.name {
                case "record_type": value = .text("progress_photo")
                case "id": value = .uuid(fixture.0)
                case "created_at", "updated_at", "progress_photo_date": value = .timestamp(timestamp)
                case "config_scope": value = .null
                case "progress_photo_image_available": value = .boolean(fixture.1)
                case "progress_photo_pose": value = .text("front")
                case "progress_photo_note": value = fixture.2.map(ExportCellV1.text) ?? .null
                default: value = .null
                }
                return .init(columnName: column.name, value: value)
            }
            return try ExportRowV1(primaryTimestamp: timestamp, cells: cells)
        }
        let table = try ExportTableV1(module: .photos, columns: columns, rows: rows)
        return try ExportSnapshotV1(
            interval: interval(), selectedModules: [.photos], tables: [table]
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func assertGenerationError(
        _ coordinator: ReportExportCoordinator,
        request: ReportExportRequest,
        expected: ReportExportError
    ) async {
        do {
            _ = try await coordinator.generate(request)
            XCTFail("Expected \(expected)")
        } catch let error as ReportExportError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func extractStoredZIP(_ data: Data) throws -> [String: Data] {
        let eocd = try XCTUnwrap(findSignature(0x0605_4b50, in: data, searchingBackward: true))
        let count = Int(try uint16(data, eocd + 10))
        var central = Int(try uint32(data, eocd + 16))
        var payloads: [String: Data] = [:]
        for _ in 0..<count {
            XCTAssertEqual(try uint32(data, central), 0x0201_4b50)
            let size = Int(try uint32(data, central + 24))
            let nameLength = Int(try uint16(data, central + 28))
            let extraLength = Int(try uint16(data, central + 30))
            let commentLength = Int(try uint16(data, central + 32))
            let localOffset = Int(try uint32(data, central + 42))
            let nameData = data.subdata(in: (central + 46)..<(central + 46 + nameLength))
            let name = try XCTUnwrap(String(data: nameData, encoding: .utf8))
            XCTAssertEqual(try uint32(data, localOffset), 0x0403_4b50)
            let localNameLength = Int(try uint16(data, localOffset + 26))
            let localExtraLength = Int(try uint16(data, localOffset + 28))
            let payloadStart = localOffset + 30 + localNameLength + localExtraLength
            payloads[name] = data.subdata(in: payloadStart..<(payloadStart + size))
            central += 46 + nameLength + extraLength + commentLength
        }
        return payloads
    }

    private func findSignature(_ signature: UInt32, in data: Data, searchingBackward: Bool) -> Int? {
        guard data.count >= 4 else { return nil }
        let offsets = searchingBackward
            ? Array(stride(from: data.count - 4, through: 0, by: -1))
            : Array(0...(data.count - 4))
        return offsets.first { (try? uint32(data, $0)) == signature }
    }

    private func uint16(_ data: Data, _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { throw FixtureError.malformedZIP }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func uint32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw FixtureError.malformedZIP }
        return (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << UInt32($1 * 8) }
    }

    private func sequence(_ values: [UUID]) -> @Sendable () -> UUID {
        let sequence = LockedUUIDSequence(values)
        return { sequence.next() }
    }

    private func ownedChildren(of root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { UUID(uuidString: $0.lastPathComponent) != nil }
    }

    private func uuidPartialArtifacts(named outputName: String, in directory: URL) throws -> [URL] {
        let prefix = ".\(outputName)."
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ).filter { candidate in
            let name = candidate.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(".partial") else { return false }
            let start = name.index(name.startIndex, offsetBy: prefix.count)
            let end = name.index(name.endIndex, offsetBy: -".partial".count)
            return UUID(uuidString: String(name[start..<end])) != nil
        }
    }

    private func ownerAndPermissions(of url: URL) throws -> (owner: uid_t, permissions: mode_t) {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return (status.st_uid, status.st_mode & mode_t(0o777))
    }

    private func moveIsRejectedAndRestoreIfNeeded(_ source: URL, to destination: URL) throws -> Bool {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            try FileManager.default.moveItem(at: destination, to: source)
            return false
        } catch {
            if FileManager.default.fileExists(atPath: destination.path),
               !FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.moveItem(at: destination, to: source)
            }
            return true
        }
    }

    private func waitUntil(
        attempts: Int = 200,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not reached")
    }
}

private func setPrivateNamespaceProtection(_ enabled: Bool, at url: URL) throws {
    var status = stat()
    guard Darwin.lstat(url.path, &status) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let protection = UInt32(UF_APPEND | UF_IMMUTABLE)
    let flags = enabled
        ? status.st_flags | protection
        : status.st_flags & ~protection
    guard Darwin.chflags(url.path, flags) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

@MainActor
private final class ExportRepositorySpy: ReportsExportRepository {
    let snapshot: ExportSnapshotV1
    private(set) var fetchCount = 0
    private(set) var intervals: [ReportDateInterval] = []
    private(set) var moduleSelections: [Set<ExportModuleV1>] = []

    init(snapshot: ExportSnapshotV1) { self.snapshot = snapshot }

    func fetchExportSnapshot(
        in interval: ReportDateInterval,
        modules: Set<ExportModuleV1>
    ) async throws -> ExportSnapshotV1 {
        fetchCount += 1
        intervals.append(interval)
        moduleSelections.append(modules)
        return snapshot
    }
}

private actor ExportPhotoProviderSpy: ReportExportPhotoByteProviding {
    let results: [UUID: ReportExportPhotoPayloadV1]
    let error: Error?
    private(set) var requestedIDs: [UUID] = []

    init(results: [UUID: ReportExportPhotoPayloadV1] = [:], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func jpegData(for photoID: UUID) async throws -> ReportExportPhotoPayloadV1 {
        requestedIDs.append(photoID)
        if let error { throw error }
        return results[photoID] ?? .missing
    }
}

private actor SuspendedExportPhotoProvider: ReportExportPhotoByteProviding {
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<ReportExportPhotoPayloadV1, Error>?

    func jpegData(for photoID: UUID) async throws -> ReportExportPhotoPayloadV1 {
        requestContinuation?.resume()
        requestContinuation = nil
        return try await withCheckedThrowingContinuation { resultContinuation = $0 }
    }

    func waitUntilRequested() async {
        if resultContinuation != nil { return }
        await withCheckedContinuation { requestContinuation = $0 }
    }

    func resume(_ result: ReportExportPhotoPayloadV1) {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}

private actor OneShotPhotoPayloadProvider: ReportExportPhotoByteProviding {
    private var payload: Data?

    init(payload: Data) { self.payload = payload }

    func jpegData(for photoID: UUID) async throws -> ReportExportPhotoPayloadV1 {
        guard let result = payload else { throw FixtureError.oneShotPayloadWasReused }
        payload = nil
        return .available(result)
    }
}

private final class PayloadDeallocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var didRelease = false

    var isReleased: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didRelease
    }

    func markReleased() {
        lock.lock()
        didRelease = true
        lock.unlock()
    }
}

private func trackedJPEGData(lifetime: PayloadDeallocationRecorder) -> Data {
    let byteCount = 4_096
    let pointer = UnsafeMutableRawPointer.allocate(
        byteCount: byteCount,
        alignment: MemoryLayout<UInt8>.alignment
    )
    pointer.initializeMemory(as: UInt8.self, repeating: 0x5a, count: byteCount)
    pointer.storeBytes(of: UInt8(0xff), toByteOffset: 0, as: UInt8.self)
    pointer.storeBytes(of: UInt8(0xd8), toByteOffset: 1, as: UInt8.self)
    pointer.storeBytes(of: UInt8(0xff), toByteOffset: byteCount - 2, as: UInt8.self)
    pointer.storeBytes(of: UInt8(0xd9), toByteOffset: byteCount - 1, as: UInt8.self)
    return Data(bytesNoCopy: pointer, count: byteCount, deallocator: .custom { pointer, _ in
        pointer.deallocate()
        lifetime.markReleased()
    })
}

private final class PayloadLifetimeObservationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStates: [Bool] = []

    var releaseStates: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStates
    }

    func record(released: Bool) {
        lock.lock()
        recordedStates.append(released)
        lock.unlock()
    }
}

private final class ArtifactLifecycleBlockingGate: @unchecked Sendable {
    enum Boundary: Equatable, Sendable {
        case markerPublication
        case payloadWrite
        case recursiveCleanup
    }

    private let lock = NSLock()
    private let boundary: Boundary
    private let delayMicroseconds: useconds_t
    private var didStart = false
    private var didBlock = false

    init(
        boundary: Boundary,
        delayMicroseconds: useconds_t
    ) {
        self.boundary = boundary
        self.delayMicroseconds = delayMicroseconds
    }

    func block(_ observedBoundary: Boundary) {
        guard observedBoundary == boundary else { return }
        lock.lock()
        let shouldBlock = !didBlock
        didBlock = true
        didStart = true
        lock.unlock()
        if shouldBlock { usleep(delayMicroseconds) }
    }

    func waitUntilStarted() async -> Bool {
        for _ in 0..<2_000 {
            if hasStarted { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    private var hasStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didStart
    }
}

private final class LifecycleBlockingTemporaryFileSystem:
    ReportExportDescriptorTemporaryFileSystem, @unchecked Sendable {
    private let base = FileManagerReportExportTemporaryFileSystem()
    private let gate: ArtifactLifecycleBlockingGate

    init(gate: ArtifactLifecycleBlockingGate) { self.gate = gate }

    var descriptorBackend: FileManagerReportExportTemporaryFileSystem { base }

    func reachDescriptorBoundary(_ boundary: ReportExportDescriptorBoundary) throws {
        switch boundary {
        case .markerPublication: gate.block(.markerPublication)
        case .payloadWrite: gate.block(.payloadWrite)
        case .recursiveCleanup: gate.block(.recursiveCleanup)
        case .markerRead, .allocationDirectoryCreated, .allocationDirectorySecured,
             .payloadStageCreated, .payloadStageBeforeUnlink, .recursiveEntryMetadata,
             .recursiveEntryOpened, .recursiveEntryBeforeUnlink: break
        }
    }

    func createRootDirectory(at url: URL) throws { try base.createRootDirectory(at: url) }
    func createExclusiveDirectory(at url: URL) throws { try base.createExclusiveDirectory(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func applyCompleteFileProtection(at url: URL) throws {
        try base.applyCompleteFileProtection(at: url)
    }
    func excludeFromBackup(at url: URL) throws { try base.excludeFromBackup(at: url) }
    func canonicalURL(for url: URL) throws -> URL { try base.canonicalURL(for: url) }
    func isSymbolicLink(at url: URL) throws -> Bool { try base.isSymbolicLink(at: url) }
    func fileIdentity(at url: URL) throws -> ReportExportFileIdentity? {
        try base.fileIdentity(at: url)
    }
    func exists(at url: URL) -> Bool { base.exists(at: url) }

    func writeAtomically(_ data: Data, to url: URL) throws {
        gate.block(url.lastPathComponent == ".allocation-id" ? .markerPublication : .payloadWrite)
        try base.writeAtomically(data, to: url)
    }

    func read(_ url: URL) throws -> Data { try base.read(url) }

    func removeItemIfExists(at url: URL) throws {
        if UUID(uuidString: url.lastPathComponent) != nil {
            gate.block(.recursiveCleanup)
        }
        try base.removeItemIfExists(at: url)
    }
}

private final class BoundaryRaceTemporaryFileSystem:
    ReportExportDescriptorTemporaryFileSystem, @unchecked Sendable {
    enum Boundary: Equatable {
        case allocationDirectoryCreated
        case allocationDirectorySecured
        case markerRead
        case payloadWrite
        case payloadStageCreated
        case payloadStageBeforeUnlink
        case recursiveCleanup
        case recursiveEntryMetadata
        case recursiveEntryOpened
        case recursiveEntryBeforeUnlink
    }

    private let base = FileManagerReportExportTemporaryFileSystem()
    private let lock = NSLock()
    private var armedBoundary: Boundary?
    private var armedAction: (@Sendable () throws -> Void)?

    var descriptorBackend: FileManagerReportExportTemporaryFileSystem { base }

    func reachDescriptorBoundary(_ boundary: ReportExportDescriptorBoundary) throws {
        switch boundary {
        case .allocationDirectoryCreated: try runIfArmed(.allocationDirectoryCreated)
        case .allocationDirectorySecured: try runIfArmed(.allocationDirectorySecured)
        case .markerRead: try runIfArmed(.markerRead)
        case .payloadWrite: try runIfArmed(.payloadWrite)
        case .payloadStageCreated: try runIfArmed(.payloadStageCreated)
        case .payloadStageBeforeUnlink: try runIfArmed(.payloadStageBeforeUnlink)
        case .recursiveCleanup: try runIfArmed(.recursiveCleanup)
        case .recursiveEntryMetadata: try runIfArmed(.recursiveEntryMetadata)
        case .recursiveEntryOpened: try runIfArmed(.recursiveEntryOpened)
        case .recursiveEntryBeforeUnlink: try runIfArmed(.recursiveEntryBeforeUnlink)
        case .markerPublication: break
        }
    }

    func arm(_ boundary: Boundary, action: @escaping @Sendable () throws -> Void) {
        lock.lock()
        armedBoundary = boundary
        armedAction = action
        lock.unlock()
    }

    func createRootDirectory(at url: URL) throws { try base.createRootDirectory(at: url) }
    func createExclusiveDirectory(at url: URL) throws { try base.createExclusiveDirectory(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func applyCompleteFileProtection(at url: URL) throws {
        try base.applyCompleteFileProtection(at: url)
    }
    func excludeFromBackup(at url: URL) throws { try base.excludeFromBackup(at: url) }
    func canonicalURL(for url: URL) throws -> URL { try base.canonicalURL(for: url) }
    func isSymbolicLink(at url: URL) throws -> Bool { try base.isSymbolicLink(at: url) }
    func fileIdentity(at url: URL) throws -> ReportExportFileIdentity? {
        try base.fileIdentity(at: url)
    }
    func exists(at url: URL) -> Bool { base.exists(at: url) }

    func writeAtomically(_ data: Data, to url: URL) throws {
        if url.lastPathComponent != ".allocation-id" {
            try runIfArmed(.payloadWrite)
        }
        try base.writeAtomically(data, to: url)
    }

    func read(_ url: URL) throws -> Data {
        let data = try base.read(url)
        if url.lastPathComponent == ".allocation-id" {
            try runIfArmed(.markerRead)
        }
        return data
    }

    func removeItemIfExists(at url: URL) throws { try base.removeItemIfExists(at: url) }

    private func runIfArmed(_ boundary: Boundary) throws {
        lock.lock()
        let action = armedBoundary == boundary ? armedAction : nil
        if action != nil {
            armedBoundary = nil
            armedAction = nil
        }
        lock.unlock()
        try action?()
    }
}

private final class PayloadStageReplacementProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let directory: URL
    private let outputName: String
    private let replacementBytes: Data
    private let parkedURL: URL
    private var attempted = false
    private var rejected = false
    private var replaced = false
    private var storedVisibleURL: URL?

    init(directory: URL, outputName: String, replacementBytes: Data) {
        self.directory = directory
        self.outputName = outputName
        self.replacementBytes = replacementBytes
        parkedURL = directory.appendingPathComponent("parked-payload-stage")
    }

    var didAttempt: Bool {
        lock.lock()
        defer { lock.unlock() }
        return attempted
    }

    var moveWasRejected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rejected
    }

    var didReplace: Bool {
        lock.lock()
        defer { lock.unlock() }
        return replaced
    }

    var replacementURL: URL {
        lock.lock()
        defer { lock.unlock() }
        return storedVisibleURL
            ?? directory.appendingPathComponent(".missing-payload-stage")
    }

    var parkedExists: Bool {
        FileManager.default.fileExists(atPath: parkedURL.path)
    }

    func attemptReplacement() throws {
        lock.lock()
        attempted = true
        lock.unlock()
        do {
            let visibleURL = directory.appendingPathComponent(visibleName)
            lock.lock()
            storedVisibleURL = visibleURL
            lock.unlock()
            try FileManager.default.moveItem(at: visibleURL, to: parkedURL)
            try replacementBytes.write(to: visibleURL, options: .withoutOverwriting)
            lock.lock()
            replaced = true
            lock.unlock()
        } catch {
            lock.lock()
            rejected = true
            lock.unlock()
        }
    }

    private var visibleName: String {
        let prefix = ".\(outputName)."
        guard let name = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
            .first(where: { candidate in
                guard candidate.hasPrefix(prefix), candidate.hasSuffix(".partial") else {
                    return false
                }
                let start = candidate.index(candidate.startIndex, offsetBy: prefix.count)
                let end = candidate.index(candidate.endIndex, offsetBy: -".partial".count)
                return UUID(uuidString: String(candidate[start..<end])) != nil
            }) else {
            return ".missing-payload-stage"
        }
        return name
    }
}

private final class FilesystemMoveAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private var rejected = false
    private var becameVisibleOutside = false

    var wasRejected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rejected
    }

    var privateBytesBecameVisibleOutside: Bool {
        lock.lock()
        defer { lock.unlock() }
        return becameVisibleOutside
    }

    func attemptAndRestore(from source: URL, to destination: URL) {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            lock.lock()
            becameVisibleOutside = true
            lock.unlock()
            try FileManager.default.moveItem(at: destination, to: source)
        } catch {
            lock.lock()
            rejected = true
            lock.unlock()
            if FileManager.default.fileExists(atPath: destination.path),
               !FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.moveItem(at: destination, to: source)
            }
        }
    }
}

private final class AppendOnlyDirectoryFailure: @unchecked Sendable {
    private let directory: URL
    private let blockerName = ".fixture-cleanup-blocker"

    init(directory: URL) { self.directory = directory }

    func enableAndThrow() throws -> Never {
        let owned = try ownedDirectory()
        try setPrivateNamespaceProtection(false, at: owned)
        do {
            try Data().write(
                to: owned.appendingPathComponent(blockerName),
                options: .withoutOverwriting
            )
            try setPrivateNamespaceProtection(true, at: owned)
        } catch {
            try? setPrivateNamespaceProtection(true, at: owned)
            throw error
        }
        throw FixtureError.pathInspectionFailed
    }

    func clear() throws {
        let owned = try ownedDirectory()
        try setPrivateNamespaceProtection(false, at: owned)
        do {
            try FileManager.default.removeItem(
                at: owned.appendingPathComponent(blockerName)
            )
            try setPrivateNamespaceProtection(true, at: owned)
        } catch {
            try? setPrivateNamespaceProtection(true, at: owned)
            throw error
        }
    }

    private func ownedDirectory() throws -> URL {
        guard let owned = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).first(where: { UUID(uuidString: $0.lastPathComponent) != nil }) else {
            throw FixtureError.pathInspectionFailed
        }
        return owned
    }
}

private final class QuarantineMoveAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private let parent: URL
    let parkedURL: URL
    private var rejected = false
    private var becameVisible = false

    init(parent: URL, parked: URL) {
        self.parent = parent
        parkedURL = parked
    }

    var wasRejected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rejected
    }

    var privateEntryBecameVisible: Bool {
        lock.lock()
        defer { lock.unlock() }
        return becameVisible
    }

    func attempt() {
        do {
            let candidate = try FileManager.default.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: nil
            ).first { $0.lastPathComponent.hasPrefix(".cleanup-") }
            guard let candidate else { throw FixtureError.pathInspectionFailed }
            try FileManager.default.moveItem(at: candidate, to: parkedURL)
            lock.lock()
            becameVisible = true
            lock.unlock()
            try Data("non-owned-replacement".utf8).write(
                to: candidate,
                options: .withoutOverwriting
            )
        } catch {
            lock.lock()
            rejected = true
            lock.unlock()
        }
    }
}

private final class CleanupLifetimeProbe: @unchecked Sendable {}

private final class ExportTemporaryStoreSpy:
    ReportExportTemporaryStoring, @unchecked Sendable {
    let root: URL
    private let lock = NSLock()
    private var storedAllocationCount = 0
    private var storedCleanupCount = 0
    private var workspaceURLs: [URL] = []

    var allocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedAllocationCount
    }

    var cleanupCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCleanupCount
    }

    init(root: URL) { self.root = root }

    func allocate() throws -> ReportExportAllocation {
        lock.lock()
        storedAllocationCount += 1
        let allocationCount = storedAllocationCount
        lock.unlock()
        let directory = root.appendingPathComponent("workspace-\(allocationCount)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        lock.lock()
        workspaceURLs.append(directory)
        lock.unlock()
        return ReportExportAllocation(
            directoryURL: directory,
            write: { data, relativePath in
                let url = directory.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try data.write(to: url, options: .withoutOverwriting)
                return url
            },
            cleanup: { [weak self] in
                self?.recordCleanup()
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
            }
        )
    }

    func lastWorkspaceRelativePaths() throws -> [String] {
        lock.lock()
        let directory = workspaceURLs.last
        lock.unlock()
        guard let directory,
              FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        ))
        return enumerator.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.map {
            String($0.path.dropFirst(directory.path.count + 1))
        }.sorted()
    }

    private func recordCleanup() {
        lock.lock()
        storedCleanupCount += 1
        lock.unlock()
    }
}

private final class ExportTemporaryFileSystemSpy:
    ReportExportTemporaryFileSystem, @unchecked Sendable {
    var collisionIDs: Set<UUID> = []
    var backupExclusionFailureURL: URL?
    var failMarkerWriteAfterPartialPublication = false
    var remainingOwnedPathInspectionFailures = 0
    var remainingOwnedIdentityFailures = 0
    var remainingReadFailures = 0
    var remainingRemovalFailures = 0
    private(set) var exclusiveDirectoryCreationCount = 0
    private(set) var protectedURLs: [URL] = []
    private(set) var backupExcludedURLs: [URL] = []
    private(set) var removalAttempts: [URL] = []
    private(set) var removedURLs: [URL] = []
    private var directories: Set<URL> = []
    private var directoryIdentities: [URL: ReportExportFileIdentity] = [:]
    private var nextInode: UInt64 = 1
    private var files: [URL: Data] = [:]

    func createRootDirectory(at url: URL) throws {
        directories.insert(url)
        assignIdentityIfNeeded(to: url)
    }

    func createExclusiveDirectory(at url: URL) throws {
        exclusiveDirectoryCreationCount += 1
        if let id = UUID(uuidString: url.lastPathComponent), collisionIDs.remove(id) != nil {
            throw CocoaError(.fileWriteFileExists)
        }
        guard !directories.contains(url) else { throw CocoaError(.fileWriteFileExists) }
        directories.insert(url)
        assignIdentityIfNeeded(to: url)
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url)
        assignIdentityIfNeeded(to: url)
    }
    func applyCompleteFileProtection(at url: URL) throws { protectedURLs.append(url) }
    func excludeFromBackup(at url: URL) throws {
        backupExcludedURLs.append(url)
        if url == backupExclusionFailureURL { throw FixtureError.setupFailed }
    }
    func canonicalURL(for url: URL) throws -> URL { url.standardizedFileURL }
    func isSymbolicLink(at url: URL) throws -> Bool {
        if UUID(uuidString: url.lastPathComponent) != nil,
           remainingOwnedPathInspectionFailures > 0 {
            remainingOwnedPathInspectionFailures -= 1
            throw FixtureError.pathInspectionFailed
        }
        return false
    }
    func fileIdentity(at url: URL) throws -> ReportExportFileIdentity? {
        if UUID(uuidString: url.lastPathComponent) != nil,
           remainingOwnedIdentityFailures > 0 {
            remainingOwnedIdentityFailures -= 1
            return nil
        }
        return directoryIdentities[url]
    }
    func exists(at url: URL) -> Bool { directories.contains(url) || files[url] != nil }
    func writeAtomically(_ data: Data, to url: URL) throws {
        if failMarkerWriteAfterPartialPublication, url.lastPathComponent == ".allocation-id" {
            failMarkerWriteAfterPartialPublication = false
            files[url] = Data(data.prefix(max(1, data.count / 2)))
            throw FixtureError.markerWriteFailed
        }
        files[url] = data
    }
    func read(_ url: URL) throws -> Data {
        if remainingReadFailures > 0 {
            remainingReadFailures -= 1
            throw FixtureError.markerReadFailed
        }
        return try XCTUnwrap(files[url])
    }

    func removeItemIfExists(at url: URL) throws {
        removalAttempts.append(url)
        if remainingRemovalFailures > 0 {
            remainingRemovalFailures -= 1
            throw FixtureError.cleanupFailed
        }
        directories.remove(url)
        directoryIdentities = directoryIdentities.filter {
            !$0.key.path.hasPrefix(url.path)
        }
        files = files.filter { !$0.key.path.hasPrefix(url.path + "/") }
        removedURLs.append(url)
    }

    func replaceMarker(at directory: URL) {
        let marker = directory.appendingPathComponent(".allocation-id")
        files[marker] = Data(UUID().uuidString.lowercased().utf8)
    }

    func forceRemoveForReuse(at directory: URL) {
        directories.remove(directory)
        directoryIdentities = directoryIdentities.filter {
            !$0.key.path.hasPrefix(directory.path)
        }
        files = files.filter { !$0.key.path.hasPrefix(directory.path + "/") }
    }

    private func assignIdentityIfNeeded(to url: URL) {
        guard directoryIdentities[url] == nil else { return }
        directoryIdentities[url] = ReportExportFileIdentity(device: 1, inode: nextInode)
        nextInode += 1
    }
}

private final class ManualCleanupScheduler:
    ReportExportCleanupScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [@Sendable () -> Void] = []
    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return operations.count
    }

    func schedule(afterNanoseconds: UInt64, operation: @escaping @Sendable () -> Void) {
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

    func runAll() async {
        await runNextBatch()
    }
}

private final class LockedInteger: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

private final class CleanupRecoveryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var storedIsOpen = false

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedIsOpen
    }

    func open() {
        lock.lock()
        storedIsOpen = true
        lock.unlock()
    }
}

private final class LockedUUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) { self.values = values }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}

@MainActor
private final class QueuedExportGenerator: ReportExportGenerating {
    var results: [Result<ExportArtifactToken, Error>]
    private(set) var requests: [ReportExportRequest] = []
    init(results: [Result<ExportArtifactToken, Error>]) { self.results = results }
    func generate(_ request: ReportExportRequest) async throws -> ExportArtifactToken {
        requests.append(request)
        return try results.removeFirst().get()
    }
}

@MainActor
private final class SuspendedExportGenerator: ReportExportGenerating {
    private(set) var callCount = 0
    private(set) var requests: [ReportExportRequest] = []
    private var continuations: [Int: CheckedContinuation<ExportArtifactToken, Error>] = [:]

    func generate(_ request: ReportExportRequest) async throws -> ExportArtifactToken {
        callCount += 1
        requests.append(request)
        let call = callCount
        return try await withCheckedThrowingContinuation { continuations[call] = $0 }
    }

    func waitUntilCallCount(_ expected: Int) async {
        for _ in 0..<200 {
            if callCount >= expected { return }
            await Task.yield()
        }
        XCTFail("Generator did not reach call \(expected)")
    }

    func resume(call: Int, with result: Result<ExportArtifactToken, Error>) {
        continuations.removeValue(forKey: call)?.resume(with: result)
    }
}

@MainActor
private final class RegistryHandoffCleanupGenerator: ReportExportGenerating {
    private let registry: ReportExportLifetimeCleanupRegistry
    private var weakTokens: [WeakArtifactTokenBox] = []
    private(set) var cleanupHandoffCount = 0

    init(registry: ReportExportLifetimeCleanupRegistry) {
        self.registry = registry
    }

    var liveTokenCount: Int { weakTokens.filter { $0.value != nil }.count }

    func generate(_ request: ReportExportRequest) async throws -> ExportArtifactToken {
        _ = request
        let cleanupID = UUID()
        let directory = URL(fileURLWithPath: "/task-seven-view-model-cleanup/\(cleanupID)")
        let token = ExportArtifactToken(shareURLs: []) { [registry] in
            registry.retain(cleanupID: cleanupID, directory: directory) {
                throw FixtureError.cleanupFailed
            }
            Task { @MainActor [weak self] in self?.cleanupHandoffCount += 1 }
            throw FixtureError.cleanupFailed
        }
        weakTokens.append(WeakArtifactTokenBox(token))
        return token
    }
}

private final class WeakArtifactTokenBox: @unchecked Sendable {
    weak var value: ExportArtifactToken?
    init(_ value: ExportArtifactToken) { self.value = value }
}

private actor ProgressDelayGate {
    private var continuations: [CheckedContinuation<Void, Error>] = []
    func wait() async throws { try await withCheckedThrowingContinuation { continuations.append($0) } }
    func resumeAll() {
        let queued = continuations
        continuations.removeAll()
        queued.forEach { $0.resume() }
    }
}

private enum FixtureError: Error {
    case providerFailed
    case generationFailed
    case setupFailed
    case markerReadFailed
    case markerWriteFailed
    case pathInspectionFailed
    case oneShotPayloadWasReused
    case cleanupFailed
    case malformedZIP
}
