import DesignSystem
import SwiftUI

public struct ReportsFoundationView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.standard) {
                        Text(String(localized: "reports.foundation.heading", bundle: .module))
                            .font(AppTypography.titleMedium)
                            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                            .accessibilityAddTraits(.isHeader)
                        Text(String(localized: "reports.foundation.message", bundle: .module))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("root.progress.content")
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.large)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(String(localized: "reports.foundation.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("root.progress")
    }
}
