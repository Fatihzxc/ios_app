import Foundation
import SwiftData

@Model
public final class BodyMetric {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var date: Date = Foundation.Date.now
    public var type: BodyMetricType = BodyMetricType.weight
    public var customName: String?
    public var value: Double = 0
    public var unit: String = ""

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, date: Date = .now,
        type: BodyMetricType = .weight, customName: String? = nil, value: Double = 0, unit: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.type = type
        self.customName = customName
        self.value = value
        self.unit = unit
    }
}
