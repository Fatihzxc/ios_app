import Foundation
import SwiftData

@Model
public final class CooldownItem {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var movement: String = ""
    public var dose: String = ""
    public var note: String?
    public var orderIndex: Int = 0
    public var workoutDayTemplate: WorkoutDayTemplate?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        movement: String = "", dose: String = "", note: String? = nil, orderIndex: Int = 0,
        workoutDayTemplate: WorkoutDayTemplate? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.movement = movement
        self.dose = dose
        self.note = note
        self.orderIndex = orderIndex
        self.workoutDayTemplate = workoutDayTemplate
    }
}
