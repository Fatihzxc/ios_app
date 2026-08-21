import Foundation
import Observation

public enum TrainingHapticPreferenceState: Equatable, Sendable {
    case unloaded
    case loaded
    case failed
}

@MainActor
@Observable
public final class TrainingHapticController {
    public private(set) var isEnabled = false
    public private(set) var preferenceState = TrainingHapticPreferenceState.unloaded

    @ObservationIgnored
    private let client: any TrainingHapticClient
    @ObservationIgnored
    private let preferenceStore: any TrainingHapticPreferenceStore
    @ObservationIgnored
    private let selectionThrottle: TimeInterval
    @ObservationIgnored
    private let uptime: @MainActor () -> TimeInterval
    @ObservationIgnored
    private var lastSelectionUptime: TimeInterval?

    public init(
        client: any TrainingHapticClient,
        preferenceStore: any TrainingHapticPreferenceStore,
        selectionThrottle: TimeInterval = 0.1,
        uptime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        precondition(selectionThrottle >= 0, "Selection throttle cannot be negative.")
        self.client = client
        self.preferenceStore = preferenceStore
        self.selectionThrottle = selectionThrottle
        self.uptime = uptime
    }

    public func loadPreference() {
        guard preferenceState != .loaded else { return }
        do {
            isEnabled = try preferenceStore.loadHapticsEnabled()
            preferenceState = .loaded
            lastSelectionUptime = nil
        } catch {
            failClosed()
        }
    }

    public func setEnabled(_ isEnabled: Bool) throws {
        if preferenceState == .unloaded {
            loadPreference()
        }
        guard preferenceState != .failed || self.isEnabled != isEnabled else { return }
        guard self.isEnabled != isEnabled || preferenceState != .loaded else { return }
        do {
            try preferenceStore.saveHapticsEnabled(isEnabled)
            self.isEnabled = isEnabled
            preferenceState = .loaded
            lastSelectionUptime = nil
        } catch {
            failClosed()
            throw error
        }
    }

    public func handle(_ event: TrainingHapticEvent) {
        guard preferenceState == .loaded, isEnabled else { return }
        guard let feedback = feedback(for: event) else { return }
        client.play(feedback)
    }

    private func feedback(for event: TrainingHapticEvent) -> TrainingHapticFeedback? {
        switch event {
        case .setSaved:
            return .mediumImpact
        case .stepperChanged:
            return shouldPlaySelection() ? .selection : nil
        case let .personalRecord(isNew):
            return isNew ? .success : nil
        case let .phaseTransition(isConfirmed):
            return isConfirmed ? .success : nil
        case .safetyStop, .deload:
            return .warning
        case .validationError, .repositoryError:
            return .error
        }
    }

    private func shouldPlaySelection() -> Bool {
        let currentUptime = uptime()
        if let lastSelectionUptime,
           currentUptime >= lastSelectionUptime,
           currentUptime - lastSelectionUptime < selectionThrottle {
            return false
        }
        lastSelectionUptime = currentUptime
        return true
    }

    private func failClosed() {
        isEnabled = false
        preferenceState = .failed
        lastSelectionUptime = nil
    }
}
