import Foundation
import SwiftData

@Model
public final class BloodworkResult {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var date: Date = Foundation.Date.now
    public var marker: String = ""
    public var value: Double = 0
    public var unit: String = ""
    public var note: String?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, date: Date = .now,
        marker: String = "", value: Double = 0, unit: String = "", note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.marker = marker
        self.value = value
        self.unit = unit
        self.note = note
    }
}
