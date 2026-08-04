import Foundation
import SwiftData

@Model
public final class PostureMetric {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var date: Date = Foundation.Date.now
    public var wallTestPass: Bool?
    public var symptomScore: Int?
    public var region: String?
    public var note: String?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, date: Date = .now,
        wallTestPass: Bool? = nil, symptomScore: Int? = nil, region: String? = nil, note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.wallTestPass = wallTestPass
        self.symptomScore = symptomScore
        self.region = region
        self.note = note
    }
}
