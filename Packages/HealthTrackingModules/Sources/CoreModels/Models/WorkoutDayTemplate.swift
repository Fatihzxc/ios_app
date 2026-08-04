import Foundation
import SwiftData

@Model
public final class WorkoutDayTemplate {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var name: String = ""
    public var orderIndex: Int = 0
    public var focus: String = ""
    public var program: Program?
    @Relationship(deleteRule: .nullify, inverse: \ExerciseTemplate.workoutDayTemplate)
    public var exerciseTemplates: [ExerciseTemplate]? = nil
    @Relationship(deleteRule: .nullify, inverse: \WarmupItem.workoutDayTemplate)
    public var warmupItems: [WarmupItem]? = nil
    @Relationship(deleteRule: .nullify, inverse: \CooldownItem.workoutDayTemplate)
    public var cooldownItems: [CooldownItem]? = nil

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        name: String = "", orderIndex: Int = 0, focus: String = "", program: Program? = nil,
        exerciseTemplates: [ExerciseTemplate]? = nil, warmupItems: [WarmupItem]? = nil,
        cooldownItems: [CooldownItem]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.orderIndex = orderIndex
        self.focus = focus
        self.program = program
        self.exerciseTemplates = exerciseTemplates
        self.warmupItems = warmupItems
        self.cooldownItems = cooldownItems
    }
}
