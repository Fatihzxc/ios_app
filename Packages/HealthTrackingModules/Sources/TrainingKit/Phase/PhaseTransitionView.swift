import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct PhaseTransitionCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let viewModel: PhaseTransitionViewModel
    private let showsOnlyPriority: Bool

    public init(
        viewModel: PhaseTransitionViewModel,
        showsOnlyPriority: Bool
    ) {
        self.viewModel = viewModel
        self.showsOnlyPriority = showsOnlyPriority
    }

    @ViewBuilder
    public var body: some View {
        if case let .content(snapshot) = viewModel.state,
           let review = snapshot.review,
           !showsOnlyPriority || snapshot.isPriority {
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    StatusPill(
                        text: review.isDue
                            ? localized("phase.transition.review.status")
                            : localized("phase.transition.upcoming.status"),
                        systemImage: "arrow.triangle.2.circlepath",
                        style: review.isDue ? .warning : .info
                    )
                    .accessibilityIdentifier("phase.transition.card")
                    Text(snapshot.currentPhaseName)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .accessibilityIdentifier("phase.transition.current")
                    Text(
                        String(
                            format: localized("phase.transition.next.format"),
                            locale: .current,
                            review.nextPhaseName
                        )
                    )
                    .font(AppTypography.titleMedium)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        String(
                            format: localized("phase.transition.estimate.format"),
                            locale: .current,
                            dateFormatter.string(from: review.estimatedStart)
                        )
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                    checklist(review.checklist)

                    if review.isDue {
                        PrimaryActionButton(
                            title: localized("phase.transition.confirm"),
                            accessibilityLabel: localized("phase.transition.confirm")
                        ) {
                            Task { await viewModel.confirmTransition() }
                        }
                        .accessibilityIdentifier("phase.transition.confirm")

                        Button(localized("phase.transition.stay")) {
                            viewModel.stayInCurrentPhase()
                        }
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.color(.accentAction, scheme: colorScheme))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("phase.transition.stay")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func checklist(_ items: [PhaseChecklistItemSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(localized("phase.transition.checklist.heading"))
                .font(AppTypography.label)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .accessibilityIdentifier("phase.transition.checklist")
            if items.isEmpty {
                Text(localized("phase.transition.checklist.empty"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: AppSpacing.compact) {
                        Image(systemName: "square")
                            .foregroundStyle(AppColors.color(.stateInfo, scheme: colorScheme))
                            .accessibilityHidden(true)
                        Text(item.text)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("phase.transition.checklist.\(index)")
                    }
                }
            }
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}

@MainActor
public struct ManualPhaseSelectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let viewModel: PhaseTransitionViewModel

    public init(viewModel: PhaseTransitionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                switch viewModel.state {
                case .loading:
                    FeatureStateView(state: .loading)
                case .empty:
                    Text(localized("phase.selection.empty"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                case .error:
                    FeatureStateView(
                        state: .error(message: localized("phase.selection.error")),
                        retry: { Task { await viewModel.load() } }
                    )
                case let .content(snapshot):
                    Text(localized("phase.selection.explanation"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(snapshot.options.enumerated()), id: \.element.id) { index, option in
                        Button {
                            Task { await viewModel.selectPhaseManually(id: option.id) }
                        } label: {
                            AppCard {
                                HStack(spacing: AppSpacing.standard) {
                                    Text(option.name)
                                        .font(AppTypography.titleMedium)
                                        .foregroundStyle(
                                            AppColors.color(.inkPrimary, scheme: colorScheme)
                                        )
                                    Spacer(minLength: AppSpacing.standard)
                                    if option.isCurrent {
                                        Label(
                                            localized("phase.selection.current"),
                                            systemImage: "checkmark.circle.fill"
                                        )
                                        .font(AppTypography.caption)
                                        .foregroundStyle(
                                            AppColors.color(.stateSuccess, scheme: colorScheme)
                                        )
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("phase.selection.option.\(index)")
                        .accessibilityValue(
                            option.isCurrent ? localized("phase.selection.current") : ""
                        )
                    }
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.large)
        }
        .background(AppColors.color(.backgroundBase, scheme: colorScheme))
        .navigationTitle(localized("phase.selection.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("phase.selection.root")
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
