import Foundation
import SwiftData

@Model
public final class HealthCheckReminder {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var name: String = ""
    public var dueDate: Date = Foundation.Date.now
    public var recurrence: HealthCheckRecurrence = HealthCheckRecurrence.none
    public var status: HealthCheckStatus = HealthCheckStatus.pending

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, name: String = "",
        dueDate: Date = .now, recurrence: HealthCheckRecurrence = .none,
        status: HealthCheckStatus = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.dueDate = dueDate
        self.recurrence = recurrence
        self.status = status
    }
}
