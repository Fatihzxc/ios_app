import Combine
import DesignSystem
import SwiftUI

@MainActor
struct AppBootstrapView: View {
    @StateObject private var runtime: AppBootstrapRuntime
    private let makeContent: @MainActor (any AppDependencyLoading) -> AnyView

    init(
        resolveEnvironment: @escaping @MainActor () throws -> AppEnvironment = {
            try AppLaunchEnvironment.resolve()
        },
        makeDependencies: @escaping @MainActor (AppEnvironment) throws -> any AppDependencyLoading = {
            try AppDependencies(environment: $0)
        },
        makeContent: @escaping @MainActor (any AppDependencyLoading) -> AnyView = {
            dependencies in
            guard let dependencies = dependencies as? AppDependencies else {
                return AnyView(AppFatalConfigurationView())
            }
            return AnyView(
                AppRootView(
                    foundationViewModel: dependencies.foundationViewModel,
                    shouldLoadFoundation: dependencies.shouldLoadFoundation,
                    persistencePresentation: dependencies.persistencePresentation
                )
            )
        }
    ) {
        let runtime = AppBootstrapRuntime(
            resolveEnvironment: resolveEnvironment,
            makeDependencies: makeDependencies
        )
        _runtime = StateObject(wrappedValue: runtime)
        self.makeContent = makeContent
    }

    var bootstrapModel: AppBootstrapModel { runtime.model }
    var dependencies: (any AppDependencyLoading)? { runtime.dependencies }

    var body: some View {
        BootstrapContent(runtime: runtime, makeContent: makeContent)
        .preferredColorScheme(runtime.preferredColorScheme)
        .task {
            guard !runtime.hasFatalConfigurationError else { return }
            await runtime.model.loadIfNeeded()
        }
    }
}

@MainActor
private struct BootstrapContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let runtime: AppBootstrapRuntime
    @ObservedObject private var model: AppBootstrapModel
    private let makeContent: @MainActor (any AppDependencyLoading) -> AnyView

    init(
        runtime: AppBootstrapRuntime,
        makeContent: @escaping @MainActor (any AppDependencyLoading) -> AnyView
    ) {
        self.runtime = runtime
        _model = ObservedObject(wrappedValue: runtime.model)
        self.makeContent = makeContent
    }

    var body: some View {
        Group {
            if runtime.hasFatalConfigurationError {
                AppFatalConfigurationView()
            } else {
                bootstrapContent
            }
        }
    }

    @ViewBuilder
    private var bootstrapContent: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(AppColors.color(.inkSecondary, scheme: colorScheme))
                Text(String(localized: "bootstrap.loading"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .accessibilityIdentifier("bootstrap.loading")
        case .content:
            if let dependencies = runtime.dependencies {
                makeContent(dependencies)
            } else {
                AppFatalConfigurationView()
            }
        case .error:
            VStack(spacing: 16) {
                Text(String(localized: "bootstrap.error"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                Button(String(localized: "bootstrap.retry")) {
                    Task { await model.retry() }
                }
                .font(AppTypography.label)
                .foregroundStyle(AppColors.color(.accentAction, scheme: colorScheme))
                .frame(minWidth: 44, minHeight: 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .accessibilityIdentifier("bootstrap.error")
        }
    }

}

struct AppFatalConfigurationView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(String(localized: "bootstrap.configurationError"))
            .font(AppTypography.body)
            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .accessibilityIdentifier("app.state.fatal-configuration")
    }
}

@MainActor
final class AppBootstrapRuntime: ObservableObject {
    let model: AppBootstrapModel
    let hasFatalConfigurationError: Bool
    let preferredColorScheme: ColorScheme?
    private let bootstrapAttempt: AppBootstrapAttempt?

    init(
        resolveEnvironment: @escaping @MainActor () throws -> AppEnvironment,
        makeDependencies: @escaping @MainActor (AppEnvironment) throws -> any AppDependencyLoading
    ) {
        do {
            let environment = try resolveEnvironment()
            let attempt = AppBootstrapAttempt(
                environment: environment,
                makeDependencies: makeDependencies
            )
            bootstrapAttempt = attempt
            model = AppBootstrapModel(load: { try attempt.load() })
            hasFatalConfigurationError = false
            #if DEBUG
            preferredColorScheme = environment == .uiTesting
                ? AppUITestLaunchConfiguration.resolve()?.appearance.colorScheme
                : nil
            #else
            preferredColorScheme = nil
            #endif
        } catch {
            bootstrapAttempt = nil
            model = AppBootstrapModel(load: {})
            hasFatalConfigurationError = true
            #if DEBUG
            preferredColorScheme = AppUITestLaunchConfiguration.resolve()?.appearance.colorScheme
            #else
            preferredColorScheme = nil
            #endif
        }
    }

    var dependencies: (any AppDependencyLoading)? {
        bootstrapAttempt?.dependencies
    }
}

@MainActor
private final class AppBootstrapAttempt {
    private let environment: AppEnvironment
    private let makeDependencies: @MainActor (AppEnvironment) throws -> any AppDependencyLoading

    private(set) var dependencies: (any AppDependencyLoading)?

    init(
        environment: AppEnvironment,
        makeDependencies: @escaping @MainActor (AppEnvironment) throws -> any AppDependencyLoading
    ) {
        self.environment = environment
        self.makeDependencies = makeDependencies
    }

    func load() throws {
        let dependencies = try makeDependencies(environment)
        try dependencies.load()
        self.dependencies = dependencies
    }
}
