import Combine

@MainActor
final class AppBootstrapModel: ObservableObject {
    enum State: Equatable {
        case loading
        case content
        case error
    }

    @Published private(set) var state: State = .loading

    private let load: @MainActor () async throws -> Void
    private var hasAttemptedImplicitLoad = false

    init(load: @escaping @MainActor () async throws -> Void) {
        self.load = load
    }

    func loadIfNeeded() async {
        guard !hasAttemptedImplicitLoad else { return }
        hasAttemptedImplicitLoad = true
        await performLoad()
    }

    func retry() async {
        hasAttemptedImplicitLoad = true
        await performLoad()
    }

    private func performLoad() async {
        state = .loading
        do {
            try await load()
            state = .content
        } catch {
            state = .error
        }
    }
}
