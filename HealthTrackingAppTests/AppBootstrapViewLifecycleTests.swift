@testable import HealthTrackingApp
import SwiftUI
import UIKit
import XCTest

@MainActor
final class AppBootstrapViewLifecycleTests: XCTestCase {
    // Mutation caught: retaining AppBootstrapModel in @StateObject while keeping
    // the successful dependency attempt in plain AppBootstrapView fields loses the
    // dependency-to-content handoff when a parent rebuilds this child in place.
    func testParentRebuildKeepsRenderedContentOnOriginalDependency() async {
        let driver = RebuildDriver()
        let probe = ContentProbe(
            initialContent: expectation(description: "initial bootstrap content"),
            rebuiltContent: expectation(description: "rebuilt bootstrap content")
        )
        let dependency = RecordingDependencies()
        var constructionAttempts = 0
        let harness = BootstrapHarness(
            driver: driver,
            probe: probe,
            resolveEnvironment: { .uiTesting },
            makeDependencies: { _ in
                constructionAttempts += 1
                return dependency
            }
        )
        let host = UIHostingController(rootView: harness)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.beginAppearanceTransition(true, animated: false)
        host.endAppearanceTransition()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        await fulfillment(of: [probe.initialContent], timeout: 1)

        XCTAssertEqual(constructionAttempts, 1)
        XCTAssertEqual(dependency.loadAttempts, 1)
        XCTAssertEqual(probe.dependencyIdentifier(for: 0), ObjectIdentifier(dependency))

        driver.rebuild()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()

        await fulfillment(of: [probe.rebuiltContent], timeout: 1)

        XCTAssertEqual(constructionAttempts, 1)
        XCTAssertEqual(dependency.loadAttempts, 1)
        XCTAssertEqual(probe.dependencyIdentifier(for: 1), ObjectIdentifier(dependency))
    }

    @MainActor
    private final class RebuildDriver: ObservableObject {
        @Published private(set) var revision = 0

        func rebuild() {
            revision += 1
        }
    }

    @MainActor
    private struct BootstrapHarness: View {
        @ObservedObject var driver: RebuildDriver
        let probe: ContentProbe
        let resolveEnvironment: @MainActor () throws -> AppEnvironment
        let makeDependencies: @MainActor (AppEnvironment) async throws -> any AppDependencyLoading

        var body: some View {
            // The revision read invalidates this parent. AppBootstrapView remains at
            // this unconditional structural position, with no explicit identity.
            let revision = driver.revision
            AppBootstrapView(
                resolveEnvironment: resolveEnvironment,
                makeDependencies: makeDependencies,
                makeContent: { dependencies in
                    AnyView(
                        RenderedContentProbe(
                            dependencies: dependencies,
                            revision: revision,
                            probe: probe
                        )
                    )
                }
            )
        }
    }

    @MainActor
    private struct RenderedContentProbe: View {
        let dependencies: any AppDependencyLoading
        let revision: Int
        let probe: ContentProbe

        var body: some View {
            Color.clear
                .onAppear {
                    probe.record(dependencies: dependencies, revision: revision)
                }
                .onChange(of: revision) { _, newRevision in
                    probe.record(dependencies: dependencies, revision: newRevision)
                }
        }
    }

    @MainActor
    private final class ContentProbe {
        let initialContent: XCTestExpectation
        let rebuiltContent: XCTestExpectation
        private var dependencyIdentifiers: [Int: ObjectIdentifier] = [:]

        init(initialContent: XCTestExpectation, rebuiltContent: XCTestExpectation) {
            self.initialContent = initialContent
            self.rebuiltContent = rebuiltContent
        }

        func record(dependencies: any AppDependencyLoading, revision: Int) {
            guard dependencyIdentifiers[revision] == nil else { return }

            dependencyIdentifiers[revision] = ObjectIdentifier(dependencies)
            switch revision {
            case 0:
                initialContent.fulfill()
            case 1:
                rebuiltContent.fulfill()
            default:
                break
            }
        }

        func dependencyIdentifier(for revision: Int) -> ObjectIdentifier? {
            dependencyIdentifiers[revision]
        }
    }

    @MainActor
    private final class RecordingDependencies: AppDependencyLoading {
        private(set) var loadAttempts = 0

        func load() throws {
            loadAttempts += 1
        }
    }
}
