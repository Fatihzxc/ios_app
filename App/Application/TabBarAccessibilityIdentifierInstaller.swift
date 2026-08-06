import SwiftUI
import UIKit

/// Assigns UI-test identifiers to the native tab bar items created by SwiftUI.
///
/// SwiftUI does not propagate a `Tab` accessibility identifier to its backing
/// `UITabBarItem`, so the native items need to be configured after the tab bar
/// has joined the view-controller hierarchy.
@MainActor
struct TabBarAccessibilityIdentifierInstaller: UIViewControllerRepresentable {
    let identifiers: [String]

    func makeUIViewController(context: Context) -> TabBarAccessibilityIdentifierInstallerViewController {
        TabBarAccessibilityIdentifierInstallerViewController(identifiers: identifiers)
    }

    func updateUIViewController(
        _ uiViewController: TabBarAccessibilityIdentifierInstallerViewController,
        context: Context
    ) {
        uiViewController.updateIdentifiers(identifiers)
    }
}

@MainActor
final class TabBarAccessibilityIdentifierInstallerViewController: UIViewController {
    private static let retryDuration = Duration.seconds(5)
    private static let retryInterval = Duration.milliseconds(200)

    private var identifiers: [String]
    private var retryTask: Task<Void, Never>?
    private var retryGeneration = 0

    init(identifiers: [String]) {
        self.identifiers = identifiers
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        retryTask?.cancel()
    }

    override func loadView() {
        let view = UIView(frame: .zero)
        view.isAccessibilityElement = false
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)

        if parent == nil {
            stopRetryWindow()
        } else {
            startRetryWindow()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRetryWindow()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopRetryWindow()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        startRetryWindow()
    }

    func updateIdentifiers(_ identifiers: [String]) {
        self.identifiers = identifiers
        startRetryWindow()
    }

    private func startRetryWindow() {
        guard parent != nil else { return }
        _ = installIdentifiersIfPossible()

        guard retryTask == nil else { return }
        retryGeneration &+= 1
        let generation = retryGeneration
        let retryDuration = Self.retryDuration
        let retryInterval = Self.retryInterval

        retryTask = Task { @MainActor [weak self, retryDuration, retryInterval] in
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: retryDuration)

            while !Task.isCancelled, clock.now < deadline {
                _ = self?.installIdentifiersIfPossible()

                do {
                    try await Task.sleep(for: retryInterval)
                } catch {
                    break
                }
            }

            self?.finishRetryWindow(generation: generation)
        }
    }

    private func stopRetryWindow() {
        retryGeneration &+= 1
        retryTask?.cancel()
        retryTask = nil
    }

    private func finishRetryWindow(generation: Int) {
        guard generation == retryGeneration else { return }
        retryTask = nil
    }

    @discardableResult
    private func installIdentifiersIfPossible() -> Bool {
        guard
            let tabBar = enclosingTabBar(),
            let items = tabBar.items
        else {
            return false
        }

        for (item, identifier) in zip(items, identifiers)
        where item.accessibilityIdentifier != identifier {
            item.accessibilityIdentifier = identifier
        }

        return zip(items, identifiers).allSatisfy { item, identifier in
            item.accessibilityIdentifier == identifier
        }
    }

    private func enclosingTabBar() -> UITabBar? {
        guard let window = viewIfLoaded?.window else { return nil }

        if
            let tabBar = tabBarController?.tabBar,
            isValidCandidate(tabBar, in: window)
        {
            return tabBar
        }

        let candidates = tabBars(in: window).filter {
            isValidCandidate($0, in: window)
        }

        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }

    private func isValidCandidate(_ tabBar: UITabBar, in window: UIWindow) -> Bool {
        guard
            !identifiers.isEmpty,
            tabBar.items?.count == identifiers.count,
            tabBar.window === window,
            tabBar.isDescendant(of: window),
            !tabBar.bounds.isEmpty
        else {
            return false
        }

        var currentView: UIView? = tabBar
        while let current = currentView, current !== window {
            guard !current.isHidden, current.alpha > 0.01 else {
                return false
            }
            currentView = current.superview
        }

        guard
            currentView === window,
            !window.isHidden,
            window.alpha > 0.01
        else {
            return false
        }

        let frameInWindow = tabBar.convert(tabBar.bounds, to: window)
        return !frameInWindow.isEmpty && frameInWindow.intersects(window.bounds)
    }

    private func tabBars(in view: UIView) -> [UITabBar] {
        var results = view.subviews.flatMap(tabBars(in:))

        if let tabBar = view as? UITabBar {
            results.insert(tabBar, at: 0)
        }

        return results
    }
}
