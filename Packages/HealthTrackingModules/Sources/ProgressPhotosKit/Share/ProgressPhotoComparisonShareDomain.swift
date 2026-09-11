import CoreModels
import Foundation

public enum ProgressPhotoComparisonShareError: Error, Equatable, Sendable {
    case invalidDate
    case emptyImageData
    case duplicateItems
    case unavailableImages
    case corruptImage
    case renderingFailed
    case temporaryStorageFailed
    case presentationFailed
}

public struct ProgressPhotoShareItem: Equatable, Sendable {
    public let imageData: Data
    public let date: Date
    public let pose: ProgressPhotoPose

    public init(
        imageData: Data,
        date: Date,
        pose: ProgressPhotoPose
    ) {
        self.imageData = imageData
        self.date = date
        self.pose = pose
    }
}

public struct ProgressPhotoComparisonShareDescriptor: Equatable, Sendable {
    public let before: ProgressPhotoShareItem
    public let after: ProgressPhotoShareItem

    public init(
        first: ProgressPhotoShareItem,
        second: ProgressPhotoShareItem
    ) throws {
        guard first.date.timeIntervalSinceReferenceDate.isFinite,
              second.date.timeIntervalSinceReferenceDate.isFinite else {
            throw ProgressPhotoComparisonShareError.invalidDate
        }
        guard !first.imageData.isEmpty, !second.imageData.isEmpty else {
            throw ProgressPhotoComparisonShareError.emptyImageData
        }
        guard first != second else {
            throw ProgressPhotoComparisonShareError.duplicateItems
        }
        if Self.orderedBefore(first, second) {
            before = first
            after = second
        } else {
            before = second
            after = first
        }
    }

    private static func orderedBefore(
        _ lhs: ProgressPhotoShareItem,
        _ rhs: ProgressPhotoShareItem
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        let lhsPose = poseRank(lhs.pose)
        let rhsPose = poseRank(rhs.pose)
        if lhsPose != rhsPose { return lhsPose < rhsPose }
        return lhs.imageData.lexicographicallyPrecedes(rhs.imageData)
    }

    private static func poseRank(_ pose: ProgressPhotoPose) -> Int {
        switch pose {
        case .front: 0
        case .side: 1
        case .back: 2
        }
    }
}

public protocol ProgressPhotoComparisonRendering: AnyObject, Sendable {
    @MainActor
    func render(
        _ descriptor: ProgressPhotoComparisonShareDescriptor
    ) async throws -> Data
}
