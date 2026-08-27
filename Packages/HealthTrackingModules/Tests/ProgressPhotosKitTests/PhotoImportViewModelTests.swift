import CoreModels
import Foundation
import ProgressPhotosKit
import XCTest

@MainActor
final class PhotoImportViewModelTests: XCTestCase {
    func testCancelledSelectionPreservesDatePoseAndNoteWithoutRepositoryWrite() async {
        let repository = ProgressPhotoRepositoryFake()
        let date = Date(timeIntervalSince1970: 200)
        let viewModel = ProgressPhotoImportViewModel(
            repository: repository,
            date: date,
            pose: .side,
            note: "Aylık kayıt"
        )

        let succeeded = await viewModel.importSelection(nil)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.date, date)
        XCTAssertEqual(viewModel.pose, .side)
        XCTAssertEqual(viewModel.note, "Aylık kayıt")
        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertTrue(repository.importRequests.isEmpty)
    }

    func testLoadFailureAndEmptyPayloadPreserveExactDraftForRetry() async {
        let repository = ProgressPhotoRepositoryFake()
        let date = Date(timeIntervalSince1970: 201)
        let viewModel = ProgressPhotoImportViewModel(
            repository: repository,
            date: date,
            pose: .back,
            note: "  Değişmeden kalmalı  "
        )

        let failed = await viewModel.importSelection(
            PhotoSelectionLoaderFake(result: .failure(FixtureSelectionError.load))
        )
        XCTAssertFalse(failed)
        XCTAssertEqual(viewModel.phase, .failed)
        XCTAssertEqual(viewModel.date, date)
        XCTAssertEqual(viewModel.pose, .back)
        XCTAssertEqual(viewModel.note, "  Değişmeden kalmalı  ")

        let empty = await viewModel.importSelection(
            PhotoSelectionLoaderFake(result: .success(nil))
        )
        XCTAssertFalse(empty)
        XCTAssertEqual(viewModel.phase, .failed)
        XCTAssertEqual(viewModel.note, "  Değişmeden kalmalı  ")
        XCTAssertTrue(repository.importRequests.isEmpty)
    }

    func testSuccessfulSelectionPassesBytesAndNormalizedDraftToRepository() async throws {
        let date = Date(timeIntervalSince1970: 202)
        let expectedInput = try ProgressPhotoInput(
            date: date,
            pose: .front,
            note: "Sabah"
        )
        let snapshot = ProgressPhotoSnapshot(
            id: UUID(),
            createdAt: date,
            updatedAt: date,
            date: date,
            imageRef: "00000000-0000-0000-0000-000000000042",
            pose: .front,
            note: "Sabah"
        )
        let repository = ProgressPhotoRepositoryFake(
            importResults: [.success(snapshot)]
        )
        let viewModel = ProgressPhotoImportViewModel(
            repository: repository,
            date: date,
            pose: .front,
            note: "  Sabah  "
        )
        let bytes = Data([1, 2, 3])

        let succeeded = await viewModel.importSelection(
            PhotoSelectionLoaderFake(result: .success(bytes))
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(viewModel.phase, .saved)
        XCTAssertEqual(viewModel.lastImportedSnapshot, snapshot)
        XCTAssertEqual(
            repository.importRequests,
            [.init(input: expectedInput, bytes: bytes)]
        )
    }

    func testDeniedLimitedAndUndeterminedBroaderAccessNeverDisableSystemPicker() {
        XCTAssertTrue(SystemPhotoPickerAvailability.isEnabled(for: .denied))
        XCTAssertTrue(SystemPhotoPickerAvailability.isEnabled(for: .limited))
        XCTAssertTrue(SystemPhotoPickerAvailability.isEnabled(for: .notDetermined))
        XCTAssertTrue(SystemPhotoPickerAvailability.isEnabled(for: .authorized))
    }
}

private enum FixtureSelectionError: Error {
    case load
}

@MainActor
private final class PhotoSelectionLoaderFake: PhotoSelectionLoading {
    let result: Result<Data?, Error>

    init(result: Result<Data?, Error>) {
        self.result = result
    }

    func loadData() async throws -> Data? {
        try result.get()
    }
}

@MainActor
private final class ProgressPhotoRepositoryFake: ProgressPhotoRepository {
    struct ImportRequest: Equatable {
        let input: ProgressPhotoInput
        let bytes: Data
    }

    var importResults: [Result<ProgressPhotoSnapshot, Error>]
    private(set) var importRequests: [ImportRequest] = []
    var pendingAssetCleanupIDs: [String] { [] }

    init(importResults: [Result<ProgressPhotoSnapshot, Error>] = []) {
        self.importResults = importResults
    }

    func fetchPhotos() async throws -> [ProgressPhotoSnapshot] { [] }

    func importPhoto(
        _ input: ProgressPhotoInput,
        bytes: Data
    ) async throws -> ProgressPhotoSnapshot {
        importRequests.append(.init(input: input, bytes: bytes))
        guard !importResults.isEmpty else { throw FixtureSelectionError.load }
        return try importResults.removeFirst().get()
    }

    func thumbnail(assetID: String) async throws -> PhotoAssetLoadResult {
        .missing
    }

    func deletePhoto(id: UUID, expectedUpdatedAt: Date) async throws {}

    func retryPendingAssetCleanup() async throws {}
}
