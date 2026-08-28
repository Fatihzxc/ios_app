import Foundation
import Observation

public enum HealthCheckNotificationAuthorizationState: Equatable, Sendable {
    case idle
    case requesting
    case authorized
    case denied
    case failed
}

@MainActor
@Observable
public final class HealthCheckNotificationAuthorizationController {
    public private(set) var state: HealthCheckNotificationAuthorizationState = .idle

    @ObservationIgnored
    private let center: any NotificationCenterClient
    @ObservationIgnored
    private var generation: UInt64 = 0
    @ObservationIgnored
    private var isRequestInFlight = false
    @ObservationIgnored
    private var isPresented = false

    public init(center: any NotificationCenterClient) {
        self.center = center
    }

    public func beginPresentation() {
        generation += 1
        isPresented = true
        isRequestInFlight = false
        state = .idle
    }

    public func dismiss() {
        generation += 1
        isPresented = false
        isRequestInFlight = false
        state = .idle
    }

    public func requestFromExplicitUserAction() async {
        guard !isRequestInFlight, isPresented else { return }
        generation += 1
        let requestGeneration = generation
        isRequestInFlight = true
        state = .requesting
        do {
            let granted = try await center.requestAuthorization()
            guard generation == requestGeneration else { return }
            isRequestInFlight = false
            state = granted ? .authorized : .denied
        } catch {
            guard generation == requestGeneration else { return }
            isRequestInFlight = false
            state = .failed
        }
    }
}
