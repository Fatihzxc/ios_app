import Foundation
import SwiftData

@Model
public final class AppReminder {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var type: AppReminderType = AppReminderType.workout
    public var schedule: String = ""
    public var message: String = ""
    public var isEnabled: Bool = false

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        type: AppReminderType = .workout, schedule: String = "", message: String = "",
        isEnabled: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.type = type
        self.schedule = schedule
        self.message = message
        self.isEnabled = isEnabled
    }
}
