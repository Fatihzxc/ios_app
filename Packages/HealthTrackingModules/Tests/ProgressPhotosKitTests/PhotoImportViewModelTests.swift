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

        let importSucceeded = await importTask.value
        XCTAssertTrue(importSucceeded)
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

        let firstSucceeded = await viewModel.importSelection(
            PhotoSelectionLoaderFake(result: .success(Data([4, 5])))
        )
        XCTAssertFalse(firstSucceeded)
        XCTAssertTrue(viewModel.canRetryImport)
        viewModel.date = Date(timeIntervalSince1970: 777)
        viewModel.pose = .back
        viewModel.note = "Başka taslak"

        let retrySucceeded = await viewModel.retryImport()
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(repository.importRequests, [
            .init(input: exactInput, bytes: Data([4, 5])),
            .init(input: exactInput, bytes: Data([4, 5])),
        ])
        XCTAssertFalse(viewModel.canRetryImport)
        XCTAssertTrue(viewModel.canUndoLastImport)
    }

    func testNewSelectionFailureReplacesOlderRepositoryRetryWithLatestSelection() async throws {
        let firstDate = Date(timeIntervalSince1970: 221)
        let secondDate = Date(timeIntervalSince1970: 222)
        let firstInput = try ProgressPhotoInput(
            date: firstDate,
            pose: .front,
            note: "İlk"
        )
        let secondInput = try ProgressPhotoInput(
            date: secondDate,
            pose: .back,
            note: "İkinci"
        )
        let secondSnapshot = ProgressPhotoSnapshot(
            id: UUID(),
            createdAt: secondDate,
            updatedAt: secondDate,
            date: secondDate,
            imageRef: "00000000-0000-0000-0000-000000000058",
            pose: .back,
            note: "İkinci"
        )
        let repository = ProgressPhotoRepositoryFake(
            importResults: [
                .failure(FixtureSelectionError.load),
                .success(secondSnapshot),
            ]
        )
        let viewModel = ProgressPhotoImportViewModel(
            repository: repository,
            date: firstDate,
            pose: .front,
            note: "İlk"
        )

        let firstSucceeded = await viewModel.importSelection(
            PhotoSelectionLoaderFake(result: .success(Data([1])))
        )
        XCTAssertFalse(firstSucceeded)
        XCTAssertTrue(viewModel.canRetryImport)

        viewModel.date = secondDate
        viewModel.pose = .back
        viewModel.note = "İkinci"
        let secondLoader = SequencedPhotoSelectionLoaderFake(results: [
            .failure(FixtureSelectionError.load),
            .success(Data([2])),
        ])
        let secondSucceeded = await viewModel.importSelection(secondLoader)
        XCTAssertFalse(secondSucceeded)
        XCTAssertTrue(viewModel.canRetryImport)

        let retrySucceeded = await viewModel.retryImport()
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(repository.importRequests, [
            .init(input: firstInput, bytes: Data([1])),
            .init(input: secondInput, bytes: Data([2])),
        ])
        XCTAssertEqual(secondLoader.requestedMaximumBytes.count, 2)
        XCTAssertEqual(viewModel.lastImportedSnapshot, secondSnapshot)
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
        let firstSucceeded = await firstTask.value
        XCTAssertFalse(firstSucceeded)
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
        let importSucceeded = await viewModel.importSelection(
            PhotoSelectionLoaderFake(result: .success(Data([1])))
        )
        XCTAssertTrue(importSucceeded)

        let undoSucceeded = await viewModel.undoLastImport()
        XCTAssertFalse(undoSucceeded)
        XCTAssertTrue(viewModel.canRetryUndo)
        let undoRetrySucceeded = await viewModel.retryUndo()
        XCTAssertTrue(undoRetrySucceeded)
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

        let succeeded = await viewModel.importSelection(loader)
        XCTAssertFalse(succeeded)
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

    func testPickerStagingSweepsStaleFilesAndNeverCopiesPastHardCap() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagingRoot = temporaryRoot
            .appendingPathComponent("ProgressPhotoPickerStaging", isDirectory: true)
        let staleDirectory = stagingRoot
            .appendingPathComponent("stale", isDirectory: true)
        let source = temporaryRoot.appendingPathComponent("source.bin")
        try FileManager.default.createDirectory(
            at: staleDirectory,
            withIntermediateDirectories: true
        )
        try Data([9]).write(
            to: staleDirectory.appendingPathComponent("raw-selection")
        )
        try Data([1, 2, 3, 4, 5]).write(to: source)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let stagingStore = CappedPhotoStagingStore(stagingRoot: stagingRoot)

        await stagingStore.prepare()
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleDirectory.path))

        do {
            _ = try stagingStore.stageFile(at: source, maximumBytes: 4)
            XCTFail("The picker staging copy must stop at the byte policy.")
        } catch {
            XCTAssertEqual(
                error as? PhotoSelectionLoadError,
                .inputTooLarge(maximumBytes: 4)
            )
        }
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: stagingRoot,
                includingPropertiesForKeys: nil
            ).isEmpty
        )

        let acceptedURL = try stagingStore.stageFile(
            at: source,
            maximumBytes: 5
        )
        XCTAssertEqual(try Data(contentsOf: acceptedURL), Data([1, 2, 3, 4, 5]))
        stagingStore.removeStagedFile(at: acceptedURL)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: stagingRoot,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    func testFailedPickerStagingRemovalRetriesDuringCurrentProcess() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagingRoot = temporaryRoot
            .appendingPathComponent("ProgressPhotoPickerStaging", isDirectory: true)
        let source = temporaryRoot.appendingPathComponent("source.bin")
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
        try Data([1, 2, 3]).write(to: source)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let removal = FailOnceStagingRemoval()
        let stagingStore = CappedPhotoStagingStore(
            stagingRoot: stagingRoot,
            removeItem: { try removal.removeItem(at: $0) }
        )
        await stagingStore.prepare()
        let stagedURL = try stagingStore.stageFile(
            at: source,
            maximumBytes: 3
        )

        removal.failNextRemoval()
        stagingStore.removeStagedFile(at: stagedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))

        await stagingStore.prepare()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
    }

    func testCleanupFailureIsPublishedAndRetriedBeforeNextMutation() async {
        let snapshot = ProgressPhotoSnapshot(
            id: UUID(),
            createdAt: .now,
            updatedAt: .now,
            date: .now,
            imageRef: "00000000-0000-0000-0000-000000000059",
            pose: .front,
            note: nil
        )
        let repository = ProgressPhotoRepositoryFake(
            importResults: [.success(snapshot)],
            cleanupResults: [
                .failure(FixtureSelectionError.load),
                .success(()),
            ]
        )
        let viewModel = ProgressPhotoImportViewModel(repository: repository)

        await viewModel.load()
        XCTAssertEqual(viewModel.assetCleanupPhase, .pending)

        let importSucceeded = await viewModel.importFixtureBytes(Data([1]))
        XCTAssertTrue(importSucceeded)
        XCTAssertEqual(repository.cleanupRequestCount, 2)
        XCTAssertEqual(viewModel.assetCleanupPhase, .clean)
    }

    func testMetadataFailureCleanupIsRetriedBeforeExactImportRetry() async {
        let assetID = "00000000-0000-0000-0000-000000000060"
        let snapshot = ProgressPhotoSnapshot(
            id: UUID(),
            createdAt: .now,
            updatedAt: .now,
            date: .now,
            imageRef: assetID,
            pose: .front,
            note: nil
        )
        let repository = ProgressPhotoRepositoryFake(
            importResults: [
                .failure(
                    ProgressPhotoRepositoryOperationError
                        .metadataSaveFailedCleanupPending(assetID: assetID)
                ),
                .success(snapshot),
            ],
            cleanupResults: [.success(()), .success(())]
        )
        let viewModel = ProgressPhotoImportViewModel(repository: repository)

        let firstImportSucceeded = await viewModel.importFixtureBytes(Data([1]))
        XCTAssertFalse(firstImportSucceeded)
        XCTAssertEqual(viewModel.assetCleanupPhase, .pending)
        XCTAssertEqual(repository.pendingAssetCleanupIDs, [assetID])

        let retrySucceeded = await viewModel.retryImport()
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(repository.cleanupRequestCount, 2)
        XCTAssertTrue(repository.pendingAssetCleanupIDs.isEmpty)
        XCTAssertEqual(viewModel.assetCleanupPhase, .clean)
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

private final class FailOnceStagingRemoval: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFailNextRemoval = false

    func failNextRemoval() {
        lock.lock()
        shouldFailNextRemoval = true
        lock.unlock()
    }

    func removeItem(at url: URL) throws {
        lock.lock()
        let shouldFail = shouldFailNextRemoval
        shouldFailNextRemoval = false
        lock.unlock()
        if shouldFail { throw FixtureSelectionError.load }
        try FileManager.default.removeItem(at: url)
    }
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
        return try result.get()
    }
}

@MainActor
private final class SequencedPhotoSelectionLoaderFake: PhotoSelectionLoading {
    var results: [Result<Data?, Error>]
    private(set) var requestedMaximumBytes: [Int] = []

    init(results: [Result<Data?, Error>]) {
        self.results = results
    }

    func loadData(maximumBytes: Int) async throws -> Data? {
        requestedMaximumBytes.append(maximumBytes)
        guard !results.isEmpty else { throw FixtureSelectionError.load }
        return try results.removeFirst().get()
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
    var cleanupResults: [Result<Void, Error>]
    private(set) var importRequests: [ImportRequest] = []
    private(set) var deleteRequests: [DeleteRequest] = []
    private(set) var cleanupRequestCount = 0
    private var pendingCleanupIDs: [String] = []
    var pendingAssetCleanupIDs: [String] { pendingCleanupIDs }

    init(
        importResults: [Result<ProgressPhotoSnapshot, Error>] = [],
        deleteResults: [Result<Void, Error>] = [],
        cleanupResults: [Result<Void, Error>] = []
    ) {
        self.importResults = importResults
        self.deleteResults = deleteResults
        self.cleanupResults = cleanupResults
    }

    func fetchPhotos() async throws -> [ProgressPhotoSnapshot] { [] }

    func importPhoto(
        _ input: ProgressPhotoInput,
        bytes: Data
    ) async throws -> ProgressPhotoSnapshot {
        importRequests.append(.init(input: input, bytes: bytes))
        guard !importResults.isEmpty else { throw FixtureSelectionError.load }
        do {
            return try importResults.removeFirst().get()
        } catch {
            if let operationError =
                error as? ProgressPhotoRepositoryOperationError,
               case let .metadataSaveFailedCleanupPending(assetID) =
               operationError {
                pendingCleanupIDs = [assetID]
            }
            throw error
        }
    }

    func thumbnail(assetID: String) async throws -> PhotoAssetLoadResult {
        .missing
    }

    func deletePhoto(id: UUID, expectedUpdatedAt: Date) async throws {
        deleteRequests.append(.init(id: id, expectedUpdatedAt: expectedUpdatedAt))
        guard !deleteResults.isEmpty else { return }
        try deleteResults.removeFirst().get()
    }

    func retryPendingAssetCleanup() async throws {
        cleanupRequestCount += 1
        if !cleanupResults.isEmpty {
            try cleanupResults.removeFirst().get()
        }
        pendingCleanupIDs = []
    }
}
