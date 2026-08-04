import SwiftData

public enum HealthTrackingSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            Program.self,
            ProgramPhase.self,
            WorkoutDayTemplate.self,
            ExerciseTemplate.self,
            WarmupItem.self,
            CooldownItem.self,
            WorkoutSession.self,
            SetLog.self,
            ProgramState.self,
            BodyMetric.self,
            ProgressPhoto.self,
            SleepLog.self,
            MoodLog.self,
            PostureMetric.self,
            HealthCheckReminder.self,
            BloodworkResult.self,
            Food.self,
            Recipe.self,
            DailyNutritionLog.self,
            MealEntry.self,
            AppReminder.self,
            AppSetting.self
        ]
    }
}
