import Foundation
import SwiftData

@Model
public final class SleepLog {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var date: Date = Foundation.Date.now
    public var durationHours: Double = 0
    public var quality: Int = 0
    public var note: String?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, date: Date = .now,
        durationHours: Double = 0, quality: Int = 0, note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.durationHours = durationHours
        self.quality = quality
        self.note = note
    }
}
