import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct LifestyleProgressSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: LifestyleViewModel
    private let date: Date

    public init(viewModel: LifestyleViewModel, date: Date) {
        self.viewModel = viewModel
        self.date = date
    }

    public var body: some View {
        stateContent
            .task {
                if viewModel.loadPhase == .idle {
                    await viewModel.load(date: date)
                }
            }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.loadPhase {
        case .idle, .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("lifestyle.progress.loading")
        case .failed:
            FeatureStateView(
                state: .error(message: localized("lifestyle.progress.error")),
                retry: { Task { await viewModel.load(date: date) } }
            )
            .accessibilityIdentifier("lifestyle.progress.error")
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.standard) {
                Text(localized("lifestyle.progress.heading"))
                    .font(AppTypography.titleMedium)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AppSpacing.small)
                Text(String(sectionCount))
                    .font(AppTypography.label)
                    .foregroundStyle(
                        AppColors.color(.inkSecondary, scheme: colorScheme)
                    )
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: true)
                    .accessibilityLabel(localized("lifestyle.progress.heading"))
                    .accessibilityValue(String(sectionCount))
                    .accessibilityIdentifier("lifestyle.progress.loaded")
            }

            if sectionCount == 0 {
                AppCard {
                    Text(localized("lifestyle.progress.empty"))
                        .font(AppTypography.body)
                        .foregroundStyle(
                            AppColors.color(.inkSecondary, scheme: colorScheme)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if let sleep = viewModel.day?.sleep {
                    summaryCard(
                        title: localized("lifestyle.progress.sleep"),
                        lines: [
                            format(
                                "lifestyle.progress.sleep.duration",
                                decimal(sleep.durationHours)
                            ),
                            format(
                                "lifestyle.progress.sleep.quality",
                                Int64(sleep.quality)
                            ),
                        ]
                    )
                }
                if let mood = viewModel.day?.mood {
                    summaryCard(
                        title: localized("lifestyle.progress.mood"),
                        lines: moodLines(mood)
                    )
                }
            }
        }
    }

    private func summaryCard(title: String, lines: [String]) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(title)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(AppTypography.body)
                        .foregroundStyle(
                            AppColors.color(.inkSecondary, scheme: colorScheme)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func moodLines(_ mood: MoodLogSnapshot) -> [String] {
        var lines: [String] = []
        if let score = mood.score {
            lines.append(format("lifestyle.progress.mood.score", Int64(score)))
        }
        if !mood.tags.isEmpty {
            lines.append(
                format("lifestyle.progress.mood.tags", mood.tags.joined(separator: ", "))
            )
        }
        if let energy = mood.energy {
            lines.append(format("lifestyle.progress.mood.energy", Int64(energy)))
        }
        return lines
    }

    private var sectionCount: Int {
        (viewModel.day?.sleep == nil ? 0 : 1)
            + (viewModel.day?.mood == nil ? 0 : 1)
    }

    private func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private func format(
        _ key: String.LocalizationValue,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: localized(key),
            locale: .autoupdatingCurrent,
            arguments: arguments
        )
    }
}
