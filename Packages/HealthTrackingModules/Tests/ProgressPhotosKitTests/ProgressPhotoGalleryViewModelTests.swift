import CoreModels
import Foundation
import ProgressPhotosKit
import XCTest

@MainActor
final class ProgressPhotoGalleryViewModelTests: XCTestCase {
    func testLoadOrdersNewestDateThenFrontSideBackAndKeepsSafeAssetFallbacks() async {
        let sameDate = Date(timeIntervalSince1970: 2_000)
        let older = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000004",
            date: Date(timeIntervalSince1970: 1_000),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000104"
        )
        let front = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000001",
            date: sameDate,
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000101"
        )
        let side = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000002",
            date: sameDate,
            pose: .side,
            assetID: "00000000-0000-0000-0000-000000000102"
        )
        let back = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000003",
            date: sameDate,
            pose: .back,
            assetID: "00000000-0000-0000-0000-000000000103"
        )
        let repository = ProgressPhotoGalleryRepositoryFake(
            photos: [older, back, front, side],
            thumbnails: [
                front.imageRef: .available(Data([1])),
                side.imageRef: .missing,
                back.imageRef: .corrupt,
                older.imageRef: .available(Data([4])),
            ]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.items.map(\.snapshot.id), [front.id, side.id, back.id, older.id])
        XCTAssertEqual(viewModel.items.map(\.assetState), [
            .available(Data([1])),
            .missing,
            .corrupt,
            .available(Data([4])),
        ])
        XCTAssertEqual(repository.thumbnailRequests, [
            front.imageRef,
            side.imageRef,
            back.imageRef,
            older.imageRef,
        ])
    }

    func testIndividualThumbnailErrorKeepsMetadataRowAsUnavailableFallback() async {
        let snapshot = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000011",
            date: Date(timeIntervalSince1970: 3_000),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000111"
        )
        let repository = ProgressPhotoGalleryRepositoryFake(
            photos: [snapshot],
            thumbnailErrors: [snapshot.imageRef: FixtureGalleryError.protectedData]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.assetState, .unavailable)
    }

    func testComparisonAcceptsExactlyTwoAvailablePhotosAndOrdersOlderBeforeNewer() async {
        let older = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000021",
            date: Date(timeIntervalSince1970: 4_000),
            pose: .side,
            assetID: "00000000-0000-0000-0000-000000000121"
        )
        let middle = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000022",
            date: Date(timeIntervalSince1970: 5_000),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000122"
        )
        let newer = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000023",
            date: Date(timeIntervalSince1970: 6_000),
            pose: .back,
            assetID: "00000000-0000-0000-0000-000000000123"
        )
        let repository = ProgressPhotoGalleryRepositoryFake(
            photos: [older, middle, newer],
            thumbnails: [
                older.imageRef: .available(Data([1])),
                middle.imageRef: .available(Data([2])),
                newer.imageRef: .available(Data([3])),
            ]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)
        await viewModel.load()

        XCTAssertEqual(viewModel.toggleSelection(id: newer.id), .selected)
        XCTAssertEqual(viewModel.toggleSelection(id: older.id), .selected)
        XCTAssertEqual(viewModel.selectedPhotoIDs, [newer.id, older.id])
        XCTAssertEqual(viewModel.comparison?.before.snapshot.id, older.id)
        XCTAssertEqual(viewModel.comparison?.after.snapshot.id, newer.id)

        XCTAssertEqual(viewModel.toggleSelection(id: middle.id), .selectionLimitReached)
        XCTAssertEqual(viewModel.selectedPhotoIDs, [newer.id, older.id])
        XCTAssertEqual(viewModel.selectionNotice, .selectionLimitReached)

        XCTAssertEqual(viewModel.toggleSelection(id: newer.id), .deselected)
        XCTAssertNil(viewModel.comparison)
        XCTAssertEqual(viewModel.toggleSelection(id: middle.id), .selected)
        XCTAssertEqual(viewModel.comparison?.before.snapshot.id, older.id)
        XCTAssertEqual(viewModel.comparison?.after.snapshot.id, middle.id)
    }

    func testMissingCorruptUnknownAndUnavailablePhotosCannotBeSelected() async {
        let missing = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000031",
            date: Date(timeIntervalSince1970: 7_000),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000131"
        )
        let corrupt = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000032",
            date: Date(timeIntervalSince1970: 7_001),
            pose: .side,
            assetID: "00000000-0000-0000-0000-000000000132"
        )
        let unavailable = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000033",
            date: Date(timeIntervalSince1970: 7_002),
            pose: .back,
            assetID: "00000000-0000-0000-0000-000000000133"
        )
        let repository = ProgressPhotoGalleryRepositoryFake(
            photos: [missing, corrupt, unavailable],
            thumbnails: [
                missing.imageRef: .missing,
                corrupt.imageRef: .corrupt,
            ],
            thumbnailErrors: [unavailable.imageRef: FixtureGalleryError.protectedData]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)
        await viewModel.load()

        XCTAssertEqual(viewModel.toggleSelection(id: missing.id), .assetUnavailable)
        XCTAssertEqual(viewModel.toggleSelection(id: corrupt.id), .assetUnavailable)
        XCTAssertEqual(viewModel.toggleSelection(id: unavailable.id), .assetUnavailable)
        XCTAssertEqual(viewModel.toggleSelection(id: UUID()), .unknownPhoto)
        XCTAssertTrue(viewModel.selectedPhotoIDs.isEmpty)
        XCTAssertNil(viewModel.comparison)
    }

    func testReloadPrunesDeletedOrNewlyUnavailableSelections() async {
        let first = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000041",
            date: Date(timeIntervalSince1970: 8_000),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000141"
        )
        let second = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000042",
            date: Date(timeIntervalSince1970: 9_000),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000142"
        )
        let repository = ProgressPhotoGalleryRepositoryFake(
            photos: [first, second],
            thumbnails: [
                first.imageRef: .available(Data([1])),
                second.imageRef: .available(Data([2])),
            ]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)
        await viewModel.load()
        _ = viewModel.toggleSelection(id: first.id)
        _ = viewModel.toggleSelection(id: second.id)

        repository.photos = [second]
        repository.thumbnails[second.imageRef] = .corrupt
        await viewModel.load()

        XCTAssertTrue(viewModel.selectedPhotoIDs.isEmpty)
        XCTAssertNil(viewModel.comparison)
        XCTAssertEqual(viewModel.items.map(\.snapshot.id), [second.id])
        XCTAssertEqual(viewModel.items.first?.assetState, .corrupt)
    }
}

private enum FixtureGalleryError: Error {
    case protectedData
}

@MainActor
private final class ProgressPhotoGalleryRepositoryFake: ProgressPhotoRepository {
    var photos: [ProgressPhotoSnapshot]
    var thumbnails: [String: PhotoAssetLoadResult]
    var thumbnailErrors: [String: Error]
    private(set) var thumbnailRequests: [String] = []
    var pendingAssetCleanupIDs: [String] { [] }

    init(
        photos: [ProgressPhotoSnapshot],
        thumbnails: [String: PhotoAssetLoadResult] = [:],
        thumbnailErrors: [String: Error] = [:]
    ) {
        self.photos = photos
        self.thumbnails = thumbnails
        self.thumbnailErrors = thumbnailErrors
    }

    func fetchPhotos() async throws -> [ProgressPhotoSnapshot] { photos }

    func importPhoto(
        _ input: ProgressPhotoInput,
        bytes: Data
    ) async throws -> ProgressPhotoSnapshot {
        throw FixtureGalleryError.protectedData
    }

    func thumbnail(assetID: String) async throws -> PhotoAssetLoadResult {
        thumbnailRequests.append(assetID)
        if let error = thumbnailErrors[assetID] { throw error }
        return thumbnails[assetID] ?? .missing
    }

    func deletePhoto(id: UUID, expectedUpdatedAt: Date) async throws {}
    func retryPendingAssetCleanup() async throws {}
}

private func fixtureSnapshot(
    id: String,
    date: Date,
    pose: ProgressPhotoPose,
    assetID: String
) -> ProgressPhotoSnapshot {
    ProgressPhotoSnapshot(
        id: UUID(uuidString: id)!,
        createdAt: date,
        updatedAt: date,
        date: date,
        imageRef: assetID,
        pose: pose,
        note: nil
    )
}
