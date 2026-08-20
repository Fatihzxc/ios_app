public enum EpleyEstimate {
    private static let comparisonTolerance = 0.000_000_001

    public static func calculate(weightKg: Double?, reps: Int?) -> Double? {
        guard let weightKg,
              let reps,
              weightKg.isFinite,
              weightKg > 0,
              reps > 0 else {
            return nil
        }
        return weightKg * (1 + Double(reps) / 30)
    }

    public static func isImprovement(_ candidate: Double, over previousBest: Double) -> Bool {
        candidate.isFinite &&
            previousBest.isFinite &&
            candidate - previousBest > comparisonTolerance
    }
}
