public enum EpleyEstimate {
    private static let comparisonTolerance = 0.000_000_001

    public static func calculate(weightKg: Double?, reps: Int?) -> Double? {
        guard let weightKg,
              let reps,
              weightKg.isFinite,
              weightKg > 0,
              reps > 0,
              reps <= Int.max - 30 else {
            return nil
        }
        let factored = weightKg * (1 + Double(reps) / 30)
        let rational = weightKg * Double(30 + reps) / 30
        // Equivalent binary paths can differ by one ULP. Keep the conservative
        // full-precision value so floating-point noise cannot manufacture a PR.
        return min(factored, rational)
    }

    public static func isImprovement(_ candidate: Double, over previousBest: Double) -> Bool {
        candidate.isFinite &&
            previousBest.isFinite &&
            candidate - previousBest > comparisonTolerance
    }
}
