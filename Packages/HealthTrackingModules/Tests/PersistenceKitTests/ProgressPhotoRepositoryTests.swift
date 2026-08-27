import CoreModels
import Foundation
import ProgressPhotosKit
import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class ProgressPhotoRepositoryTests: XCTestCase {
    func testImportPersistsOnlyOpaqueAssetIDAndNormalizedMetadata() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000037"
        let assetStore = ProgressPhotoAssetStoreFake(
            importResults: [.success(.init(assetID: assetID))]
        )
        let timestamp = Date(timeIntervalSince1970: 300)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            now: { timestamp },
            makeID: { id }
        )
        let bytes = Data([0xde, 0xad, 0xbe, 0xef])
        let input = try ProgressPhotoInput(
            date: Date(timeIntervalSince1970: 200),
            pose: .side,
            note: "  Aylık kayıt  "
        )

        let snapshot = try await repository.importPhoto(input, bytes: bytes)

        XCTAssertEqual(assetStore.importRequests, [bytes])
        XCTAssertEqual(snapshot.id, id)
        XCTAssertEqual(snapshot.imageRef, assetID)
        XCTAssertEqual(snapshot.note, "Aylık kayıt")
        XCTAssertFalse(snapshot.imageRef.hasPrefix("/"))
        XCTAssertFalse(snapshot.imageRef.contains("file:"))
        let models = try context.fetch(FetchDescriptor<ProgressPhoto>())
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].imageRef, assetID)
        XCTAssertFalse(
            Mirror(reflecting: models[0]).children.contains { $0.value is Data },
            "SwiftData metadata must never persist photo binary data."
        )
    }

    func testThumbnailAndFullImageUseExplicitAssetVariants() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000036"
        let assetStore = ProgressPhotoAssetStoreFake(
            loadResults: [
                .success(.available(Data([1]))),
                .success(.available(Data([2]))),
            ]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )

        let thumbnail = try await repository.thumbnail(assetID: assetID)
        let fullImage = try await repository.fullImage(assetID: assetID)

        XCTAssertEqual(thumbnail, .available(Data([1])))
        XCTAssertEqual(fullImage, .available(Data([2])))
        XCTAssertEqual(assetStore.loadRequests, [
            .init(id: assetID, variant: .thumbnail),
            .init(id: assetID, variant: .full),
        ])
    }

    func testMetadataSaveFailureDeletesImportedAssetAndRollsBackModel() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000038"
        let assetStore = ProgressPhotoAssetStoreFake(
            importResults: [.success(.init(assetID: assetID))]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            save: { throw FixtureError.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.importPhoto(
                try ProgressPhotoInput(date: .now, pose: .front, note: nil),
                bytes: Data([1])
            )
            XCTFail("A metadata save failure must fail the import.")
        } catch {
            XCTAssertEqual(error as? ProgressPhotoRepositoryOperationError, .saveFailed)
        }

        XCTAssertEqual(assetStore.deleteRequests, [assetID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProgressPhoto>()).isEmpty)
    }

    func testProtectedCleanupFailureRemainsPendingUntilExactRetrySucceeds() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000039"
        let journal = PhotoAssetCleanupJournalFake()
        let firstAssetStore = ProgressPhotoAssetStoreFake(
            importResults: [.success(.init(assetID: assetID))],
            deleteResults: [.failure(.protectedDataUnavailable)]
        )
        let firstRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: firstAssetStore,
            cleanupJournal: journal,
            save: { throw FixtureError.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await firstRepository.importPhoto(
                try ProgressPhotoInput(date: .now, pose: .back, note: nil),
                bytes: Data([1])
            )
            XCTFail("The imported file still requires protected-data cleanup.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryOperationError,
                .metadataSaveFailedCleanupPending(assetID: assetID)
            )
        }
        XCTAssertEqual(firstRepository.pendingAssetCleanupIDs, [assetID])
        let persistedAfterFailure = try await journal.loadPendingAssetIDs()
        XCTAssertEqual(persistedAfterFailure, [assetID])

        let relaunchedAssetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [.success(())],
            localAssetIDs: [assetID]
        )
        let relaunchedRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: relaunchedAssetStore,
            cleanupJournal: journal
        )

        _ = try await relaunchedRepository.fetchPhotos()

        XCTAssertTrue(relaunchedRepository.pendingAssetCleanupIDs.isEmpty)
        let persistedAfterRelaunch = try await journal.loadPendingAssetIDs()
        XCTAssertEqual(persistedAfterRelaunch, [])
        XCTAssertEqual(firstAssetStore.deleteRequests, [assetID])
        XCTAssertEqual(relaunchedAssetStore.deleteRequests, [assetID])
    }

    func testJournalAndImmediateDeleteFailureQueuesOrphanForCurrentProcessRetry() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000066"
        let assetStore = ProgressPhotoAssetStoreFake(
            importResults: [.success(.init(assetID: assetID))],
            deleteResults: [
                .failure(.protectedDataUnavailable),
                .success(()),
            ]
        )
        let journal = PhotoAssetCleanupJournalFake(addError: FixtureError.save)
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: journal
        )

        do {
            _ = try await repository.importPhoto(
                try ProgressPhotoInput(date: .now, pose: .front, note: nil),
                bytes: Data([1])
            )
            XCTFail("An unjournaled asset must not report a successful import.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryOperationError,
                .cleanupJournalFailed(assetID: assetID)
            )
        }
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetID])
        XCTAssertEqual(assetStore.deleteRequests, [assetID])

        journal.addError = nil
        try await repository.retryPendingAssetCleanup()

        XCTAssertTrue(repository.pendingAssetCleanupIDs.isEmpty)
        XCTAssertEqual(assetStore.deleteRequests, [assetID, assetID])
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)
    }

    func testJournalAndDeleteCompensationFailureQueuesOrphanForRetry() async throws {
        let context = try makeContext()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000073")!
        let assetID = "00000000-0000-0000-0000-000000000067"
        let timestamp = Date(timeIntervalSince1970: 670)
        context.insert(
            ProgressPhoto(
                id: id,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [.success(())],
            localAssetIDs: [assetID]
        )
        let journal = PhotoAssetCleanupJournalFake(addError: FixtureError.save)
        var saveCallCount = 0
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: journal,
            save: {
                saveCallCount += 1
                if saveCallCount == 2 { throw FixtureError.save }
                try context.save()
            },
            rollback: { context.rollback() }
        )

        do {
            try await repository.deletePhoto(
                id: id,
                expectedUpdatedAt: timestamp
            )
            XCTFail("Failed metadata compensation must leave cleanup retryable.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryOperationError,
                .deleteCompensationFailed
            )
        }
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProgressPhoto>()).isEmpty)

        journal.addError = nil
        try await repository.retryPendingAssetCleanup()

        XCTAssertTrue(repository.pendingAssetCleanupIDs.isEmpty)
        XCTAssertEqual(assetStore.deleteRequests, [assetID])
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)
    }

    func testStartupReconciliationKeepsReferencedAssetAndDeletesCrashWindowOrphan() async throws {
        let context = try makeContext()
        let referencedID = "00000000-0000-0000-0000-000000000061"
        let orphanID = "00000000-0000-0000-0000-000000000062"
        let date = Date(timeIntervalSince1970: 620)
        context.insert(
            ProgressPhoto(
                id: UUID(),
                createdAt: date,
                updatedAt: date,
                date: date,
                imageRef: referencedID,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let journal = PhotoAssetCleanupJournalFake(
            pendingAssetIDs: [referencedID, orphanID]
        )
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [.success(())],
            localAssetIDs: [referencedID, orphanID]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: journal
        )

        let snapshots = try await repository.fetchPhotos()

        XCTAssertEqual(snapshots.map(\.imageRef), [referencedID])
        XCTAssertEqual(assetStore.deleteRequests, [orphanID])
        XCTAssertEqual(assetStore.localAssetIDs, [referencedID])
        let persistedAfterReconciliation = try await journal.loadPendingAssetIDs()
        XCTAssertEqual(persistedAfterReconciliation, [])
    }

    func testStartupInventoryDeletesUnjournaledOrphanFromRenameCrashWindow() async throws {
        let context = try makeContext()
        let orphanID = "00000000-0000-0000-0000-000000000063"
        let journal = PhotoAssetCleanupJournalFake()
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [.success(())],
            localAssetIDs: [orphanID]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: journal
        )

        _ = try await repository.fetchPhotos()

        XCTAssertEqual(assetStore.deleteRequests, [orphanID])
        XCTAssertTrue(assetStore.localAssetIDs.isEmpty)
        let persistedAfterReconciliation = try await journal.loadPendingAssetIDs()
        XCTAssertEqual(persistedAfterReconciliation, [])
    }

    func testInboundCloudAssetSurvivesOrphanCleanupAcrossMetadataCrashRelaunch() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000068"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let journalURL = directory.appendingPathComponent("cloud-inbound.json")
        let firstInboundJournal = FileCloudPhotoAssetInboundJournal(fileURL: journalURL)
        try await firstInboundJournal.recordInboundAssetID(assetID)
        let assetStore = ProgressPhotoAssetStoreFake(localAssetIDs: [assetID])
        let beforeMetadataRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            inboundAssetJournal: firstInboundJournal
        )

        let beforeMetadata = try await beforeMetadataRepository.fetchPhotos()
        let pendingBeforeMetadata = try await firstInboundJournal.loadInboundAssetIDs()

        XCTAssertTrue(beforeMetadata.isEmpty)
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)
        XCTAssertEqual(assetStore.localAssetIDs, [assetID])
        XCTAssertEqual(pendingBeforeMetadata, [assetID])

        let timestamp = Date(timeIntervalSince1970: 680)
        context.insert(
            ProgressPhoto(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000074")!,
                createdAt: timestamp,
                updatedAt: timestamp,
                date: timestamp,
                imageRef: assetID,
                pose: .front,
                note: nil
            )
        )
        try context.save()
        let recreatedInboundJournal = FileCloudPhotoAssetInboundJournal(fileURL: journalURL)
        let afterMetadataRepository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake(),
            inboundAssetJournal: recreatedInboundJournal
        )

        let afterMetadata = try await afterMetadataRepository.fetchPhotos()
        let pendingAfterMetadata = try await recreatedInboundJournal.loadInboundAssetIDs()

        XCTAssertEqual(afterMetadata.map(\.imageRef), [assetID])
        XCTAssertTrue(assetStore.deleteRequests.isEmpty)
        XCTAssertEqual(assetStore.localAssetIDs, [assetID])
        XCTAssertTrue(pendingAfterMetadata.isEmpty)
    }

    func testDuplicateImageReferenceFailsClosedBeforeEitherOwnerCanDelete() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000064"
        let timestamp = Date(timeIntervalSince1970: 640)
        let firstID = UUID()
        for id in [firstID, UUID()] {
            context.insert(
                ProgressPhoto(
                    id: id,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    date: timestamp,
                    imageRef: assetID,
                    pose: .front,
                    note: nil
                )
            )
        }
        try context.save()
        let assetStore = ProgressPhotoAssetStoreFake(localAssetIDs: [assetID])
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )

        do {
            try await repository.deletePhoto(
                id: firstID,
                expectedUpdatedAt: timestamp
            )
            XCTFail("Shared asset ownership must fail closed before deletion.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryIntegrityError,
                .duplicateImageRefs(assetID: assetID, count: 2)
            )
        }

        XCTAssertTrue(assetStore.deleteRequests.isEmpty)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ProgressPhoto>()).count,
            2
        )
    }

    func testReconciliationSerializesAConcurrentImportAcrossSuspension() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000065"
        let assetStore = InterleavingProgressPhotoAssetStore(assetID: assetID)
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )
        let input = try ProgressPhotoInput(
            date: Date(timeIntervalSince1970: 650),
            pose: .side,
            note: nil
        )

        let fetchTask = Task { try await repository.fetchPhotos() }
        await waitForInventoryCallCount(1, in: assetStore)

        let importStarted = expectation(description: "import task entered")
        let importTask = Task {
            importStarted.fulfill()
            return try await repository.importPhoto(input, bytes: Data([1]))
        }
        await fulfillment(of: [importStarted], timeout: 2)
        let suspendedCounts = await assetStore.callCounts()
        XCTAssertEqual(suspendedCounts.inventory, 1)
        XCTAssertEqual(suspendedCounts.imports, 0)

        await assetStore.resumeInventory(with: [])
        _ = try await fetchTask.value
        let imported = try await importTask.value

        XCTAssertEqual(imported.imageRef, assetID)
        let finalCounts = await assetStore.callCounts()
        XCTAssertEqual(finalCounts.imports, 1)
        XCTAssertTrue(finalCounts.deletes.isEmpty)
    }

    func testAssetDeleteFailureRestoresMetadataForExactRetry() async throws {
        let context = try makeContext()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000072")!
        let assetID = "00000000-0000-0000-0000-000000000040"
        let timestamp = Date(timeIntervalSince1970: 300)
        let model = ProgressPhoto(
            id: id,
            createdAt: timestamp,
            updatedAt: timestamp,
            date: timestamp,
            imageRef: assetID,
            pose: .front,
            note: nil
        )
        context.insert(model)
        try context.save()
        let assetStore = ProgressPhotoAssetStoreFake(
            deleteResults: [
                .failure(.protectedDataUnavailable),
                .success(()),
            ]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )

        do {
            try await repository.deletePhoto(id: id, expectedUpdatedAt: timestamp)
            XCTFail("File cleanup failure must compensate the metadata deletion.")
        } catch {
            XCTAssertEqual(
                error as? ProgressPhotoRepositoryOperationError,
                .protectedDataUnavailable
            )
        }
        let restored = try await repository.fetchPhotos()
        XCTAssertEqual(restored.map(\.id), [id])

        try await repository.deletePhoto(id: id, expectedUpdatedAt: timestamp)
        try await repository.deletePhoto(id: id, expectedUpdatedAt: timestamp)
        let deleted = try await repository.fetchPhotos()
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertEqual(assetStore.deleteRequests, [assetID, assetID])
    }

    func testThumbnailPassesThroughAvailableMissingAndCorruptFallbacks() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000041"
        let assetStore = ProgressPhotoAssetStoreFake(
            loadResults: [
                .success(.available(Data([1]))),
                .success(.missing),
                .success(.corrupt),
            ]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )

        let available = try await repository.thumbnail(assetID: assetID)
        let missing = try await repository.thumbnail(assetID: assetID)
        let corrupt = try await repository.thumbnail(assetID: assetID)
        XCTAssertEqual(available, .available(Data([1])))
        XCTAssertEqual(missing, .missing)
        XCTAssertEqual(corrupt, .corrupt)
        XCTAssertEqual(
            assetStore.loadRequests,
            [
                .init(id: assetID, variant: .thumbnail),
                .init(id: assetID, variant: .thumbnail),
                .init(id: assetID, variant: .thumbnail),
            ]
        )
    }

    func testAbsoluteOrMalformedPersistedImageRefFailsClosed() async throws {
        let context = try makeContext()
        context.insert(
            ProgressPhoto(
                id: UUID(),
                imageRef: "/private/var/mobile/photo.jpg",
                pose: .front
            )
        )
        try context.save()
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: ProgressPhotoAssetStoreFake(),
            cleanupJournal: PhotoAssetCleanupJournalFake()
        )

        do {
            _ = try await repository.fetchPhotos()
            XCTFail("Absolute paths must never cross the repository boundary.")
        } catch {
            guard let integrityError = error as? ProgressPhotoRepositoryIntegrityError,
                  case .invalidImageRef = integrityError else {
                return XCTFail("Expected an invalid opaque image reference, got \(error)")
            }
        }
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ProgressPhoto.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    private func waitForInventoryCallCount(
        _ expectedCount: Int,
        in store: InterleavingProgressPhotoAssetStore
    ) async {
        for _ in 0..<1_000 {
            if await store.callCounts().inventory >= expectedCount {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for the suspended inventory request.")
    }
}

private enum FixtureError: Error {
    case save
}

private final class ProgressPhotoAssetStoreFake:
    PhotoAssetStoring,
    @unchecked Sendable {
    struct LoadRequest: Equatable {
        let id: String
        let variant: PhotoAssetVariant
    }

    var importResults: [Result<PhotoAssetReference, PhotoAssetStoreError>]
    var loadResults: [Result<PhotoAssetLoadResult, PhotoAssetStoreError>]
    var deleteResults: [Result<Void, PhotoAssetStoreError>]
    var localAssetIDs: Set<String>
    private(set) var importRequests: [Data] = []
    private(set) var loadRequests: [LoadRequest] = []
    private(set) var deleteRequests: [String] = []

    init(
        importResults: [Result<PhotoAssetReference, PhotoAssetStoreError>] = [],
        loadResults: [Result<PhotoAssetLoadResult, PhotoAssetStoreError>] = [],
        deleteResults: [Result<Void, PhotoAssetStoreError>] = [],
        localAssetIDs: Set<String> = []
    ) {
        self.importResults = importResults
        self.loadResults = loadResults
        self.deleteResults = deleteResults
        self.localAssetIDs = localAssetIDs
    }

    func importAsset(_ bytes: Data) async throws -> PhotoAssetReference {
        importRequests.append(bytes)
        guard !importResults.isEmpty else { throw PhotoAssetStoreError.corruptInput }
        let reference = try importResults.removeFirst().get()
        localAssetIDs.insert(reference.assetID)
        return reference
    }

    func loadAsset(
        id: String,
        variant: PhotoAssetVariant
    ) async throws -> PhotoAssetLoadResult {
        loadRequests.append(.init(id: id, variant: variant))
        guard !loadResults.isEmpty else { return .missing }
        return try loadResults.removeFirst().get()
    }

    func deleteAsset(id: String) async throws {
        deleteRequests.append(id)
        if !deleteResults.isEmpty {
            try deleteResults.removeFirst().get()
        }
        localAssetIDs.remove(id)
    }

    func storedAssetIDs() async throws -> Set<String> { localAssetIDs }
}

private actor InterleavingProgressPhotoAssetStore: PhotoAssetStoring {
    private let assetID: String
    private var inventoryContinuations: [
        CheckedContinuation<Set<String>, Never>
    ] = []
    private var inventoryCalls = 0
    private var importCalls = 0
    private var deleteCalls: [String] = []

    init(assetID: String) {
        self.assetID = assetID
    }

    func importAsset(_ bytes: Data) async throws -> PhotoAssetReference {
        _ = bytes
        importCalls += 1
        return PhotoAssetReference(assetID: assetID)
    }

    func loadAsset(
        id: String,
        variant: PhotoAssetVariant
    ) async throws -> PhotoAssetLoadResult {
        _ = id
        _ = variant
        return .missing
    }

    func deleteAsset(id: String) async throws {
        deleteCalls.append(id)
    }

    func storedAssetIDs() async throws -> Set<String> {
        inventoryCalls += 1
        return await withCheckedContinuation { continuation in
            inventoryContinuations.append(continuation)
        }
    }

    func callCounts() -> (inventory: Int, imports: Int, deletes: [String]) {
        (inventoryCalls, importCalls, deleteCalls)
    }

    func resumeInventory(with ids: Set<String>) {
        let continuations = inventoryContinuations
        inventoryContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: ids)
        }
    }
}

private final class PhotoAssetCleanupJournalFake:
    PhotoAssetCleanupJournaling,
    @unchecked Sendable {
    private var pendingAssetIDs: Set<String>
    var addError: Error?

    init(
        pendingAssetIDs: Set<String> = [],
        addError: Error? = nil
    ) {
        self.pendingAssetIDs = pendingAssetIDs
        self.addError = addError
    }

    func loadPendingAssetIDs() async throws -> Set<String> {
        pendingAssetIDs
    }

    func addPendingAssetID(_ assetID: String) async throws {
        if let addError { throw addError }
        pendingAssetIDs.insert(assetID)
    }

    func removePendingAssetID(_ assetID: String) async throws {
        pendingAssetIDs.remove(assetID)
    }
}
