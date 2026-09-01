import DesignSystem
import SwiftUI

public struct ReportsFoundationView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ScrollView {
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    Text(String(localized: "reports.dashboard.title", bundle: .module))
                        .font(AppTypography.titleMedium)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: AppSpacing.compact) {
                        ProgressView().accessibilityHidden(true)
                        Text(String(localized: "reports.dashboard.loading", bundle: .module))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("root.progress.content")
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.large)
        }
        .background(AppColors.color(.backgroundBase, scheme: colorScheme))
        .accessibilityIdentifier("root.progress")
    }
}
