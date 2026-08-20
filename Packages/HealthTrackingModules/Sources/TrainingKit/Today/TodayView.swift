import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct TodayView: View {
    private static let emptyActionActivationPoint = UnitPoint(x: 0.5, y: 0.9)
    private static let errorActionActivationPoint = UnitPoint(x: 0.01, y: 0.9)

    @Environment(\.colorScheme) private var colorScheme

    private let viewModel: TodayViewModel
    private let onPerformAction: @MainActor (TodayMainAction) -> Void

    public init(
        viewModel: TodayViewModel,
        onPerformAction: @escaping @MainActor (TodayMainAction) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onPerformAction = onPerformAction
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                stateContent
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.standard)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(text("today.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("root.today")
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .loading:
            HStack(spacing: AppSpacing.small) {
                ProgressView()
                    .tint(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .accessibilityHidden(true)
                Text(text("today.loading.accessibility"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text("today.loading.accessibility"))
            .accessibilityIdentifier("today.state.loading")
        case let .content(presentation):
            content(presentation)
        case .empty:
            FeatureStateView(
                state: .empty(
                    message: text("today.empty.message"),
                    actionTitle: text("today.empty.action"),
                    actionAccessibilityLabel: text("today.empty.accessibility"),
                    action: retry
                )
            )
            .accessibilityIdentifier("today.state.empty")
            .accessibilityLabel(Text(text("today.empty.accessibility")))
            .accessibilityHint(String(localized: "today.empty.hint", bundle: .module))
            .accessibilityAddTraits(.isButton)
            .accessibilityActivationPoint(Self.emptyActionActivationPoint)
            .accessibilityAction(.default, retry)
        case .error:
            FeatureStateView(
                state: .error(message: text("today.error.message")),
                retry: retry
            )
            .accessibilityIdentifier("today.state.error")
            .accessibilityLabel(Text(text("today.error.accessibility")))
            .accessibilityHint(String(localized: "today.error.hint", bundle: .module))
            .accessibilityAddTraits(.isButton)
            .accessibilityActivationPoint(Self.errorActionActivationPoint)
            .accessibilityAction(.default, retry)
        }
    }

    private func content(_ presentation: TodayPresentation) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(text("today.heading"))
                .font(AppTypography.titleMedium)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("root.today.content")

            Text(
                format(
                    "today.phase.format",
                    presentation.phase.name,
                    Int64(presentation.phase.position),
                    Int64(presentation.phase.count)
                )
            )
            .font(AppTypography.label)
            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("today.phase")

            directiveCard(presentation.directive)

            if let alert = presentation.alert {
                alertCard(alert, additionalCount: presentation.additionalAlertCount)
            }

            PrimaryActionButton(
                title: actionTitle(presentation.mainAction),
                accessibilityLabel: actionTitle(presentation.mainAction)
            ) {
                onPerformAction(presentation.mainAction)
            }
            .accessibilityIdentifier("today.action.primary")
            .accessibilityHint(text("today.action.hint"))

            proteinCard(targetG: presentation.proteinTargetG)

            #if DEBUG
            if let elapsed = presentation.firstMeaningfulContentElapsed {
                Text(text("today.performance.marker"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .accessibilityIdentifier("today.performance.firstMeaningful")
                    .accessibilityValue(
                        String(
                            format: "%.6f",
                            locale: Locale(identifier: "en_US_POSIX"),
                            elapsed
                        )
                    )
            }
            #endif
        }
    }

    private func directiveCard(_ directive: TodayDirectivePresentation) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                switch directive {
                case let .train(workoutDay, _):
                    Text(format("today.directive.train.format", workoutDay.name))
                        .accessibilityIdentifier("today.directive.train")
                    directiveContext(format("today.directive.focus.format", workoutDay.focus))
                case let .resume(_, workoutDay):
                    Text(format("today.directive.resume.format", workoutDay.name))
                        .accessibilityIdentifier("today.directive.resume")
                    directiveContext(format("today.directive.resume.context", workoutDay.focus))
                case let .rest(reason, nextWorkoutDay):
                    Text(text("today.directive.rest.title"))
                        .accessibilityIdentifier("today.directive.rest")
                    directiveContext(restContext(reason, nextWorkoutDay: nextWorkoutDay))
                }
            }
            .font(AppTypography.titleMedium)
            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func directiveContext(_ value: String) -> some View {
        Text(value)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("today.directive.context")
    }

    private func alertCard(
        _ alert: TodayAlertPresentation,
        additionalCount: Int
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                    alertText(alert)
                    Spacer(minLength: AppSpacing.compact)
                    if additionalCount > 0 {
                        Text(format("today.alert.additional.format", Int64(additionalCount)))
                            .font(AppTypography.label)
                            .foregroundStyle(AppColors.color(.stateInfo, scheme: colorScheme))
                            .accessibilityIdentifier("today.alert.additional")
                    }
                }
                Text(alertContext(alert))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.alert.context")
            }
        }
    }

    @ViewBuilder
    private func alertText(_ alert: TodayAlertPresentation) -> some View {
        switch alert {
        case .activeSymptoms:
            alertTitle(text("today.alert.activeSymptoms.title"), id: "today.alert.activeSymptoms")
        case .ohp:
            alertTitle(text("today.alert.ohp.title"), id: "today.alert.ohp")
        case let .deload(mode, _, _):
            alertTitle(
                mode == .active
                    ? text("today.alert.deload.active")
                    : text("today.alert.deload.recommended"),
                id: "today.alert.deload"
            )
        case let .phase(nextPhaseName):
            alertTitle(
                format("today.alert.phase.title", nextPhaseName),
                id: "today.alert.phase"
            )
        case let .bloodwork(title, _):
            alertTitle(
                format("today.alert.bloodwork.title", title),
                id: "today.alert.bloodwork"
            )
        case let .measurement(message):
            alertTitle(message, id: "today.alert.measurement")
        }
    }

    private func alertTitle(_ value: String, id: String) -> some View {
        Text(value)
            .font(AppTypography.label)
            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id)
    }

    private func alertContext(_ alert: TodayAlertPresentation) -> String {
        switch alert {
        case .activeSymptoms:
            text("today.alert.activeSymptoms.context")
        case .ohp:
            text("today.alert.ohp.context")
        case let .deload(_, reason, trainingWeekIndex):
            switch reason {
            case .scheduled:
                format("today.alert.deload.scheduled", Int64(trainingWeekIndex))
            case .reactive:
                text("today.alert.deload.reactive")
            }
        case let .phase(nextPhaseName):
            format("today.alert.phase.context", nextPhaseName)
        case let .bloodwork(_, dueDate):
            format(
                "today.alert.bloodwork.context",
                dueDate.formatted(date: .abbreviated, time: .omitted)
            )
        case .measurement:
            text("today.alert.measurement.context")
        }
    }

    private func proteinCard(targetG: Double) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(text("today.protein.title"))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                Text(format("today.protein.target.format", Int64(targetG.rounded())))
                    .font(AppTypography.numericRow)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                Text(text("today.protein.targetOnly"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("today.protein.target")
    }

    private func restContext(
        _ reason: TodayRestReason,
        nextWorkoutDay: TodayWorkoutDayPresentation
    ) -> String {
        switch reason {
        case .completedToday:
            return format("today.directive.rest.completedToday", nextWorkoutDay.name)
        case .completedPreviousCalendarDay:
            return format("today.directive.rest.completedYesterday", nextWorkoutDay.name)
        case let .weeklyTargetReached(completed, target):
            return format(
                "today.directive.rest.weeklyTarget",
                Int64(completed),
                Int64(target),
                nextWorkoutDay.name
            )
        }
    }

    private func actionTitle(_ action: TodayMainAction) -> String {
        switch action {
        case .start:
            text("today.action.start")
        case .resume:
            text("today.action.resume")
        case .overrideRest:
            text("today.action.overrideRest")
        }
    }

    private func retry() {
        Task { await viewModel.retry() }
    }

    private func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(
            format: String(localized: key, bundle: .module),
            locale: .current,
            arguments: arguments
        )
    }
}
