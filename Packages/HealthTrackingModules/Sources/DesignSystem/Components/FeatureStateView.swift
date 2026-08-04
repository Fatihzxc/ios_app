import SwiftUI

public enum FeatureState {
    case loading
    case empty(
        message: String,
        actionTitle: String,
        actionAccessibilityLabel: String,
        action: @MainActor () -> Void
    )
    case error(message: String)
}

@MainActor
public struct FeatureStateView: View {
    static let retryForegroundRole: AppColorRole = .accentAction

    @Environment(\.colorScheme) private var colorScheme

    private let state: FeatureState
    private let retry: (@MainActor () -> Void)?

    public init(state: FeatureState, retry: (@MainActor () -> Void)? = nil) {
        self.state = state
        self.retry = retry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            switch state {
            case .loading:
                HStack(spacing: AppSpacing.small) {
                    LoadingIndicator(color: AppColors.color(.inkSecondary, scheme: colorScheme))
                    Text(String(localized: "designSystem.featureState.loading", bundle: .module))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                }
            case let .empty(message, actionTitle, actionAccessibilityLabel, action):
                Image(systemName: "tray")
                    .foregroundStyle(AppColors.color(.stateInfo, scheme: colorScheme))
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                PrimaryActionButton(
                    title: actionTitle,
                    accessibilityLabel: actionAccessibilityLabel,
                    action: action
                )
            case let .error(message):
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                if let retry {
                    Button(String(localized: "designSystem.featureState.retry", bundle: .module), action: retry)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.color(Self.retryForegroundRole, scheme: colorScheme))
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct LoadingIndicator: View {
    let color: Color

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}
