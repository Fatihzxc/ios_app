import DesignSystem
import SwiftUI

public struct NutritionFoundationView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.standard) {
                        Text(String(localized: "nutrition.foundation.heading", bundle: .module))
                            .font(AppTypography.titleMedium)
                            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                            .accessibilityAddTraits(.isHeader)
                        Text(String(localized: "nutrition.foundation.message", bundle: .module))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("root.nutrition.content")
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.large)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(String(localized: "nutrition.foundation.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("root.nutrition")
    }
}
