import Foundation
import SwiftData

@Model
public final class ExerciseTemplate {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var name: String = ""
    public var orderIndex: Int = 0
    public var targetSets: Int = 0
    public var repLow: Int?
    public var repHigh: Int?
    public var rirLow: Int = 0
    public var rirHigh: Int = 0
    public var category: ExerciseCategory = ExerciseCategory.accessory
    public var allowFailure: Bool = false
    public var cues: String = ""
    public var safetyNote: String?
    public var startingWeightKg: Double?
    public var progressionRule: ProgressionRule = ProgressionRule.doubleProgression
    public var measurementKind: ExerciseMeasurementKind = ExerciseMeasurementKind.weightReps
    public var supersetGroupId: UUID?
    public var supersetOrder: Int?
    public var workoutDayTemplate: WorkoutDayTemplate?

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        name: String = "", orderIndex: Int = 0, targetSets: Int = 0, repLow: Int? = nil,
        repHigh: Int? = nil, rirLow: Int = 0, rirHigh: Int = 0,
        category: ExerciseCategory = .accessory, allowFailure: Bool = false, cues: String = "",
        safetyNote: String? = nil, startingWeightKg: Double? = nil,
        progressionRule: ProgressionRule = .doubleProgression,
        measurementKind: ExerciseMeasurementKind = .weightReps, supersetGroupId: UUID? = nil,
        supersetOrder: Int? = nil, workoutDayTemplate: WorkoutDayTemplate? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.repLow = repLow
        self.repHigh = repHigh
        self.rirLow = rirLow
        self.rirHigh = rirHigh
        self.category = category
        self.allowFailure = allowFailure
        self.cues = cues
        self.safetyNote = safetyNote
        self.startingWeightKg = startingWeightKg
        self.progressionRule = progressionRule
        self.measurementKind = measurementKind
        self.supersetGroupId = supersetGroupId
        self.supersetOrder = supersetOrder
        self.workoutDayTemplate = workoutDayTemplate
    }
}
