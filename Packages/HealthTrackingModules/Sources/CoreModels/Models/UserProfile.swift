import Foundation
import SwiftData

@Model
public final class UserProfile {
    public var id: UUID = UUID()
    public var createdAt: Date = Foundation.Date.now
    public var updatedAt: Date = Foundation.Date.now
    public var displayName: String = ""
    public var heightCm: Double = 0
    public var startWeightKg: Double = 0
    public var targetWeightKg: Double = 0
    public var birthYear: Int?
    public var unitsSystem: UnitsSystem = UnitsSystem.metric
    public var proteinTargetG: Double = 0
    public var calorieTarget: Double?
    public var carbTargetG: Double?
    public var fatTargetG: Double?
    public var programStartDate: Date = Foundation.Date.now
    public var weeklyWorkoutTarget: Int = 3

    public init(
        id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now,
        displayName: String = "", heightCm: Double = 0, startWeightKg: Double = 0,
        targetWeightKg: Double = 0, birthYear: Int? = nil, unitsSystem: UnitsSystem = .metric,
        proteinTargetG: Double = 0, calorieTarget: Double? = nil, carbTargetG: Double? = nil,
        fatTargetG: Double? = nil, programStartDate: Date = .now, weeklyWorkoutTarget: Int = 3
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.displayName = displayName
        self.heightCm = heightCm
        self.startWeightKg = startWeightKg
        self.targetWeightKg = targetWeightKg
        self.birthYear = birthYear
        self.unitsSystem = unitsSystem
        self.proteinTargetG = proteinTargetG
        self.calorieTarget = calorieTarget
        self.carbTargetG = carbTargetG
        self.fatTargetG = fatTargetG
        self.programStartDate = programStartDate
        self.weeklyWorkoutTarget = weeklyWorkoutTarget
    }
}
