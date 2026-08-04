import SwiftUI

public struct PrimaryActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    private let title: String
    private let accessibilityLabel: String
    private let isLoading: Bool
    private let isEnabled: Bool
    private let action: () -> Void

    public init(
        title: String,
        accessibilityLabel: String,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.compact) {
                if isLoading {
                    ProgressView()
                        .tint(AppColors.color(.accentOnAction, scheme: colorScheme))
                }
                Text(isLoading ? String(localized: "designSystem.button.loading", bundle: .module) : title)
                    .font(AppTypography.label)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppColors.color(.accentOnAction, scheme: colorScheme))
        .padding(.horizontal, AppSpacing.comfortable)
        .frame(minWidth: 44, minHeight: 44)
        .background(AppColors.color(.accentAction, scheme: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.action, style: .continuous))
        .opacity(isEnabled && !isLoading ? 1.0 : 0.55)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(accessibilityLabel)
    }
}
