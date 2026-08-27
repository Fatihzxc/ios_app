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

    func testMetadataSaveFailureDeletesImportedAssetAndRollsBackModel() async throws {
        let context = try makeContext()
        let assetID = "00000000-0000-0000-0000-000000000038"
        let assetStore = ProgressPhotoAssetStoreFake(
            importResults: [.success(.init(assetID: assetID))]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
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
        let assetStore = ProgressPhotoAssetStoreFake(
            importResults: [.success(.init(assetID: assetID))],
            deleteResults: [
                .failure(.protectedDataUnavailable),
                .success(()),
            ]
        )
        let repository = SwiftDataProgressPhotoRepository(
            modelContext: context,
            assetStore: assetStore,
            save: { throw FixtureError.save },
            rollback: { context.rollback() }
        )

        do {
            _ = try await repository.importPhoto(
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
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetID])

        try await repository.retryPendingAssetCleanup()
        XCTAssertTrue(repository.pendingAssetCleanupIDs.isEmpty)
        XCTAssertEqual(assetStore.deleteRequests, [assetID, assetID])
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
            assetStore: assetStore
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
            assetStore: assetStore
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
            assetStore: ProgressPhotoAssetStoreFake()
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
}

private enum FixtureError: Error {
    case save
}

@MainActor
private final class ProgressPhotoAssetStoreFake: PhotoAssetStoring {
    struct LoadRequest: Equatable {
        let id: String
        let variant: PhotoAssetVariant
    }

    var importResults: [Result<PhotoAssetReference, PhotoAssetStoreError>]
    var loadResults: [Result<PhotoAssetLoadResult, PhotoAssetStoreError>]
    var deleteResults: [Result<Void, PhotoAssetStoreError>]
    private(set) var importRequests: [Data] = []
    private(set) var loadRequests: [LoadRequest] = []
    private(set) var deleteRequests: [String] = []

    init(
        importResults: [Result<PhotoAssetReference, PhotoAssetStoreError>] = [],
        loadResults: [Result<PhotoAssetLoadResult, PhotoAssetStoreError>] = [],
        deleteResults: [Result<Void, PhotoAssetStoreError>] = []
    ) {
        self.importResults = importResults
        self.loadResults = loadResults
        self.deleteResults = deleteResults
    }

    func importAsset(_ bytes: Data) async throws -> PhotoAssetReference {
        importRequests.append(bytes)
        guard !importResults.isEmpty else { throw PhotoAssetStoreError.corruptInput }
        return try importResults.removeFirst().get()
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
        guard !deleteResults.isEmpty else { return }
        try deleteResults.removeFirst().get()
    }
}
