import CoreModels
import Foundation
import Observation

public enum ProgressPhotoGalleryPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

public enum ProgressPhotoGalleryAssetState: Equatable, Sendable {
    case unloaded
    case loading
    case available(Data)
    case missing
    case corrupt
    case unavailable

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public struct ProgressPhotoGalleryItem: Identifiable, Equatable, Sendable {
    public let snapshot: ProgressPhotoSnapshot
    public let assetState: ProgressPhotoGalleryAssetState
    public let thumbnailLoadID: UInt64

    public var id: UUID { snapshot.id }

    public init(
        snapshot: ProgressPhotoSnapshot,
        assetState: ProgressPhotoGalleryAssetState,
        thumbnailLoadID: UInt64 = 0
    ) {
        self.snapshot = snapshot
        self.assetState = assetState
        self.thumbnailLoadID = thumbnailLoadID
    }
}

public struct ProgressPhotoComparison: Equatable, Sendable {
    public let before: ProgressPhotoGalleryItem
    public let after: ProgressPhotoGalleryItem

    public init(
        before: ProgressPhotoGalleryItem,
        after: ProgressPhotoGalleryItem
    ) {
        self.before = before
        self.after = after
    }
}

public struct ProgressPhotoComparisonLoadID: Equatable, Sendable {
    public let selectedPhotoIDs: [UUID]
    public let generation: UInt64

    public init(selectedPhotoIDs: [UUID], generation: UInt64) {
        self.selectedPhotoIDs = selectedPhotoIDs
        self.generation = generation
    }
}

public enum ProgressPhotoSelectionResult: Equatable, Sendable {
    case selected
    case deselected
    case replacedOldest(removedID: UUID)
    case assetUnavailable
    case unknownPhoto
}

public enum ProgressPhotoSelectionNotice: Equatable, Sendable {
    case replacedOldest(removedID: UUID)
    case assetUnavailable
    case unknownPhoto
}

public enum ProgressPhotoGalleryOrdering {
    public static func newestDateThenPose(
        _ lhs: ProgressPhotoSnapshot,
        _ rhs: ProgressPhotoSnapshot
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        let lhsPose = poseRank(lhs.pose)
        let rhsPose = poseRank(rhs.pose)
        if lhsPose != rhsPose { return lhsPose < rhsPose }
        return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }

    static func chronological(
        _ lhs: ProgressPhotoGalleryItem,
        _ rhs: ProgressPhotoGalleryItem
    ) -> Bool {
        if lhs.snapshot.date != rhs.snapshot.date {
            return lhs.snapshot.date < rhs.snapshot.date
        }
        let lhsPose = poseRank(lhs.snapshot.pose)
        let rhsPose = poseRank(rhs.snapshot.pose)
        if lhsPose != rhsPose { return lhsPose < rhsPose }
        return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }

    private static func poseRank(_ pose: ProgressPhotoPose) -> Int {
        switch pose {
        case .front: 0
        case .side: 1
        case .back: 2
        }
    }
}

@MainActor
@Observable
public final class ProgressPhotoGalleryViewModel {
    public private(set) var phase: ProgressPhotoGalleryPhase = .idle
    public private(set) var items: [ProgressPhotoGalleryItem] = []
    public private(set) var selectedPhotoIDs: [UUID] = []
    public private(set) var selectionNotice: ProgressPhotoSelectionNotice?
    public private(set) var comparisonLoadGeneration: UInt64 = 0
    private var comparisonAssetStates: [UUID: ProgressPhotoGalleryAssetState] = [:]

    @ObservationIgnored
    private let repository: any ProgressPhotoRepository
    @ObservationIgnored
    private let thumbnailCacheLimit: Int
    @ObservationIgnored
    private var loadGeneration: UInt64 = 0
    @ObservationIgnored
    private var selectionGeneration: UInt64 = 0
    @ObservationIgnored
    private var thumbnailRecency: [UUID] = []

    public init(
        repository: any ProgressPhotoRepository,
        thumbnailCacheLimit: Int = 24
    ) {
        precondition(thumbnailCacheLimit >= 2)
        self.repository = repository
        self.thumbnailCacheLimit = thumbnailCacheLimit
    }

    public var comparison: ProgressPhotoComparison? {
        let selected = selectedAvailableItems
        guard selected.count == 2 else { return nil }
        let ordered = selected.sorted(by: ProgressPhotoGalleryOrdering.chronological)
        return ProgressPhotoComparison(
            before: comparisonItem(from: ordered[0]),
            after: comparisonItem(from: ordered[1])
        )
    }

    public var comparisonLoadID: ProgressPhotoComparisonLoadID? {
        guard selectedAvailableItems.count == 2 else { return nil }
        return ProgressPhotoComparisonLoadID(
            selectedPhotoIDs: selectedPhotoIDs,
            generation: comparisonLoadGeneration
        )
    }

    public func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        phase = .loading
        do {
            let snapshots = try await repository.fetchPhotos()
                .sorted(by: ProgressPhotoGalleryOrdering.newestDateThenPose)
            guard generation == loadGeneration else { return }

            items = snapshots.map {
                ProgressPhotoGalleryItem(
                    snapshot: $0,
                    assetState: .unloaded,
                    thumbnailLoadID: generation
                )
            }
            thumbnailRecency.removeAll(keepingCapacity: true)
            comparisonAssetStates.removeAll(keepingCapacity: true)
            selectionGeneration &+= 1
            comparisonLoadGeneration &+= 1
            let existingIDs = Set(snapshots.map(\.id))
            selectedPhotoIDs.removeAll { !existingIDs.contains($0) }
            selectionNotice = nil
            phase = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            phase = .failed
        }
    }

    public func loadThumbnail(id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].assetState.isAvailable {
            recordThumbnailAccess(id)
            return
        }
        guard items[index].assetState == .unloaded else { return }

        let generation = loadGeneration
        let snapshot = items[index].snapshot
        setThumbnailState(.loading, id: id)
        do {
            let result = try await repository.thumbnail(assetID: snapshot.imageRef)
            guard generation == loadGeneration,
                  !Task.isCancelled,
                  currentSnapshot(id: id)?.imageRef == snapshot.imageRef else {
                restoreUnloadedThumbnail(id: id, generation: generation)
                return
            }
            let state = galleryState(from: result)
            setThumbnailState(state, id: id)
            if state.isAvailable {
                recordThumbnailAccess(id)
            } else {
                pruneSelectionIfUnavailable(id: id)
            }
        } catch {
            guard generation == loadGeneration,
                  currentSnapshot(id: id)?.imageRef == snapshot.imageRef else { return }
            if Task.isCancelled {
                restoreUnloadedThumbnail(
                    id: id,
                    generation: generation
                )
            } else {
                setThumbnailState(.unavailable, id: id)
                pruneSelectionIfUnavailable(id: id)
            }
        }
    }

    public func loadComparisonImages() async {
        let selected = selectedAvailableItems
        guard selected.count == 2 else { return }
        let generation = selectionGeneration
        let selectedIDs = selectedPhotoIDs

        for id in selectedIDs {
            guard let item = selected.first(where: { $0.id == id }) else { continue }
            switch comparisonAssetStates[id] ?? .unloaded {
            case .available, .missing, .corrupt, .unavailable, .loading:
                continue
            case .unloaded:
                break
            }
            comparisonAssetStates[id] = .loading
            do {
                let result = try await repository.fullImage(
                    assetID: item.snapshot.imageRef
                )
                guard generation == selectionGeneration,
                      selectedIDs == selectedPhotoIDs else { return }
                guard !Task.isCancelled else {
                    comparisonAssetStates[id] = .unloaded
                    comparisonLoadGeneration &+= 1
                    return
                }
                comparisonAssetStates[id] = galleryState(from: result)
            } catch {
                guard generation == selectionGeneration,
                      selectedIDs == selectedPhotoIDs else { return }
                comparisonAssetStates[id] = Task.isCancelled
                    ? .unloaded
                    : .unavailable
                if Task.isCancelled {
                    comparisonLoadGeneration &+= 1
                    return
                }
            }
        }
    }

    public func retryUnavailableAssets() async {
        let thumbnailIDs = items.compactMap { item in
            item.assetState == .unavailable ? item.id : nil
        }
        for id in thumbnailIDs {
            setThumbnailState(.unloaded, id: id, advancesLoadID: true)
        }
        for id in thumbnailIDs { await loadThumbnail(id: id) }

        let fullImageIDs = selectedPhotoIDs.filter {
            comparisonAssetStates[$0] == .unavailable
        }
        for id in fullImageIDs { comparisonAssetStates[id] = .unloaded }
        if !fullImageIDs.isEmpty {
            comparisonLoadGeneration &+= 1
            await loadComparisonImages()
        }
    }

    @discardableResult
    public func toggleSelection(id: UUID) -> ProgressPhotoSelectionResult {
        guard let item = items.first(where: { $0.id == id }) else {
            selectionNotice = .unknownPhoto
            return .unknownPhoto
        }
        guard item.assetState.isAvailable else {
            selectionNotice = .assetUnavailable
            return .assetUnavailable
        }
        if let index = selectedPhotoIDs.firstIndex(of: id) {
            selectedPhotoIDs.remove(at: index)
            selectionDidChange()
            selectionNotice = nil
            return .deselected
        }
        if selectedPhotoIDs.count == 2 {
            let removedID = selectedPhotoIDs.removeFirst()
            selectedPhotoIDs.append(id)
            selectionDidChange()
            selectionNotice = .replacedOldest(removedID: removedID)
            return .replacedOldest(removedID: removedID)
        }
        selectedPhotoIDs.append(id)
        selectionDidChange()
        selectionNotice = nil
        return .selected
    }

    private var selectedAvailableItems: [ProgressPhotoGalleryItem] {
        guard selectedPhotoIDs.count == 2 else { return [] }
        return selectedPhotoIDs.compactMap { id in
            items.first { $0.id == id && $0.assetState.isAvailable }
        }
    }

    private func comparisonItem(
        from thumbnailItem: ProgressPhotoGalleryItem
    ) -> ProgressPhotoGalleryItem {
        ProgressPhotoGalleryItem(
            snapshot: thumbnailItem.snapshot,
            assetState: comparisonAssetStates[thumbnailItem.id] ?? .unloaded
        )
    }

    private func selectionDidChange() {
        selectionGeneration &+= 1
        comparisonLoadGeneration &+= 1
        guard selectedPhotoIDs.count == 2 else {
            comparisonAssetStates.removeAll(keepingCapacity: true)
            trimThumbnailCache()
            return
        }
        let selected = Set(selectedPhotoIDs)
        comparisonAssetStates = comparisonAssetStates.filter { entry in
            selected.contains(entry.key) && entry.value != .loading
        }
        trimThumbnailCache()
    }

    private func galleryState(
        from result: PhotoAssetLoadResult
    ) -> ProgressPhotoGalleryAssetState {
        switch result {
        case let .available(bytes): return .available(bytes)
        case .missing: return .missing
        case .corrupt: return .corrupt
        }
    }

    private func currentSnapshot(id: UUID) -> ProgressPhotoSnapshot? {
        items.first(where: { $0.id == id })?.snapshot
    }

    private func setThumbnailState(
        _ state: ProgressPhotoGalleryAssetState,
        id: UUID
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = ProgressPhotoGalleryItem(
            snapshot: items[index].snapshot,
            assetState: state,
            thumbnailLoadID: items[index].thumbnailLoadID
        )
    }

    private func setThumbnailState(
        _ state: ProgressPhotoGalleryAssetState,
        id: UUID,
        advancesLoadID: Bool
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = ProgressPhotoGalleryItem(
            snapshot: items[index].snapshot,
            assetState: state,
            thumbnailLoadID: advancesLoadID
                ? items[index].thumbnailLoadID &+ 1
                : items[index].thumbnailLoadID
        )
    }

    private func restoreUnloadedThumbnail(
        id: UUID,
        generation: UInt64
    ) {
        guard generation == loadGeneration,
              let item = items.first(where: { $0.id == id }),
              item.assetState == .loading else { return }
        setThumbnailState(
            .unloaded,
            id: id,
            advancesLoadID: true
        )
    }

    private func pruneSelectionIfUnavailable(id: UUID) {
        guard let index = selectedPhotoIDs.firstIndex(of: id) else { return }
        selectedPhotoIDs.remove(at: index)
        selectionDidChange()
        selectionNotice = .assetUnavailable
    }

    private func recordThumbnailAccess(_ id: UUID) {
        thumbnailRecency.removeAll { $0 == id }
        thumbnailRecency.append(id)
        trimThumbnailCache()
    }

    private func trimThumbnailCache() {
        while thumbnailRecency.count > thumbnailCacheLimit {
            guard let evictionIndex = thumbnailRecency.firstIndex(where: {
                !selectedPhotoIDs.contains($0)
            }) else { return }
            let evictedID = thumbnailRecency.remove(at: evictionIndex)
            if currentSnapshot(id: evictedID) != nil {
                setThumbnailState(
                    .unloaded,
                    id: evictedID,
                    advancesLoadID: true
                )
            }
        }
    }
}
