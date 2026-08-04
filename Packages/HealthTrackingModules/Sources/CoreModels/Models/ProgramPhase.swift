import Foundation
import SwiftData

@Model
public final class ProgramPhase {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var name: String = ""
    public var orderIndex: Int = 0
    public var monthStart: Int = 0
    public var monthEnd: Int = 0
    public var trainingFocus: String = ""
    public var nutritionFocus: String = ""
    public var milestone: String = ""
    public var entryCriteria: String = ""
    public var program: Program?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        name: String = "", orderIndex: Int = 0, monthStart: Int = 0, monthEnd: Int = 0,
        trainingFocus: String = "", nutritionFocus: String = "", milestone: String = "",
        entryCriteria: String = "", program: Program? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.orderIndex = orderIndex
        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.trainingFocus = trainingFocus
        self.nutritionFocus = nutritionFocus
        self.milestone = milestone
        self.entryCriteria = entryCriteria
        self.program = program
    }
}
