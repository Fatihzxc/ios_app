import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct TodayView: View {
    private static let emptyActionActivationPoint = UnitPoint(x: 0.5, y: 0.9)
    private static let errorActionActivationPoint = UnitPoint(x: 0.01, y: 0.9)

    @Environment(\.colorScheme) private var colorScheme

    private let viewModel: TodayViewModel
    private let nutritionState: TodayNutritionViewState
    private let exposesLaunchPerformanceEvidence: Bool
    private let onPerformAction: @MainActor (TodayMainAction) -> Void
    private let onAddMeal: @MainActor () -> Void
    private let onOpenTrackers: @MainActor () -> Void
    private let onOpenLifestyle: @MainActor () -> Void
    private let onOpenPosture: @MainActor () -> Void
    private let onOpenHealthChecks: @MainActor () -> Void

    public init(
        viewModel: TodayViewModel,
        nutritionState: TodayNutritionViewState = .loading,
        exposesLaunchPerformanceEvidence: Bool = false,
        onPerformAction: @escaping @MainActor (TodayMainAction) -> Void = { _ in },
        onAddMeal: @escaping @MainActor () -> Void = {},
        onOpenTrackers: @escaping @MainActor () -> Void = {},
        onOpenLifestyle: @escaping @MainActor () -> Void = {},
        onOpenPosture: @escaping @MainActor () -> Void = {},
        onOpenHealthChecks: @escaping @MainActor () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.nutritionState = nutritionState
        self.exposesLaunchPerformanceEvidence = exposesLaunchPerformanceEvidence
        self.onPerformAction = onPerformAction
        self.onAddMeal = onAddMeal
        self.onOpenTrackers = onOpenTrackers
        self.onOpenLifestyle = onOpenLifestyle
        self.onOpenPosture = onOpenPosture
        self.onOpenHealthChecks = onOpenHealthChecks
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

            VStack(alignment: .leading, spacing: AppSpacing.standard) {
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

                directiveCard(presentation.directive)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today.accessibility.summary")

            if let alert = presentation.alert {
                alertCard(alert, additionalCount: presentation.additionalAlertCount)
            }

            if case let .some(.bloodwork(title, dueDate)) = presentation.alert {
                healthCheckCard(title: title, dueDate: dueDate)
            }

            PrimaryActionButton(
                title: actionTitle(presentation.mainAction),
                accessibilityLabel: actionTitle(presentation.mainAction)
            ) {
                onPerformAction(presentation.mainAction)
            }
            .accessibilityIdentifier("today.action.primary")
            .accessibilityHint(text("today.action.hint"))

            Button(action: onAddMeal) {
                Label(
                    text("today.nutrition.action"),
                    systemImage: "plus.circle.fill"
                )
                .font(AppTypography.label)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .tint(AppColors.color(.accentAction, scheme: colorScheme))
            .accessibilityIdentifier("today.nutrition.action")
            .accessibilityHint(text("today.nutrition.action.hint"))

            Button(action: onOpenTrackers) {
                Label(
                    text("today.metrics.action"),
                    systemImage: "ruler"
                )
                .font(AppTypography.label)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .tint(AppColors.color(.accentAction, scheme: colorScheme))
            .accessibilityIdentifier("today.metrics.action")
            .accessibilityHint(text("today.metrics.action.hint"))

            Button(action: onOpenLifestyle) {
                Label(
                    text("today.lifestyle.action"),
                    systemImage: "moon.stars.fill"
                )
                .font(AppTypography.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .tint(AppColors.color(.accentAction, scheme: colorScheme))
            .accessibilityIdentifier("today.lifestyle.action")
            .accessibilityHint(text("today.lifestyle.action.hint"))

            Button(action: onOpenPosture) {
                Label(
                    text("today.posture.action"),
                    systemImage: "figure.stand"
                )
                .font(AppTypography.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .tint(AppColors.color(.accentAction, scheme: colorScheme))
            .accessibilityIdentifier("today.posture.action")
            .accessibilityHint(text("today.posture.action.hint"))

            nutritionCard(
                state: nutritionState,
                fallbackProteinTargetG: presentation.proteinTargetG
            )

            #if DEBUG
            if exposesLaunchPerformanceEvidence,
               let elapsed = presentation.firstMeaningfulContentElapsed {
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

    private func healthCheckCard(title: String, dueDate: Date) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(text("today.health-check.heading"))
                    .font(AppTypography.titleMedium)
                    .fixedSize(horizontal: false, vertical: true)
                Text(title)
                    .font(AppTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(AppTypography.caption)
                Button(action: onOpenHealthChecks) {
                    Label(
                        text("today.health-check.action"),
                        systemImage: "cross.case.fill"
                    )
                    .font(AppTypography.label)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("today.health-check.action")
                .accessibilityHint(text("today.health-check.action.hint"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.health-check.summary")
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

    @ViewBuilder
    private func nutritionCard(
        state: TodayNutritionViewState,
        fallbackProteinTargetG: Double
    ) -> some View {
        switch state {
        case let .empty(presentation), let .content(presentation):
            trackedNutritionCard(presentation)
        case .loading, .error:
            proteinCard(targetG: fallbackProteinTargetG)
        }
    }

    private func trackedNutritionCard(
        _ presentation: TodayNutritionPresentation
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(text("today.nutrition.heading"))
                    .font(AppTypography.titleMedium)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                Text(text("today.protein.title"))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))

                Text(proteinValue(presentation.protein))
                    .font(AppTypography.numericRow)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityValue(proteinValue(presentation.protein))
                    .accessibilityIdentifier("today.protein.consumed")

                if let progress = presentation.protein.clampedProgress {
                    ProgressView(value: NSDecimalNumber(decimal: progress).doubleValue)
                        .tint(AppColors.color(.accentAction, scheme: colorScheme))
                        .accessibilityLabel(text("today.protein.progress.label"))
                        .accessibilityValue(proteinValue(presentation.protein))
                        .accessibilityIdentifier("today.protein.progress")
                }

                Text(nutritionSummary(presentation))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.nutrition.summary")
    }

    private func proteinValue(_ metric: TodayNutritionMetricPresentation) -> String {
        if let target = metric.target {
            return format(
                "today.protein.consumedTarget.format",
                decimal(metric.consumed),
                decimal(target)
            )
        }
        return format("today.protein.consumed.format", decimal(metric.consumed))
    }

    private func nutritionSummary(_ presentation: TodayNutritionPresentation) -> String {
        format(
            "today.nutrition.macros.format",
            metricValue(presentation.calories, unit: text("today.nutrition.unit.kcal")),
            metricValue(presentation.carbG, unit: text("today.nutrition.unit.gram")),
            metricValue(presentation.fatG, unit: text("today.nutrition.unit.gram"))
        )
    }

    private func metricValue(
        _ metric: TodayNutritionMetricPresentation,
        unit: String
    ) -> String {
        if let target = metric.target {
            return format(
                "today.nutrition.metric.targeted.format",
                decimal(metric.consumed),
                decimal(target),
                unit
            )
        }
        return format(
            "today.nutrition.metric.total.format",
            decimal(metric.consumed),
            unit
        )
    }

    private func decimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
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
