import Foundation
import SwiftData

@Model
public final class Program {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var name: String = ""
    public var descriptionText: String = ""
    public var isActive: Bool = false
    @Relationship(deleteRule: .nullify, inverse: \WorkoutDayTemplate.program)
    public var workoutDayTemplates: [WorkoutDayTemplate]? = nil
    @Relationship(deleteRule: .nullify, inverse: \ProgramPhase.program)
    public var programPhases: [ProgramPhase]? = nil

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        name: String = "", descriptionText: String = "", isActive: Bool = false,
        workoutDayTemplates: [WorkoutDayTemplate]? = nil, programPhases: [ProgramPhase]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.descriptionText = descriptionText
        self.isActive = isActive
        self.workoutDayTemplates = workoutDayTemplates
        self.programPhases = programPhases
    }
}
