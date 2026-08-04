import Foundation
import SwiftData

@Model
public final class AppSetting {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var key: String = ""
    public var value: String = ""

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        key: String = "", value: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.key = key
        self.value = value
    }
}
