import Foundation
import SwiftData

@Model
public final class WarmupItem {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var phase: WarmupPhase = WarmupPhase.raise
    public var movement: String = ""
    public var dose: String = ""
    public var orderIndex: Int = 0
    public var workoutDayTemplate: WorkoutDayTemplate?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        phase: WarmupPhase = .raise, movement: String = "", dose: String = "", orderIndex: Int = 0,
        workoutDayTemplate: WorkoutDayTemplate? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.phase = phase
        self.movement = movement
        self.dose = dose
        self.orderIndex = orderIndex
        self.workoutDayTemplate = workoutDayTemplate
    }
}
