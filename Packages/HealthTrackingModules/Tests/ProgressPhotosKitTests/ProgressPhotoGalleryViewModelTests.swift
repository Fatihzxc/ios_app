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
            .unloaded,
            .unloaded,
            .unloaded,
            .unloaded,
        ])
        XCTAssertTrue(repository.thumbnailRequests.isEmpty)

        await viewModel.loadThumbnail(id: front.id)
        await viewModel.loadThumbnail(id: side.id)
        await viewModel.loadThumbnail(id: back.id)
        await viewModel.loadThumbnail(id: older.id)

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
        await viewModel.loadThumbnail(id: snapshot.id)

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.assetState, .unavailable)
    }

    func testThirdSelectionReplacesOldestChoiceAndOrdersComparisonChronologically() async {
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
        await viewModel.loadThumbnail(id: older.id)
        await viewModel.loadThumbnail(id: middle.id)
        await viewModel.loadThumbnail(id: newer.id)

        XCTAssertEqual(viewModel.toggleSelection(id: newer.id), .selected)
        XCTAssertEqual(viewModel.toggleSelection(id: older.id), .selected)
        XCTAssertEqual(viewModel.selectedPhotoIDs, [newer.id, older.id])
        XCTAssertEqual(viewModel.comparison?.before.snapshot.id, older.id)
        XCTAssertEqual(viewModel.comparison?.after.snapshot.id, newer.id)

        XCTAssertEqual(
            viewModel.toggleSelection(id: middle.id),
            .replacedOldest(removedID: newer.id)
        )
        XCTAssertEqual(viewModel.selectedPhotoIDs, [older.id, middle.id])
        XCTAssertEqual(
            viewModel.selectionNotice,
            .replacedOldest(removedID: newer.id)
        )
        XCTAssertEqual(viewModel.comparison?.before.snapshot.id, older.id)
        XCTAssertEqual(viewModel.comparison?.after.snapshot.id, middle.id)

        XCTAssertEqual(viewModel.toggleSelection(id: older.id), .deselected)
        XCTAssertNil(viewModel.comparison)
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
        await viewModel.loadThumbnail(id: missing.id)
        await viewModel.loadThumbnail(id: corrupt.id)
        await viewModel.loadThumbnail(id: unavailable.id)

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
        await viewModel.loadThumbnail(id: first.id)
        await viewModel.loadThumbnail(id: second.id)
        _ = viewModel.toggleSelection(id: first.id)
        _ = viewModel.toggleSelection(id: second.id)

        repository.photos = [second]
        repository.thumbnails[second.imageRef] = .corrupt
        await viewModel.load()
        await viewModel.loadThumbnail(id: second.id)

        XCTAssertTrue(viewModel.selectedPhotoIDs.isEmpty)
        XCTAssertNil(viewModel.comparison)
        XCTAssertEqual(viewModel.items.map(\.snapshot.id), [second.id])
        XCTAssertEqual(viewModel.items.first?.assetState, .corrupt)
    }

    func testLargeGalleryDefersEveryThumbnailAndLoadsFullImagesOnlyForCompare() async {
        let first = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000051",
            date: Date(timeIntervalSince1970: 10_000),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000151"
        )
        let second = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000052",
            date: Date(timeIntervalSince1970: 11_000),
            pose: .side,
            assetID: "00000000-0000-0000-0000-000000000152"
        )
        let filler = (0..<98).map { offset in
            fixtureSnapshot(
                id: String(
                    format: "00000000-0000-0000-0000-%012d",
                    200 + offset
                ),
                date: Date(timeIntervalSince1970: TimeInterval(12_000 + offset)),
                pose: .back,
                assetID: String(
                    format: "00000000-0000-0000-0001-%012d",
                    200 + offset
                )
            )
        }
        let repository = ProgressPhotoGalleryRepositoryFake(
            photos: [first, second] + filler,
            thumbnails: [
                first.imageRef: .available(Data([1])),
                second.imageRef: .available(Data([2])),
            ],
            fullImages: [
                first.imageRef: .available(Data([11])),
                second.imageRef: .available(Data([22])),
            ]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.items.count, 100)
        XCTAssertTrue(repository.thumbnailRequests.isEmpty)
        XCTAssertTrue(repository.fullImageRequests.isEmpty)

        await viewModel.loadThumbnail(id: first.id)
        await viewModel.loadThumbnail(id: second.id)
        _ = viewModel.toggleSelection(id: second.id)
        _ = viewModel.toggleSelection(id: first.id)

        XCTAssertTrue(repository.fullImageRequests.isEmpty)
        XCTAssertEqual(viewModel.comparison?.before.assetState, .unloaded)
        XCTAssertEqual(viewModel.comparison?.after.assetState, .unloaded)

        await viewModel.loadComparisonImages()

        XCTAssertEqual(repository.fullImageRequests, [second.imageRef, first.imageRef])
        XCTAssertEqual(viewModel.comparison?.before.assetState, .available(Data([11])))
        XCTAssertEqual(viewModel.comparison?.after.assetState, .available(Data([22])))
    }

    func testProtectedDataFallbackRetriesAfterUnlockWithoutReloadingMetadata() async {
        let snapshot = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000061",
            date: Date(timeIntervalSince1970: 12_000),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000161"
        )
        let repository = ProgressPhotoGalleryRepositoryFake(
            photos: [snapshot],
            thumbnails: [snapshot.imageRef: .available(Data([6]))],
            thumbnailErrors: [snapshot.imageRef: FixtureGalleryError.protectedData]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)
        await viewModel.load()
        await viewModel.loadThumbnail(id: snapshot.id)
        XCTAssertEqual(viewModel.items.first?.assetState, .unavailable)

        repository.thumbnailErrors.removeValue(forKey: snapshot.imageRef)
        await viewModel.retryUnavailableAssets()

        XCTAssertEqual(viewModel.items.first?.assetState, .available(Data([6])))
        XCTAssertEqual(
            repository.thumbnailRequests,
            [snapshot.imageRef, snapshot.imageRef]
        )
    }

    func testCompareFullImageFallbacksRetryProtectedDataWithoutThumbnailReuse() async {
        let first = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000062",
            date: Date(timeIntervalSince1970: 12_100),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000162"
        )
        let second = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000063",
            date: Date(timeIntervalSince1970: 12_200),
            pose: .side,
            assetID: "00000000-0000-0000-0000-000000000163"
        )
        let third = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000064",
            date: Date(timeIntervalSince1970: 12_300),
            pose: .back,
            assetID: "00000000-0000-0000-0000-000000000164"
        )
        let repository = ProgressPhotoGalleryRepositoryFake(
            photos: [first, second, third],
            thumbnails: [
                first.imageRef: .available(Data([1])),
                second.imageRef: .available(Data([2])),
                third.imageRef: .available(Data([3])),
            ],
            fullImages: [
                first.imageRef: .missing,
                second.imageRef: .corrupt,
                third.imageRef: .available(Data([33])),
            ],
            fullImageErrors: [
                third.imageRef: FixtureGalleryError.protectedData,
            ]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)
        await viewModel.load()
        await viewModel.loadThumbnail(id: first.id)
        await viewModel.loadThumbnail(id: second.id)
        await viewModel.loadThumbnail(id: third.id)

        _ = viewModel.toggleSelection(id: first.id)
        _ = viewModel.toggleSelection(id: second.id)
        await viewModel.loadComparisonImages()
        XCTAssertEqual(viewModel.comparison?.before.assetState, .missing)
        XCTAssertEqual(viewModel.comparison?.after.assetState, .corrupt)

        _ = viewModel.toggleSelection(id: first.id)
        _ = viewModel.toggleSelection(id: second.id)
        _ = viewModel.toggleSelection(id: first.id)
        _ = viewModel.toggleSelection(id: third.id)
        await viewModel.loadComparisonImages()
        XCTAssertEqual(viewModel.comparison?.before.assetState, .missing)
        XCTAssertEqual(viewModel.comparison?.after.assetState, .unavailable)

        repository.fullImageErrors.removeValue(forKey: third.imageRef)
        await viewModel.retryUnavailableAssets()
        XCTAssertEqual(viewModel.comparison?.before.assetState, .missing)
        XCTAssertEqual(viewModel.comparison?.after.assetState, .available(Data([33])))
    }

    func testSuccessfulSyncReloadsExactMissingAndCorruptGalleryStatesInOpenLifecycle() async throws {
        let thumbnailMissing = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000065",
            date: Date(timeIntervalSince1970: 12_400),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000165"
        )
        let thumbnailCorrupt = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000066",
            date: Date(timeIntervalSince1970: 12_500),
            pose: .side,
            assetID: "00000000-0000-0000-0000-000000000166"
        )
        let alreadyAvailable = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000067",
            date: Date(timeIntervalSince1970: 12_600),
            pose: .back,
            assetID: "00000000-0000-0000-0000-000000000167"
        )
        let comparisonMissing = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000068",
            date: Date(timeIntervalSince1970: 12_700),
            pose: .front,
            assetID: "00000000-0000-0000-0000-000000000168"
        )
        let comparisonCorrupt = fixtureSnapshot(
            id: "00000000-0000-0000-0000-000000000069",
            date: Date(timeIntervalSince1970: 12_800),
            pose: .side,
            assetID: "00000000-0000-0000-0000-000000000169"
        )
        let repository = ProgressPhotoGalleryRepositoryFake(
            photos: [
                thumbnailMissing,
                thumbnailCorrupt,
                alreadyAvailable,
                comparisonMissing,
                comparisonCorrupt,
            ],
            thumbnails: [
                thumbnailMissing.imageRef: .missing,
                thumbnailCorrupt.imageRef: .corrupt,
                alreadyAvailable.imageRef: .available(Data([7])),
                comparisonMissing.imageRef: .available(Data([8])),
                comparisonCorrupt.imageRef: .available(Data([9])),
            ],
            fullImages: [
                comparisonMissing.imageRef: .missing,
                comparisonCorrupt.imageRef: .corrupt,
            ]
        )
        let viewModel = ProgressPhotoGalleryViewModel(repository: repository)
        await viewModel.load()
        await viewModel.loadThumbnail(id: thumbnailMissing.id)
        await viewModel.loadThumbnail(id: thumbnailCorrupt.id)
        await viewModel.loadThumbnail(id: alreadyAvailable.id)
        await viewModel.loadThumbnail(id: comparisonMissing.id)
        await viewModel.loadThumbnail(id: comparisonCorrupt.id)
        _ = viewModel.toggleSelection(id: comparisonMissing.id)
        _ = viewModel.toggleSelection(id: comparisonCorrupt.id)
        await viewModel.loadComparisonImages()

        XCTAssertEqual(
            viewModel.items.first { $0.id == thumbnailMissing.id }?.assetState,
            .missing
        )
        XCTAssertEqual(
            viewModel.items.first { $0.id == thumbnailCorrupt.id }?.assetState,
            .corrupt
        )
        XCTAssertEqual(viewModel.comparison?.before.assetState, .missing)
        XCTAssertEqual(viewModel.comparison?.after.assetState, .corrupt)

        repository.thumbnails[thumbnailMissing.imageRef] = .available(Data([5]))
        repository.thumbnails[thumbnailCorrupt.imageRef] = .available(Data([6]))
        repository.fullImages[comparisonMissing.imageRef] = .available(Data([18]))
        repository.fullImages[comparisonCorrupt.imageRef] = .available(Data([19]))
        let synchronizer = CloudPhotoAssetSynchronizerFake(outcome: .synchronized)
        let lifecycle = ProgressPhotoAssetSyncLifecycle(
            synchronizer: synchronizer,
            galleryViewModel: viewModel
        )

        let outcome = try await lifecycle.synchronize()
        _ = try await lifecycle.synchronize()
        let synchronizationCalls = await synchronizer.calls

        XCTAssertEqual(outcome, .synchronized)
        XCTAssertEqual(synchronizationCalls, 2)
        XCTAssertEqual(
            viewModel.items.first { $0.id == thumbnailMissing.id }?.assetState,
            .available(Data([5]))
        )
        XCTAssertEqual(
            viewModel.items.first { $0.id == thumbnailCorrupt.id }?.assetState,
            .available(Data([6]))
        )
        XCTAssertEqual(viewModel.comparison?.before.assetState, .available(Data([18])))
        XCTAssertEqual(viewModel.comparison?.after.assetState, .available(Data([19])))
        XCTAssertEqual(
            repository.thumbnailRequests.filter { $0 == thumbnailMissing.imageRef }.count,
            2
        )
        XCTAssertEqual(
            repository.thumbnailRequests.filter { $0 == thumbnailCorrupt.imageRef }.count,
            2
        )
        XCTAssertEqual(
            repository.thumbnailRequests.filter { $0 == alreadyAvailable.imageRef }.count,
            1
        )
        XCTAssertEqual(
            repository.fullImageRequests.filter { $0 == comparisonMissing.imageRef }.count,
            2
        )
        XCTAssertEqual(
            repository.fullImageRequests.filter { $0 == comparisonCorrupt.imageRef }.count,
            2
        )
    }

    func testThumbnailCacheEvictsLeastRecentUnselectedAsset() async {
        let snapshots = (0..<3).map { offset in
            fixtureSnapshot(
                id: String(
                    format: "00000000-0000-0000-0000-%012d",
                    71 + offset
                ),
                date: Date(timeIntervalSince1970: TimeInterval(13_000 + offset)),
                pose: .front,
                assetID: String(
                    format: "00000000-0000-0000-0001-%012d",
                    71 + offset
                )
            )
        }
        let repository = ProgressPhotoGalleryRepositoryFake(
            photos: snapshots,
            thumbnails: Dictionary(uniqueKeysWithValues: snapshots.map {
                ($0.imageRef, PhotoAssetLoadResult.available(Data([1])))
            })
        )
        let viewModel = ProgressPhotoGalleryViewModel(
            repository: repository,
            thumbnailCacheLimit: 2
        )
        await viewModel.load()

        for snapshot in snapshots {
            await viewModel.loadThumbnail(id: snapshot.id)
        }

        XCTAssertEqual(viewModel.items.first { $0.id == snapshots[0].id }?.assetState, .unloaded)
        XCTAssertEqual(
            Set(viewModel.items.filter { $0.assetState.isAvailable }.map(\.id)),
            Set([snapshots[1].id, snapshots[2].id])
        )
    }
}

private actor CloudPhotoAssetSynchronizerFake: CloudPhotoAssetSynchronizing {
    private let outcome: CloudPhotoAssetSyncOutcome
    private(set) var calls = 0

    init(outcome: CloudPhotoAssetSyncOutcome) {
        self.outcome = outcome
    }

    func synchronize() async throws -> CloudPhotoAssetSyncOutcome {
        calls += 1
        return outcome
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
    var fullImages: [String: PhotoAssetLoadResult]
    var fullImageErrors: [String: Error]
    private(set) var thumbnailRequests: [String] = []
    private(set) var fullImageRequests: [String] = []
    var pendingAssetCleanupIDs: [String] { [] }

    init(
        photos: [ProgressPhotoSnapshot],
        thumbnails: [String: PhotoAssetLoadResult] = [:],
        thumbnailErrors: [String: Error] = [:],
        fullImages: [String: PhotoAssetLoadResult] = [:],
        fullImageErrors: [String: Error] = [:]
    ) {
        self.photos = photos
        self.thumbnails = thumbnails
        self.thumbnailErrors = thumbnailErrors
        self.fullImages = fullImages
        self.fullImageErrors = fullImageErrors
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

    func fullImage(assetID: String) async throws -> PhotoAssetLoadResult {
        fullImageRequests.append(assetID)
        if let error = fullImageErrors[assetID] { throw error }
        return fullImages[assetID] ?? .missing
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
