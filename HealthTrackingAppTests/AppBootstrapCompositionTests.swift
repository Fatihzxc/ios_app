@testable import HealthTrackingApp
import XCTest

@MainActor
final class AppBootstrapCompositionTests: XCTestCase {
    // Mutation caught: removing a default or injected closure parameter from the
    // production bootstrap initializer would disconnect the live and test paths.
    // A GREEN source review must additionally reject a competing no-argument bypass.
    func testDefaultableProductionInitializerCompileContract() {
        withExtendedLifetime(Self.initializerCallsAreTypeChecked) {}
    }

    // Mutation caught: constructing dependencies during runtime initialization would
    // prevent the bootstrap loading attempt from covering construction/seed.
    func testRuntimeInitializesEnvironmentOnceButDefersDependenciesUntilImplicitLoad() async {
        var environmentResolutions = 0
        var constructionAttempts = 0
        let dependency = RecordingDependencies()
        let runtime = AppBootstrapRuntime(
            resolveEnvironment: {
                environmentResolutions += 1
                return .uiTesting
            },
            makeDependencies: { _ in
                constructionAttempts += 1
                return dependency
            }
        )

        XCTAssertEqual(environmentResolutions, 1)
        XCTAssertEqual(constructionAttempts, 0)
        XCTAssertEqual(dependency.loadAttempts, 0)
        XCTAssertNil(runtime.dependencies)

        await runtime.model.loadIfNeeded()

        XCTAssertEqual(runtime.model.state, .content)
        XCTAssertEqual(constructionAttempts, 1)
        XCTAssertEqual(dependency.loadAttempts, 1)
        XCTAssertTrue(runtime.dependencies === dependency)
    }

    // Mutation caught: classifying a construction error as fatal would prevent the
    // runtime retry path from performing a complete second construction.
    func testRuntimeConstructionFailureIsRecoverableAndRetryConstructsThenSeedsAgain() async {
        var constructionAttempts = 0
        let dependency = RecordingDependencies()
        let runtime = AppBootstrapRuntime(
            resolveEnvironment: { .uiTesting },
            makeDependencies: { _ in
                constructionAttempts += 1
                if constructionAttempts == 1 {
                    throw ConstructionFailure()
                }
                return dependency
            }
        )

        await runtime.model.loadIfNeeded()

        XCTAssertEqual(runtime.model.state, .error)
        XCTAssertEqual(constructionAttempts, 1)
        XCTAssertEqual(dependency.loadAttempts, 0)
        XCTAssertNil(runtime.dependencies)

        await runtime.model.retry()

        XCTAssertEqual(runtime.model.state, .content)
        XCTAssertEqual(constructionAttempts, 2)
        XCTAssertEqual(dependency.loadAttempts, 1)
        XCTAssertTrue(runtime.dependencies === dependency)
    }

    // Mutation caught: retaining a dependency before its seed/load succeeds would
    // let retry reuse a failed instance instead of constructing a fresh composition.
    func testRuntimeSeedFailureIsRecoverableAndRetryRetainsOnlySecondSuccessfulDependencies() async {
        var constructionAttempts = 0
        let failedDependency = RecordingDependencies(loadError: LoadFailure())
        let successfulDependency = RecordingDependencies()
        let runtime = AppBootstrapRuntime(
            resolveEnvironment: { .uiTesting },
            makeDependencies: { _ in
                constructionAttempts += 1
                return constructionAttempts == 1 ? failedDependency : successfulDependency
            }
        )

        await runtime.model.loadIfNeeded()

        XCTAssertEqual(runtime.model.state, .error)
        XCTAssertEqual(constructionAttempts, 1)
        XCTAssertEqual(failedDependency.loadAttempts, 1)
        XCTAssertEqual(successfulDependency.loadAttempts, 0)
        XCTAssertNil(runtime.dependencies)

        await runtime.model.retry()

        XCTAssertEqual(runtime.model.state, .content)
        XCTAssertEqual(constructionAttempts, 2)
        XCTAssertEqual(failedDependency.loadAttempts, 1)
        XCTAssertEqual(successfulDependency.loadAttempts, 1)
        XCTAssertTrue(runtime.dependencies === successfulDependency)
    }

    // Intentionally uninvoked: each call is type-checked without evaluating live
    // AppEnvironment resolution or default dependency construction on the host.
    private static let initializerCallsAreTypeChecked: () -> Void = {
        _ = AppBootstrapView()
        _ = AppBootstrapView(resolveEnvironment: { .uiTesting })
        _ = AppBootstrapView(makeDependencies: { _ in TypeCheckDependencies() })
        _ = AppBootstrapView(
            resolveEnvironment: { .uiTesting },
            makeDependencies: { _ in TypeCheckDependencies() }
        )
    }

    private final class RecordingDependencies: AppDependencyLoading {
        private(set) var loadAttempts = 0
        private let loadError: Error?

        init(loadError: Error? = nil) {
            self.loadError = loadError
        }

        func load() throws {
            loadAttempts += 1
            if let loadError {
                throw loadError
            }
        }
    }

    private final class TypeCheckDependencies: AppDependencyLoading {
        func load() throws {}
    }

    private struct ConstructionFailure: Error {}
    private struct LoadFailure: Error {}
}
