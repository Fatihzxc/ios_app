import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct FoundationProgramView: View {
    /// Targets the real full-width empty action and leading-edge error action.
    private static let emptyActionActivationPoint = UnitPoint(x: 0.5, y: 0.9)
    private static let errorActionActivationPoint = UnitPoint(x: 0.01, y: 0.9)

    @Environment(\.colorScheme) private var colorScheme
    private let viewModel: FoundationProgramViewModel
    private let phaseTransitionViewModel: PhaseTransitionViewModel?
    private let historyViewModel: TrainingHistoryViewModel?
    private let onOpenSession: (@MainActor (UUID) -> Void)?

    public init(
        viewModel: FoundationProgramViewModel,
        phaseTransitionViewModel: PhaseTransitionViewModel? = nil,
        historyViewModel: TrainingHistoryViewModel? = nil,
        onOpenSession: (@MainActor (UUID) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.phaseTransitionViewModel = phaseTransitionViewModel
        self.historyViewModel = historyViewModel
        self.onOpenSession = onOpenSession
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    stateContent
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(localized("foundation.training.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("root.training")
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("foundation.state.loading")
        case let .content(snapshot):
            loadedContent(snapshot)
        case .empty:
            FeatureStateView(
                state: .empty(
                    message: localized("foundation.empty.message"),
                    actionTitle: localized("foundation.empty.action"),
                    actionAccessibilityLabel: localized("foundation.empty.accessibility"),
                    action: reload
                )
            )
            .accessibilityIdentifier("foundation.state.empty")
            .accessibilityLabel(Text(localized("foundation.empty.accessibility")))
            .accessibilityHint(String(localized: "foundation.empty.hint", bundle: .module))
            .accessibilityAddTraits(.isButton)
            .accessibilityActivationPoint(Self.emptyActionActivationPoint)
            .accessibilityAction(.default, reload)
        case .error:
            FeatureStateView(
                state: .error(message: localized("foundation.error.message")),
                retry: reload
            )
            .accessibilityIdentifier("foundation.state.error")
            .accessibilityLabel(Text(localized("foundation.error.accessibility")))
            .accessibilityHint(String(localized: "foundation.error.hint", bundle: .module))
            .accessibilityAddTraits(.isButton)
            .accessibilityActivationPoint(Self.errorActionActivationPoint)
            .accessibilityAction(.default, reload)
        }
    }

    private func loadedContent(_ snapshot: FoundationProgramSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            sectionHeading(localized("foundation.profile.heading"))
                .accessibilityIdentifier("root.training.content")
            profileCard(snapshot.profile)

            sectionHeading(localized("foundation.program.heading"))
            AppCard {
                Text(snapshot.program.name)
                    .font(AppTypography.titleMedium)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("training.program.name")
            }

            if let historyViewModel {
                sectionHeading(localized("foundation.history.heading"))
                NavigationLink {
                    TrainingHistoryView(viewModel: historyViewModel)
                } label: {
                    AppCard {
                        HStack(spacing: AppSpacing.standard) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(
                                    AppColors.color(.stateInfo, scheme: colorScheme)
                                )
                                .accessibilityHidden(true)
                            Text(localized("foundation.history.open"))
                                .font(AppTypography.titleMedium)
                                .foregroundStyle(
                                    AppColors.color(.inkPrimary, scheme: colorScheme)
                                )
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(
                                    AppColors.color(.inkSecondary, scheme: colorScheme)
                                )
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("training.history.link")
            }

            if let phaseTransitionViewModel {
                PhaseTransitionCardView(
                    viewModel: phaseTransitionViewModel,
                    showsOnlyPriority: false
                )
            }

            sectionHeading(localized("foundation.phases.heading"))
            VStack(spacing: AppSpacing.standard) {
                ForEach(Array(snapshot.phases.enumerated()), id: \.element.id) { index, phase in
                    phaseRow(phase, index: index)
                }
            }

            sectionHeading(localized("foundation.days.heading"))
            VStack(spacing: AppSpacing.standard) {
                ForEach(Array(snapshot.workoutDays.enumerated()), id: \.element.id) { index, day in
                    dayRow(day, index: index)
                }
            }
        }
    }

    private func profileCard(_ profile: FoundationProfileSummary) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                Text(profile.displayName)
                    .font(AppTypography.titleMedium)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    profile.usesFallbackDisplayName
                        ? localized("foundation.profile.provenance.fallback")
                        : localized("foundation.profile.provenance.user")
                )
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))

                ResponsiveFoundationValueRow(
                    label: localized("foundation.profile.height"),
                    value: formatHeight(profile.heightCm, mode: profile.unitDisplayMode)
                )
                ResponsiveFoundationValueRow(
                    label: localized("foundation.profile.startWeight"),
                    value: formatWeight(profile.startWeightKg, mode: profile.unitDisplayMode)
                )
                ResponsiveFoundationValueRow(
                    label: localized("foundation.profile.targetWeight"),
                    value: formatWeight(profile.targetWeightKg, mode: profile.unitDisplayMode)
                )
                ResponsiveFoundationValueRow(
                    label: localized("foundation.profile.protein"),
                    value: formatMass(profile.proteinTargetG, unit: .grams)
                )
                ResponsiveFoundationValueRow(
                    label: localized("foundation.profile.weeklyTarget"),
                    value: String(
                        format: localized("foundation.profile.weeklyTarget.value"),
                        locale: .current,
                        Int64(profile.weeklyWorkoutTarget)
                    )
                )
            }
        }
    }

    private func phaseRow(_ phase: FoundationPhaseSummary, index: Int) -> some View {
        AppCard {
            HStack(alignment: .top, spacing: AppSpacing.standard) {
                Image(systemName: "circle.fill")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.color(.stateInfo, scheme: colorScheme))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(phase.name)
                        .font(AppTypography.titleMedium)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    Text(monthRange(phase))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    Text(phase.trainingFocus)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(phase.nutritionFocus)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(phase.milestone)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(phase.name))
        .accessibilityValue(Text(phaseAccessibilityValue(phase)))
        .accessibilityIdentifier("training.phase-row.\(index)")
    }

    @ViewBuilder
    private func dayRow(_ day: FoundationWorkoutDaySummary, index: Int) -> some View {
        if let onOpenSession {
            Button {
                onOpenSession(day.id)
            } label: {
                dayCard(day)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(day.name))
            .accessibilityValue(Text(day.focus))
            .accessibilityHint(Text(localized("session.open.day.hint")))
            .accessibilityIdentifier("training.day-row.\(index)")
        } else {
            dayCard(day)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(day.name))
                .accessibilityValue(Text(day.focus))
                .accessibilityIdentifier("training.day-row.\(index)")
        }
    }

    private func dayCard(_ day: FoundationWorkoutDaySummary) -> some View {
        AppCard {
            HStack(alignment: .top, spacing: AppSpacing.standard) {
                Image(systemName: "dumbbell")
                    .foregroundStyle(AppColors.color(.stateInfo, scheme: colorScheme))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(day.name)
                        .font(AppTypography.titleMedium)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    Text(day.focus)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.titleMedium)
            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            .accessibilityAddTraits(.isHeader)
    }

    private func monthRange(_ phase: FoundationPhaseSummary) -> String {
        String(
            format: localized("foundation.phase.monthRange"),
            locale: .current,
            Int64(phase.monthStart),
            Int64(phase.monthEnd)
        )
    }

    private func phaseAccessibilityValue(_ phase: FoundationPhaseSummary) -> String {
        String(
            format: localized("foundation.phase.accessibilityValue"),
            locale: .current,
            monthRange(phase),
            phase.trainingFocus,
            phase.nutritionFocus,
            phase.milestone
        )
    }

    private func formatHeight(_ centimeters: Double, mode: FoundationUnitDisplayMode) -> String {
        switch mode {
        case .metric:
            formatLength(centimeters, unit: .centimeters)
        case .imperial:
            formatLength(Measurement(value: centimeters, unit: UnitLength.centimeters).converted(to: .inches).value, unit: .inches)
        }
    }

    private func formatWeight(_ kilograms: Double, mode: FoundationUnitDisplayMode) -> String {
        switch mode {
        case .metric:
            formatMass(kilograms, unit: .kilograms)
        case .imperial:
            formatMass(Measurement(value: kilograms, unit: UnitMass.kilograms).converted(to: .pounds).value, unit: .pounds)
        }
    }

    private func formatLength(_ value: Double, unit: UnitLength) -> String {
        measurementFormatter.string(from: Measurement(value: value, unit: unit))
    }

    private func formatMass(_ value: Double, unit: UnitMass) -> String {
        measurementFormatter.string(from: Measurement(value: value, unit: unit))
    }

    private var measurementFormatter: MeasurementFormatter {
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private func reload() {
        Task { await viewModel.load() }
    }
}

private struct ResponsiveFoundationValueRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let label: String
    let value: String

    @ViewBuilder
    var body: some View {
        Group {
            if dynamicTypeSize < .accessibility3 {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.standard) {
                        horizontalLabelText
                        Spacer(minLength: AppSpacing.standard)
                        horizontalValueText
                    }
                    verticalLayout
                }
            } else {
                verticalLayout
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }

    private var horizontalLabelText: some View {
        Text(label)
            .font(AppTypography.body)
            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            .fixedSize(horizontal: true, vertical: false)
    }

    private var horizontalValueText: some View {
        Text(value)
            .font(AppTypography.numericRow)
            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            .fixedSize(horizontal: true, vertical: false)
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(label)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(AppTypography.numericRow)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
