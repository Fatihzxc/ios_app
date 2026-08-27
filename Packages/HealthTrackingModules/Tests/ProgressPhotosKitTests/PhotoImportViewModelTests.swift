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

    func testSuspendedPickerCapturesImmutableDraftBeforeTransferCompletes() async throws {
        let originalDate = Date(timeIntervalSince1970: 210)
        let expectedInput = try ProgressPhotoInput(
            date: originalDate,
            pose: .side,
            note: "İlk taslak"
        )
        let snapshot = ProgressPhotoSnapshot(
            id: UUID(),
            createdAt: originalDate,
            updatedAt: originalDate,
            date: originalDate,
            imageRef: "00000000-0000-0000-0000-000000000052",
            pose: .side,
            note: "İlk taslak"
        )
        let repository = ProgressPhotoRepositoryFake(
            importResults: [.success(snapshot)]
        )
        let viewModel = ProgressPhotoImportViewModel(
            repository: repository,
            date: originalDate,
            pose: .side,
            note: "  İlk taslak  "
        )
        let started = expectation(description: "selection transfer started")
        let loader = SuspendedPhotoSelectionLoader(onStart: { started.fulfill() })

        let importTask = Task { await viewModel.importSelection(loader) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(viewModel.isMutationInFlight)
        viewModel.date = Date(timeIntervalSince1970: 999)
        viewModel.pose = .back
        viewModel.note = "Yeni taslak"
        loader.resume(returning: Data([7, 8, 9]))

        XCTAssertTrue(await importTask.value)
        XCTAssertEqual(
            repository.importRequests,
            [.init(input: expectedInput, bytes: Data([7, 8, 9]))]
        )
    }

    func testRepositoryFailureRetriesExactCapturedRequestAfterDraftChanges() async throws {
        let originalDate = Date(timeIntervalSince1970: 220)
        let exactInput = try ProgressPhotoInput(
            date: originalDate,
            pose: .front,
            note: "Aynı istek"
        )
        let snapshot = ProgressPhotoSnapshot(
            id: UUID(),
            createdAt: originalDate,
            updatedAt: originalDate,
            date: originalDate,
            imageRef: "00000000-0000-0000-0000-000000000053",
            pose: .front,
            note: "Aynı istek"
        )
        let repository = ProgressPhotoRepositoryFake(
            importResults: [
                .failure(FixtureSelectionError.load),
                .success(snapshot),
            ]
        )
        let viewModel = ProgressPhotoImportViewModel(
            repository: repository,
            date: originalDate,
            pose: .front,
            note: "  Aynı istek  ",
            makeRequestID: {
                UUID(uuidString: "00000000-0000-0000-0000-000000000054")!
            }
        )

        XCTAssertFalse(
            await viewModel.importSelection(
                PhotoSelectionLoaderFake(result: .success(Data([4, 5])))
            )
        )
        XCTAssertTrue(viewModel.canRetryImport)
        viewModel.date = Date(timeIntervalSince1970: 777)
        viewModel.pose = .back
        viewModel.note = "Başka taslak"

        XCTAssertTrue(await viewModel.retryImport())
        XCTAssertEqual(repository.importRequests, [
            .init(input: exactInput, bytes: Data([4, 5])),
            .init(input: exactInput, bytes: Data([4, 5])),
        ])
        XCTAssertFalse(viewModel.canRetryImport)
        XCTAssertTrue(viewModel.canUndoLastImport)
    }

    func testCancelDuringSuspendedTransferLetsNewerRequestWin() async throws {
        let firstDate = Date(timeIntervalSince1970: 230)
        let secondDate = Date(timeIntervalSince1970: 231)
        let secondSnapshot = ProgressPhotoSnapshot(
            id: UUID(),
            createdAt: secondDate,
            updatedAt: secondDate,
            date: secondDate,
            imageRef: "00000000-0000-0000-0000-000000000055",
            pose: .back,
            note: "İkinci"
        )
        let repository = ProgressPhotoRepositoryFake(
            importResults: [.success(secondSnapshot)]
        )
        let viewModel = ProgressPhotoImportViewModel(
            repository: repository,
            date: firstDate,
            pose: .front,
            note: "İlk"
        )
        let started = expectation(description: "first transfer started")
        let firstLoader = SuspendedPhotoSelectionLoader(onStart: { started.fulfill() })
        let firstTask = Task { await viewModel.importSelection(firstLoader) }
        await fulfillment(of: [started], timeout: 2)

        viewModel.cancelPendingSelection()
        viewModel.date = secondDate
        viewModel.pose = .back
        viewModel.note = "İkinci"
        let secondSucceeded = await viewModel.importSelection(
            PhotoSelectionLoaderFake(result: .success(Data([2])))
        )
        firstLoader.resume(returning: Data([1]))

        XCTAssertTrue(secondSucceeded)
        XCTAssertFalse(await firstTask.value)
        XCTAssertEqual(repository.importRequests.count, 1)
        XCTAssertEqual(repository.importRequests.first?.bytes, Data([2]))
        XCTAssertEqual(viewModel.lastImportedSnapshot, secondSnapshot)
    }

    func testUndoAndFailedUndoRetryUseExactSavedSnapshotIdentity() async {
        let date = Date(timeIntervalSince1970: 240)
        let snapshot = ProgressPhotoSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000056")!,
            createdAt: date,
            updatedAt: date,
            date: date,
            imageRef: "00000000-0000-0000-0000-000000000057",
            pose: .front,
            note: nil
        )
        let repository = ProgressPhotoRepositoryFake(
            importResults: [.success(snapshot)],
            deleteResults: [
                .failure(FixtureSelectionError.load),
                .success(()),
            ]
        )
        let viewModel = ProgressPhotoImportViewModel(repository: repository)
        XCTAssertTrue(
            await viewModel.importSelection(
                PhotoSelectionLoaderFake(result: .success(Data([1])))
            )
        )

        XCTAssertFalse(await viewModel.undoLastImport())
        XCTAssertTrue(viewModel.canRetryUndo)
        XCTAssertTrue(await viewModel.retryUndo())
        XCTAssertEqual(repository.deleteRequests, [
            .init(id: snapshot.id, expectedUpdatedAt: snapshot.updatedAt),
            .init(id: snapshot.id, expectedUpdatedAt: snapshot.updatedAt),
        ])
        XCTAssertNil(viewModel.lastImportedSnapshot)
        XCTAssertFalse(viewModel.canUndoLastImport)
    }

    func testSelectionLoaderReceivesPreflightByteLimitAndOversizeNeverWrites() async {
        let repository = ProgressPhotoRepositoryFake()
        let loader = PhotoSelectionLoaderFake(
            result: .success(Data(repeating: 1, count: 5))
        )
        let viewModel = ProgressPhotoImportViewModel(
            repository: repository,
            maximumSelectionBytes: 4
        )

        XCTAssertFalse(await viewModel.importSelection(loader))
        XCTAssertEqual(loader.requestedMaximumBytes, [4])
        XCTAssertTrue(repository.importRequests.isEmpty)
        XCTAssertEqual(viewModel.phase, .failed)
    }

    func testCappedFileReaderRejectsByResourceSizeBeforeReturningData() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try Data([1, 2, 3, 4, 5]).write(to: url)
        let reader = CappedPhotoFileReader()

        do {
            _ = try await reader.readData(at: url, maximumBytes: 4)
            XCTFail("The picker file must be rejected before an oversized payload is returned.")
        } catch {
            XCTAssertEqual(
                error as? PhotoSelectionLoadError,
                .inputTooLarge(maximumBytes: 4)
            )
        }

        let accepted = try await reader.readData(at: url, maximumBytes: 5)
        XCTAssertEqual(accepted, Data([1, 2, 3, 4, 5]))
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
    private(set) var requestedMaximumBytes: [Int] = []

    init(result: Result<Data?, Error>) {
        self.result = result
    }

    func loadData(maximumBytes: Int) async throws -> Data? {
        requestedMaximumBytes.append(maximumBytes)
        try result.get()
    }
}

@MainActor
private final class SuspendedPhotoSelectionLoader: PhotoSelectionLoading {
    private let onStart: () -> Void
    private var continuation: CheckedContinuation<Data?, Error>?

    init(onStart: @escaping () -> Void) {
        self.onStart = onStart
    }

    func loadData(maximumBytes: Int) async throws -> Data? {
        _ = maximumBytes
        onStart()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(returning data: Data?) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}

@MainActor
private final class ProgressPhotoRepositoryFake: ProgressPhotoRepository {
    struct ImportRequest: Equatable {
        let input: ProgressPhotoInput
        let bytes: Data
    }

    struct DeleteRequest: Equatable {
        let id: UUID
        let expectedUpdatedAt: Date
    }

    var importResults: [Result<ProgressPhotoSnapshot, Error>]
    var deleteResults: [Result<Void, Error>]
    private(set) var importRequests: [ImportRequest] = []
    private(set) var deleteRequests: [DeleteRequest] = []
    var pendingAssetCleanupIDs: [String] { [] }

    init(
        importResults: [Result<ProgressPhotoSnapshot, Error>] = [],
        deleteResults: [Result<Void, Error>] = []
    ) {
        self.importResults = importResults
        self.deleteResults = deleteResults
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

    func deletePhoto(id: UUID, expectedUpdatedAt: Date) async throws {
        deleteRequests.append(.init(id: id, expectedUpdatedAt: expectedUpdatedAt))
        guard !deleteResults.isEmpty else { return }
        try deleteResults.removeFirst().get()
    }

    func retryPendingAssetCleanup() async throws {}
}
