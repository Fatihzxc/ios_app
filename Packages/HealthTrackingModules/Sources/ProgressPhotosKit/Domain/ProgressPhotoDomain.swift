import CoreModels
import Foundation

public enum ProgressPhotoInputError: Error, Equatable, Sendable {
    case invalidDate
}

public struct ProgressPhotoInput: Equatable, Sendable {
    public let date: Date
    public let pose: ProgressPhotoPose
    public let note: String?

    public init(
        date: Date,
        pose: ProgressPhotoPose,
        note: String?
    ) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw ProgressPhotoInputError.invalidDate
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.date = date
        self.pose = pose
        self.note = trimmedNote?.isEmpty == false ? trimmedNote : nil
    }
}

public struct ProgressPhotoSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let date: Date
    public let imageRef: String
    public let pose: ProgressPhotoPose
    public let note: String?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        date: Date,
        imageRef: String,
        pose: ProgressPhotoPose,
        note: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.imageRef = imageRef
        self.pose = pose
        self.note = note
    }
}

public func isOpaquePhotoAssetID(_ value: String) -> Bool {
    guard !value.isEmpty,
          !value.contains("/"),
          !value.contains("\\"),
          !value.contains(":"),
          let identifier = UUID(uuidString: value) else {
        return false
    }
    return identifier.uuidString.lowercased() == value
}

public enum ProgressPhotoOrdering {
    public static func newestFirst(
        _ lhs: ProgressPhotoSnapshot,
        _ rhs: ProgressPhotoSnapshot
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }
}
