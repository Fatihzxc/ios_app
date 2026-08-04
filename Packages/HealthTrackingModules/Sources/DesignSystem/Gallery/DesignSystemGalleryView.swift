import SwiftUI

public struct DesignSystemGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ScrollView {
            GalleryContentView()
        }
        .background(AppColors.color(.backgroundBase, scheme: colorScheme))
        .accessibilityIdentifier("designSystem.gallery")
    }
}

struct GalleryContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var actionFeedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            Text(String(localized: "designSystem.gallery.title", bundle: .module))
                .font(AppTypography.titleLarge)

            GallerySchemeView(scheme: .light, actionFeedback: $actionFeedback)
            GallerySchemeView(scheme: .dark, actionFeedback: $actionFeedback)

            if let actionFeedback {
                Text(actionFeedback)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .accessibilityIdentifier("designSystem.gallery.actionFeedback")
            }

            Text(String(localized: "designSystem.gallery.dynamicType", bundle: .module))
                .font(AppTypography.titleMedium)
            AppCard {
                Text(String(localized: "designSystem.gallery.dynamicTypeSample", bundle: .module))
                    .font(AppTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.large)
    }
}

private struct GallerySchemeView: View {
    let scheme: ColorScheme
    @Binding var actionFeedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            Text(String(localized: scheme == .dark ? "designSystem.gallery.dark" : "designSystem.gallery.light", bundle: .module))
                .font(AppTypography.titleMedium)

            Text(String(localized: "designSystem.gallery.colors", bundle: .module))
                .font(AppTypography.label)
            Grid(horizontalSpacing: AppSpacing.compact, verticalSpacing: AppSpacing.compact) {
                let roles = AppColorRole.allCases
                ForEach(Array(stride(from: 0, to: roles.count, by: 2)), id: \.self) { index in
                    GridRow {
                        ColorTokenCell(role: roles[index], scheme: scheme)
                        if index + 1 < roles.count {
                            ColorTokenCell(role: roles[index + 1], scheme: scheme)
                        }
                    }
                }
            }

            Text(String(localized: "designSystem.gallery.components", bundle: .module))
                .font(AppTypography.label)
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    Text(String(localized: "designSystem.gallery.componentTitle", bundle: .module))
                        .font(AppTypography.titleMedium)
                    StatusPill(
                        text: String(localized: "designSystem.gallery.statusReady", bundle: .module),
                        systemImage: "checkmark.circle.fill",
                        style: .success
                    )
                    PrimaryActionButton(
                        title: String(localized: "designSystem.gallery.actionTitle", bundle: .module),
                        accessibilityLabel: String(localized: "designSystem.gallery.actionAccessibility", bundle: .module),
                        isEnabled: false,
                        action: {}
                    )
                }
            }
            FeatureStateView(state: .loading)
            FeatureStateView(
                state: .empty(
                    message: String(localized: "designSystem.gallery.emptyMessage", bundle: .module),
                    actionTitle: String(localized: "designSystem.gallery.emptyActionTitle", bundle: .module),
                    actionAccessibilityLabel: String(localized: "designSystem.gallery.emptyActionAccessibility", bundle: .module),
                    action: {
                        actionFeedback = String(localized: "designSystem.gallery.emptyActionConfirmation", bundle: .module)
                    }
                )
            )
            FeatureStateView(state: .error(message: String(localized: "designSystem.gallery.errorMessage", bundle: .module)))
            FeatureStateView(
                state: .error(message: String(localized: "designSystem.gallery.errorMessage", bundle: .module)),
                retry: {
                    actionFeedback = String(localized: "designSystem.gallery.retryConfirmation", bundle: .module)
                }
            )
        }
        .padding(AppSpacing.comfortable)
        .background(AppColors.color(.backgroundSunken, scheme: scheme))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous))
        .environment(\.colorScheme, scheme)
    }
}

private struct ColorTokenCell: View {
    let role: AppColorRole
    let scheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .fill(AppColors.color(role, scheme: scheme))
                .frame(height: 36)
                .overlay {
                    if role == .borderStrong {
                        RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                            .stroke(AppColors.color(.borderStrong, scheme: scheme), lineWidth: 2)
                    }
                }
            Text(String(localized: String.LocalizationValue(labelKey), bundle: .module))
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var labelKey: String {
        switch role {
        case .backgroundBase: "designSystem.role.backgroundBase"
        case .backgroundRaised: "designSystem.role.backgroundRaised"
        case .backgroundSunken: "designSystem.role.backgroundSunken"
        case .inkPrimary: "designSystem.role.inkPrimary"
        case .inkSecondary: "designSystem.role.inkSecondary"
        case .inkTertiary: "designSystem.role.inkTertiary"
        case .accentAction: "designSystem.role.accentAction"
        case .accentOnAction: "designSystem.role.accentOnAction"
        case .stateSuccess: "designSystem.role.stateSuccess"
        case .stateWarning: "designSystem.role.stateWarning"
        case .stateDanger: "designSystem.role.stateDanger"
        case .stateInfo: "designSystem.role.stateInfo"
        case .borderHairline: "designSystem.role.borderHairline"
        case .borderStrong: "designSystem.role.borderStrong"
        }
    }
}
