import CoreModels
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

public enum PhotoLibraryAccessState: Equatable, Sendable {
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

@MainActor
public protocol PhotoSelectionLoading: AnyObject {
    func loadData() async throws -> Data?
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

    @ObservationIgnored
    private let repository: any ProgressPhotoRepository
    @ObservationIgnored
    private var loadGeneration: UInt64 = 0

    public init(
        repository: any ProgressPhotoRepository,
        date: Date = .now,
        pose: ProgressPhotoPose = .front,
        note: String = ""
    ) {
        self.repository = repository
        self.date = date
        self.pose = pose
        self.note = note
    }

    public func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        listPhase = .loading
        do {
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
        guard phase != .loading else { return false }
        guard let selection else {
            phase = .idle
            return false
        }
        phase = .loading
        do {
            guard let bytes = try await selection.loadData(), !bytes.isEmpty else {
                phase = .failed
                return false
            }
            return await importPreparedBytes(bytes)
        } catch {
            phase = .failed
            return false
        }
    }

    @discardableResult
    public func importFixtureBytes(_ bytes: Data) async -> Bool {
        guard phase != .loading, !bytes.isEmpty else { return false }
        phase = .loading
        return await importPreparedBytes(bytes)
    }

    @discardableResult
    public func delete(_ snapshot: ProgressPhotoSnapshot) async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        deleteFailureID = nil
        do {
            try await repository.deletePhoto(
                id: snapshot.id,
                expectedUpdatedAt: snapshot.updatedAt
            )
            snapshots.removeAll { $0.id == snapshot.id }
            isDeleting = false
            return true
        } catch {
            deleteFailureID = snapshot.id
            isDeleting = false
            return false
        }
    }

    private func importPreparedBytes(_ bytes: Data) async -> Bool {
        do {
            let input = try ProgressPhotoInput(
                date: date,
                pose: pose,
                note: note
            )
            let snapshot = try await repository.importPhoto(input, bytes: bytes)
            snapshots = (snapshots.filter { $0.id != snapshot.id } + [snapshot])
                .sorted(by: ProgressPhotoOrdering.newestFirst)
            lastImportedSnapshot = snapshot
            listPhase = .loaded
            phase = .saved
            return true
        } catch {
            phase = .failed
            return false
        }
    }
}
