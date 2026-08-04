import Foundation
import SwiftData

@Model
public final class MoodLog {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var date: Date = Foundation.Date.now
    public var moodScore: Int?
    public var moodTags: [String] = []
    public var energy: Int?
    public var note: String?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, date: Date = .now,
        moodScore: Int? = nil, moodTags: [String] = [], energy: Int? = nil, note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.moodScore = moodScore
        self.moodTags = moodTags
        self.energy = energy
        self.note = note
    }
}
