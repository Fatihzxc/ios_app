public enum MedicalSafetyMotionPolicy {
    public static func transition<Value>(
        reduceMotion: Bool,
        identity: Value,
        opacity: Value
    ) -> Value {
        guard !reduceMotion else { return identity }
        return opacity
    }
}
