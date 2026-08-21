import TrainingKit
import UIKit

@MainActor
final class UIKitTrainingHapticClient: TrainingHapticClient {
    private lazy var mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private lazy var selectionGenerator = UISelectionFeedbackGenerator()
    private lazy var notificationGenerator = UINotificationFeedbackGenerator()

    func play(_ feedback: TrainingHapticFeedback) {
        switch feedback {
        case .mediumImpact:
            mediumImpactGenerator.prepare()
            mediumImpactGenerator.impactOccurred()
        case .selection:
            selectionGenerator.prepare()
            selectionGenerator.selectionChanged()
        case .success:
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(.success)
        case .warning:
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(.warning)
        case .error:
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(.error)
        }
    }
}
