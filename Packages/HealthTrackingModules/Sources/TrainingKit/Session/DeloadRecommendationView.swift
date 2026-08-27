import DesignSystem
import SwiftUI

@MainActor
public struct DeloadRecommendationView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let reason: SessionDeloadReason
    private let trainingWeekIndex: Int
    private let respond: (SessionDeloadAction) -> Void

    public init(
        reason: SessionDeloadReason,
        trainingWeekIndex: Int,
        respond: @escaping (SessionDeloadAction) -> Void
    ) {
        self.reason = reason
        self.trainingWeekIndex = trainingWeekIndex
        self.respond = respond
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.standard) {
                        HStack(spacing: AppSpacing.compact) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(
                                    AppColors.color(.stateWarning, scheme: colorScheme)
                                )
                                .accessibilityIdentifier("session.deload.warning-icon")
                            Text(localized("session.deload.recommendation.title"))
                                .font(AppTypography.titleLarge)
                                .foregroundStyle(
                                    AppColors.color(.inkPrimary, scheme: colorScheme)
                                )
                        }
                        Text(message)
                            .font(AppTypography.body)
                            .foregroundStyle(
                                AppColors.color(.inkSecondary, scheme: colorScheme)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("session.deload.recommendation")
                        Text(localized("session.deload.recommendation.range"))
                            .font(AppTypography.caption)
                            .foregroundStyle(
                                AppColors.color(.inkSecondary, scheme: colorScheme)
                            )
                    }
                }

                PrimaryActionButton(
                    title: localized("session.deload.action.accept"),
                    accessibilityLabel: localized("session.deload.action.accept"),
                    minimumHeight: 52
                ) {
                    respond(.accepted)
                }
                .accessibilityIdentifier("session.deload.action.accept")

                secondaryAction(
                    title: localized("session.deload.action.stay"),
                    identifier: "session.deload.action.stay",
                    action: .stay
                )
                secondaryAction(
                    title: localized("session.deload.action.techniqueReview"),
                    identifier: "session.deload.action.technique-review",
                    action: .techniqueReview
                )
                secondaryAction(
                    title: localized("session.deload.action.skip"),
                    identifier: "session.deload.action.skip",
                    action: .skipped
                )
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, SessionStageLayout.bottomActionClearance)
        }
        .accessibilityIdentifier("session.deload.gate")
    }

    private var message: String {
        switch reason {
        case .scheduled:
            String(
                format: localized("session.deload.recommendation.scheduled"),
                locale: .current,
                Int64(trainingWeekIndex)
            )
        case .reactive:
            localized("session.deload.recommendation.reactive")
        }
    }

    private func secondaryAction(
        title: String,
        identifier: String,
        action: SessionDeloadAction
    ) -> some View {
        Button(title) {
            respond(action)
        }
        .buttonStyle(.bordered)
        .font(AppTypography.label)
        .frame(maxWidth: .infinity, minHeight: 52)
        .accessibilityIdentifier(identifier)
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}

@MainActor
struct DeloadActiveBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: AppSpacing.compact) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(localized("session.deload.active"))
                .font(AppTypography.label)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .background(AppColors.color(.stateWarning, scheme: colorScheme).opacity(0.16))
        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session.deload.active")
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
