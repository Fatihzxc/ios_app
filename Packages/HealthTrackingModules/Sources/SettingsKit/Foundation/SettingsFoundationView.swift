import DesignSystem
import SwiftUI

public enum FoundationPersistencePresentation: Equatable, Sendable {
    case uiTestingInMemory
    case localStore
    case iCloudConfigured
}

public struct SettingsFoundationView: View {
    private enum Route: Hashable {
        case designSystemGallery
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var path: [Route] = []
    private let persistencePresentation: FoundationPersistencePresentation

    public init(persistencePresentation: FoundationPersistencePresentation) {
        self.persistencePresentation = persistencePresentation
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
}
