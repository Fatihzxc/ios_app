import Foundation
import SwiftData

@Model
public final class ProgressPhoto {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var date: Date = Foundation.Date.now
    public var imageRef: String = ""
    public var pose: ProgressPhotoPose = ProgressPhotoPose.front
    public var note: String?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, date: Date = .now,
        imageRef: String = "", pose: ProgressPhotoPose = .front, note: String? = nil
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
