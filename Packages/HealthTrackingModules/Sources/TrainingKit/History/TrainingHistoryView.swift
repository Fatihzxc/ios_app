import DesignSystem
import SwiftUI

@MainActor
public struct TrainingHistoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: TrainingHistoryViewModel

    public init(viewModel: TrainingHistoryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                FeatureStateView(state: .loading)
            case .empty:
                FeatureStateView(
                    state: .empty(
                        message: localized("history.empty"),
                        actionTitle: localized("history.reload"),
                        actionAccessibilityLabel: localized("history.reload"),
                        action: { Task { await viewModel.load() } }
                    )
                )
            case .error:
                FeatureStateView(
                    state: .error(message: localized("history.error")),
                    retry: { Task { await viewModel.retry() } }
                )
            case let .content(sessions):
                historyList(sessions)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.color(.backgroundBase, scheme: colorScheme))
        .navigationTitle(localized("history.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("training.history.root")
        .task { await viewModel.load() }
    }

    private func historyList(
        _ sessions: [TrainingHistorySessionPresentation]
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.standard) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    NavigationLink {
                        WorkoutSessionDetailView(
                            viewModel: viewModel,
                            sessionID: session.id
                        )
                    } label: {
                        sessionCard(session)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text(localized("history.session.open.hint")))
                    .accessibilityIdentifier("training.history.session.\(index)")
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.large)
        }
    }

    private func sessionCard(
        _ session: TrainingHistorySessionPresentation
    ) -> some View {
        AppCard {
            HStack(alignment: .top, spacing: AppSpacing.standard) {
                Image(systemName: "calendar")
                    .foregroundStyle(AppColors.color(.stateInfo, scheme: colorScheme))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(session.workoutDayName ?? localized("history.missing.day"))
                        .font(AppTypography.titleMedium)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    Text(session.session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(AppTypography.numericRow)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    Text(
                        String(
                            format: localized("history.session.setCount"),
                            locale: .current,
                            Int64(session.exercises.flatMap(\.sets).count)
                        )
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                }
                Spacer(minLength: AppSpacing.compact)
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .accessibilityHidden(true)
            }
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
