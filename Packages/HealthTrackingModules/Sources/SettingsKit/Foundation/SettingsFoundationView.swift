import DesignSystem
import SwiftUI
import TrainingKit

public enum FoundationPersistencePresentation: Equatable, Sendable {
    case uiTestingInMemory
    case localStore
    case iCloudConfigured
}

public struct SettingsFoundationView: View {
    private enum Route: Hashable {
        case designSystemGallery
        case programPhase
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var path: [Route] = []
    @State private var hapticPreferenceSaveFailed = false
    private let persistencePresentation: FoundationPersistencePresentation
    private let phaseTransitionViewModel: PhaseTransitionViewModel?
    private let trainingHapticController: TrainingHapticController?

    public init(
        persistencePresentation: FoundationPersistencePresentation,
        phaseTransitionViewModel: PhaseTransitionViewModel? = nil,
        trainingHapticController: TrainingHapticController? = nil
    ) {
        self.persistencePresentation = persistencePresentation
        self.phaseTransitionViewModel = phaseTransitionViewModel
        self.trainingHapticController = trainingHapticController
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.standard) {
                            Text(String(localized: "settings.persistence.heading", bundle: .module))
                                .font(AppTypography.titleMedium)
                                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("root.settings.content")
                            Text(persistenceMessage)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let trainingHapticController {
                        AppCard {
                            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                Toggle(
                                    isOn: Binding(
                                        get: { trainingHapticController.isEnabled },
                                        set: { isEnabled in
                                            updateHaptics(
                                                isEnabled,
                                                controller: trainingHapticController
                                            )
                                        }
                                    )
                                ) {
                                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                                        Text(
                                            String(
                                                localized: "settings.haptics.title",
                                                bundle: .module
                                            )
                                        )
                                        .font(AppTypography.label)
                                        .foregroundStyle(
                                            AppColors.color(.inkPrimary, scheme: colorScheme)
                                        )
                                        Text(
                                            String(
                                                localized: "settings.haptics.detail",
                                                bundle: .module
                                            )
                                        )
                                        .font(AppTypography.caption)
                                        .foregroundStyle(
                                            AppColors.color(.inkSecondary, scheme: colorScheme)
                                        )
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .accessibilityIdentifier("settings.haptics-toggle")
                                .accessibilityHint(
                                    String(
                                        localized: "settings.haptics.hint",
                                        bundle: .module
                                    )
                                )

                                if hapticPreferenceSaveFailed ||
                                    trainingHapticController.preferenceState == .failed {
                                    Text(
                                        String(
                                            localized: "settings.haptics.saveError",
                                            bundle: .module
                                        )
                                    )
                                    .font(AppTypography.caption)
                                    .foregroundStyle(
                                        AppColors.color(.stateDanger, scheme: colorScheme)
                                    )
                                    .accessibilityIdentifier("settings.haptics-error")
                                }
                            }
                        }
                    }

                    AppCard {
                        NavigationLink(value: Route.designSystemGallery) {
                            Label(
                                String(localized: "settings.gallery.title", bundle: .module),
                                systemImage: "paintpalette"
                            )
                            .font(AppTypography.label)
                            .foregroundStyle(AppColors.color(.accentAction, scheme: colorScheme))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("settings.gallery-link")
                        .accessibilityHint(String(localized: "settings.gallery.hint", bundle: .module))
                    }

                    if phaseTransitionViewModel != nil {
                        AppCard {
                            NavigationLink(value: Route.programPhase) {
                                Label(
                                    String(localized: "settings.phase.title", bundle: .module),
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                                .font(AppTypography.label)
                                .foregroundStyle(
                                    AppColors.color(.accentAction, scheme: colorScheme)
                                )
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("settings.phase-link")
                            .accessibilityHint(
                                String(localized: "settings.phase.hint", bundle: .module)
                            )
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.large)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(String(localized: "settings.foundation.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .designSystemGallery:
                    DesignSystemGalleryView()
                        .navigationTitle(String(localized: "settings.foundation.title", bundle: .module))
                case .programPhase:
                    if let phaseTransitionViewModel {
                        ManualPhaseSelectionView(viewModel: phaseTransitionViewModel)
                    }
                }
            }
        }
        .accessibilityIdentifier("root.settings")
    }

    private var persistenceMessage: String {
        switch persistencePresentation {
        case .uiTestingInMemory:
            String(localized: "settings.persistence.uiTesting", bundle: .module)
        case .localStore:
            String(localized: "settings.persistence.local", bundle: .module)
        case .iCloudConfigured:
            String(localized: "settings.persistence.iCloudConfigured", bundle: .module)
        }
    }

    private func updateHaptics(
        _ isEnabled: Bool,
        controller: TrainingHapticController
    ) {
        do {
            try controller.setEnabled(isEnabled)
            hapticPreferenceSaveFailed = false
        } catch {
            hapticPreferenceSaveFailed = true
        }
    }
}
