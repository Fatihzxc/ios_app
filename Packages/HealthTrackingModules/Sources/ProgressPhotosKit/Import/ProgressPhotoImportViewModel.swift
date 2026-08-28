import CoreModels
import DesignSystem
import Foundation
import Observation

public enum PhotoImportPhase: Equatable, Sendable {
    case idle
    case loading
    case saved
    case failed
}

public enum ProgressPhotoListPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

public enum PhotoAssetCleanupPhase: Equatable, Sendable {
    case idle
    case retrying
    case clean
    case pending
}

public enum PhotoLibraryAccessState: String, Equatable, Sendable {
    case denied
    case limited
    case notDetermined
    case authorized
}

public enum SystemPhotoPickerAvailability {
    public static func isEnabled(for state: PhotoLibraryAccessState) -> Bool {
        switch state {
        case .denied, .limited, .notDetermined, .authorized:
            return true
        }
    }
}

public enum PhotoSelectionLoadError: Error, Equatable, Sendable {
    case inputTooLarge(maximumBytes: Int)
    case fileUnavailable
}

@MainActor
public protocol PhotoSelectionLoading: AnyObject {
    func loadData(maximumBytes: Int) async throws -> Data?
}

public struct ProgressPhotoCreationUndoToken: Equatable, Sendable {
    public let snapshot: ProgressPhotoSnapshot

    public init(snapshot: ProgressPhotoSnapshot) {
        self.snapshot = snapshot
    }
}

@MainActor
@Observable
public final class ProgressPhotoImportViewModel {
    public var date: Date
    public var pose: ProgressPhotoPose
    public var note: String
    public private(set) var phase: PhotoImportPhase = .idle
    public private(set) var listPhase: ProgressPhotoListPhase = .idle
    public private(set) var snapshots: [ProgressPhotoSnapshot] = []
    public private(set) var lastImportedSnapshot: ProgressPhotoSnapshot?
    public private(set) var deleteFailureID: UUID?
    public private(set) var isDeleting = false
    public private(set) var assetCleanupPhase: PhotoAssetCleanupPhase = .idle
    public private(set) var mutationPhase:
        QuickEntryMutationPhase<ProgressPhotoCreationUndoToken> = .idle

    public var canRetryImport: Bool {
        if pendingSelection != nil, !isLoadingSelection { return true }
        if case .saveFailed = mutationMachine.phase { return pendingImport != nil }
        return false
    }

    public var canUndoLastImport: Bool {
        if case .saved = mutationMachine.phase { return true }
        return false
    }

    public var canRetryUndo: Bool {
        if case .undoFailed = mutationMachine.phase { return true }
        return false
    }

    public var isMutationInFlight: Bool {
        if isLoadingSelection { return true }
        switch mutationMachine.phase {
        case .saving, .undoing:
            return true
        case .idle, .saved, .saveFailed, .undoFailed:
            return false
        }
    }

    @ObservationIgnored
    private let repository: any ProgressPhotoRepository
    @ObservationIgnored
    private let maximumSelectionBytes: Int
    @ObservationIgnored
    private let makeRequestID: @MainActor () -> UUID
    @ObservationIgnored
    private var mutationMachine =
        QuickEntryMutationStateMachine<ProgressPhotoCreationUndoToken>()
    @ObservationIgnored
    private var pendingImport: PendingPhotoImport?
    @ObservationIgnored
    private var pendingSelection: PendingPhotoSelection?
    @ObservationIgnored
    private var loadGeneration: UInt64 = 0
    @ObservationIgnored
    private var selectionGeneration: UInt64 = 0
    @ObservationIgnored
    private var isLoadingSelection = false

    public init(
        repository: any ProgressPhotoRepository,
        date: Date = .now,
        pose: ProgressPhotoPose = .front,
        note: String = "",
        maximumSelectionBytes: Int = PhotoAssetPolicy.production.maximumInputBytes,
        makeRequestID: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        precondition(maximumSelectionBytes > 0)
        self.repository = repository
        self.date = date
        self.pose = pose
        self.note = note
        self.maximumSelectionBytes = maximumSelectionBytes
        self.makeRequestID = makeRequestID
    }

    public func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        listPhase = .loading
        do {
            _ = await retryPendingAssetCleanup()
            let loaded = try await repository.fetchPhotos()
            guard generation == loadGeneration else { return }
            snapshots = loaded.sorted(by: ProgressPhotoOrdering.newestFirst)
            listPhase = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            listPhase = .failed
        }
    }

    @discardableResult
    public func importSelection(
        _ selection: (any PhotoSelectionLoading)?
    ) async -> Bool {
        guard !isMutationInFlight else { return false }
        guard let selection else {
            phase = .idle
            return false
        }
        abandonFailedImportForNewSelection()
        guard let request = makePendingRequest() else {
            phase = .failed
            return false
        }
        let pending = PendingPhotoSelection(request: request, loader: selection)
        pendingSelection = pending
        return await loadSelection(pending)
    }

    public func cancelPendingSelection() {
        guard isLoadingSelection else { return }
        selectionGeneration &+= 1
        isLoadingSelection = false
        pendingSelection = nil
        phase = .idle
    }

    @discardableResult
    public func importFixtureBytes(_ bytes: Data) async -> Bool {
        guard !isMutationInFlight else {
            phase = .failed
            return false
        }
        abandonFailedImportForNewSelection()
        pendingSelection = nil
        guard !bytes.isEmpty,
              bytes.count <= maximumSelectionBytes,
              let request = makePendingRequest() else {
            phase = .failed
            return false
        }
        phase = .loading
        return await beginImport(request: request, bytes: bytes)
    }

    @discardableResult
    public func retryImport() async -> Bool {
        if let pendingSelection, !isLoadingSelection {
            return await loadSelection(pendingSelection)
        }
        guard let pendingImport,
              let attempt = mutationMachine.retrySave() else { return false }
        phase = .loading
        publishMutationPhase()
        return await performImport(pendingImport, attempt: attempt)
    }

    @discardableResult
    public func retryPendingAssetCleanup() async -> Bool {
        assetCleanupPhase = .retrying
        do {
            try await repository.retryPendingAssetCleanup()
            let isClean = repository.pendingAssetCleanupIDs.isEmpty
            assetCleanupPhase = isClean ? .clean : .pending
            return isClean
        } catch {
            assetCleanupPhase = .pending
            return false
        }
    }

    @discardableResult
    public func undoLastImport() async -> Bool {
        guard case let .saved(undoToken) = mutationMachine.phase,
              let attempt = mutationMachine.beginUndo(
                requestID: makeRequestID()
              ) else { return false }
        phase = .loading
        publishMutationPhase()
        return await performUndo(undoToken, attempt: attempt)
    }

    @discardableResult
    public func retryUndo() async -> Bool {
        guard case let .undoFailed(_, undoToken) = mutationMachine.phase,
              let attempt = mutationMachine.retryUndo() else { return false }
        phase = .loading
        publishMutationPhase()
        return await performUndo(undoToken, attempt: attempt)
    }

    @discardableResult
    public func delete(_ snapshot: ProgressPhotoSnapshot) async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        deleteFailureID = nil
        _ = await retryPendingAssetCleanup()
        do {
            try await repository.deletePhoto(
                id: snapshot.id,
                expectedUpdatedAt: snapshot.updatedAt
            )
            snapshots.removeAll { $0.id == snapshot.id }
            if lastImportedSnapshot?.id == snapshot.id {
                _ = mutationMachine.expireUndo()
                pendingImport = nil
                lastImportedSnapshot = nil
                publishMutationPhase()
            }
            isDeleting = false
            return true
        } catch {
            publishPendingCleanupIfNeeded(after: error)
            deleteFailureID = snapshot.id
            isDeleting = false
            return false
        }
    }

    private func makePendingRequest() -> PendingPhotoRequest? {
        if mutationMachine.expireUndo() {
            pendingImport = nil
            publishMutationPhase()
        }
        guard let input = try? ProgressPhotoInput(
            date: date,
            pose: pose,
            note: note
        ) else { return nil }
        return PendingPhotoRequest(requestID: makeRequestID(), input: input)
    }

    private func abandonFailedImportForNewSelection() {
        if mutationMachine.abandonFailedSave() {
            pendingImport = nil
            publishMutationPhase()
        }
    }

    private func loadSelection(
        _ pending: PendingPhotoSelection
    ) async -> Bool {
        selectionGeneration &+= 1
        let generation = selectionGeneration
        isLoadingSelection = true
        phase = .loading
        do {
            guard let bytes = try await pending.loader.loadData(
                maximumBytes: maximumSelectionBytes
            ), !bytes.isEmpty, bytes.count <= maximumSelectionBytes else {
                guard generation == selectionGeneration else { return false }
                isLoadingSelection = false
                phase = .failed
                return false
            }
            guard generation == selectionGeneration else { return false }
            isLoadingSelection = false
            pendingSelection = nil
            return await beginImport(request: pending.request, bytes: bytes)
        } catch {
            guard generation == selectionGeneration else { return false }
            isLoadingSelection = false
            phase = .failed
            return false
        }
    }

    private func beginImport(
        request: PendingPhotoRequest,
        bytes: Data
    ) async -> Bool {
        let pending = PendingPhotoImport(
            requestID: request.requestID,
            input: request.input,
            bytes: bytes
        )
        guard let attempt = mutationMachine.beginSave(
            requestID: request.requestID
        ) else { return false }
        pendingImport = pending
        publishMutationPhase()
        return await performImport(pending, attempt: attempt)
    }

    private func performImport(
        _ pending: PendingPhotoImport,
        attempt: QuickEntryMutationAttempt
    ) async -> Bool {
        _ = await retryPendingAssetCleanup()
        do {
            let snapshot = try await repository.importPhoto(
                pending.input,
                bytes: pending.bytes
            )
            guard mutationMachine.completeSave(
                attempt,
                undoToken: ProgressPhotoCreationUndoToken(snapshot: snapshot)
            ) else { return false }
            snapshots = (snapshots.filter { $0.id != snapshot.id } + [snapshot])
                .sorted(by: ProgressPhotoOrdering.newestFirst)
            lastImportedSnapshot = snapshot
            listPhase = .loaded
            phase = .saved
            publishMutationPhase()
            return true
        } catch {
            publishPendingCleanupIfNeeded(after: error)
            guard mutationMachine.failSave(attempt) else { return false }
            phase = .failed
            publishMutationPhase()
            return false
        }
    }

    private func performUndo(
        _ undoToken: ProgressPhotoCreationUndoToken,
        attempt: QuickEntryMutationAttempt
    ) async -> Bool {
        _ = await retryPendingAssetCleanup()
        do {
            try await repository.deletePhoto(
                id: undoToken.snapshot.id,
                expectedUpdatedAt: undoToken.snapshot.updatedAt
            )
            guard mutationMachine.completeUndo(attempt) else { return false }
            snapshots.removeAll { $0.id == undoToken.snapshot.id }
            if lastImportedSnapshot?.id == undoToken.snapshot.id {
                lastImportedSnapshot = nil
            }
            pendingImport = nil
            phase = .idle
            publishMutationPhase()
            return true
        } catch {
            publishPendingCleanupIfNeeded(after: error)
            guard mutationMachine.failUndo(attempt) else { return false }
            phase = .failed
            publishMutationPhase()
            return false
        }
    }

    private func publishMutationPhase() {
        mutationPhase = mutationMachine.phase
    }

    private func publishPendingCleanupIfNeeded(after error: Error) {
        if !repository.pendingAssetCleanupIDs.isEmpty {
            assetCleanupPhase = .pending
            return
        }
        guard let operationError = error as? ProgressPhotoRepositoryOperationError
        else { return }
        switch operationError {
        case .metadataSaveFailedCleanupPending, .cleanupJournalFailed:
            assetCleanupPhase = .pending
        case .loadFailed, .saveFailed, .protectedDataUnavailable,
             .assetDeleteFailed, .deleteCompensationFailed:
            break
        }
    }
}

private struct PendingPhotoRequest: Equatable, Sendable {
    let requestID: UUID
    let input: ProgressPhotoInput
}

private struct PendingPhotoImport: Equatable, Sendable {
    let requestID: UUID
    let input: ProgressPhotoInput
    let bytes: Data
}

@MainActor
private struct PendingPhotoSelection {
    let request: PendingPhotoRequest
    let loader: any PhotoSelectionLoading
}
