import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct ExerciseStageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var isExerciseHeadingFocused: Bool
    @Bindable private var viewModel: SessionViewModel
    private let presentation: SessionPresentation

    public init(
        viewModel: SessionViewModel,
        presentation: SessionPresentation
    ) {
        self.viewModel = viewModel
        self.presentation = presentation
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                if let exercise = viewModel.displayedExercise {
                    ohpSafetyStop
                    exerciseHeader(exercise)
                    exerciseGuidance(exercise)
                    if let draft = viewModel.currentSetDraft {
                        SetEntryBar(
                            draft: draft,
                            saveState: viewModel.setSaveState,
                            recommendationReason: viewModel.recommendationReason,
                            variantOptions: viewModel.currentVariantOptions,
                            selectVariant: viewModel.selectPerformedVariant,
                            selectionChanged: viewModel.stepperChanged,
                            save: {
                                Task { await viewModel.saveCurrentSet() }
                            },
                            retry: {
                                Task { await viewModel.retrySetSave() }
                            }
                        )
                    }
                    navigationActions
                } else {
                    Text(localized("session.exercise.missing"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.large)
        }
        .accessibilityIdentifier("session.stage.exercise")
        .task {
            isExerciseHeadingFocused = true
        }
        .onChange(of: viewModel.displayedExercise?.id) { _, _ in
            isExerciseHeadingFocused = true
        }
    }

    private func exerciseHeader(_ exercise: SessionExerciseSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(
                String(
                    format: localized("session.exercise.position"),
                    locale: .current,
                    Int64((presentation.currentExerciseIndex ?? 0) + 1),
                    Int64(presentation.plan.exercises.count)
                )
            )
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            Text(exercise.name)
                .font(AppTypography.titleLarge)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("session.exercise.name")
                .accessibilityFocused($isExerciseHeadingFocused)
            Text(targetText(exercise))
                .font(AppTypography.numericRow)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .accessibilityIdentifier("session.exercise.target")
            Text(
                String(
                    format: localized("session.exercise.completedSets"),
                    locale: .current,
                    Int64(viewModel.completedWorkingSetsForDisplayedExercise.count),
                    Int64(exercise.targetSets)
                )
            )
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            .accessibilityIdentifier("session.exercise.completedSets")
        }
    }

    private func exerciseGuidance(_ exercise: SessionExerciseSnapshot) -> some View {
        VStack(spacing: AppSpacing.standard) {
            ohpVariant

            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(localized("session.exercise.recommendation.heading"))
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    Text(recommendationText)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .accessibilityIdentifier("session.exercise.recommendation")
                }
            }

            deloadLoadInformation
            equipmentCeilingInformation

            if let safetyNote = exercise.safetyNote, !safetyNote.isEmpty {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        StatusPill(
                            text: localized("session.exercise.safety.heading"),
                            systemImage: "exclamationmark.triangle",
                            style: .warning
                        )
                        .accessibilityIdentifier("session.exercise.safety.heading")
                        Text(safetyNote)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("session.exercise.safety")
                    }
                }
            }

            AppCard {
                Text(
                    exercise.allowFailure
                        ? localized("session.exercise.failure.allowed")
                        : localized("session.exercise.failure.blocked")
                )
                .font(AppTypography.body)
                .foregroundStyle(
                    AppColors.color(
                        exercise.allowFailure ? .stateWarning : .inkSecondary,
                        scheme: colorScheme
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("session.exercise.failure")
            }

            if !exercise.cues.isEmpty {
                Text(exercise.cues)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            }

            if viewModel.canReportCurrentOHPSymptom {
                Button(role: .destructive) {
                    Task { await viewModel.reportCurrentOHPSymptom() }
                } label: {
                    Label(
                        localized("session.ohp.currentSymptom"),
                        systemImage: "hand.raised.fill"
                    )
                    .font(AppTypography.label)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("session.ohp.current-symptom")
            }
        }
    }

    @ViewBuilder
    private var ohpSafetyStop: some View {
        if presentation.currentExercise?.progressionRule == .gradedEntryOHP,
           case .stopped = viewModel.ohpSafetyState {
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    StatusPill(
                        text: localized("session.ohp.stop.title"),
                        systemImage: "hand.raised.fill",
                        style: .danger
                    )
                    .accessibilityIdentifier("session.ohp.stop")
                    Text(localized("session.ohp.stop.message"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let safety = viewModel.symptomSafetyPresentation {
                        Text(safety.disclaimer)
                            .font(AppTypography.caption)
                            .foregroundStyle(
                                AppColors.color(.inkSecondary, scheme: colorScheme)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("medical.disclaimer.l1")
                        Text(safety.levelTwoMessage)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("medical.safety.l2")
                    }
                    symptomJournalStatus
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var symptomJournalStatus: some View {
        switch viewModel.symptomJournalState {
        case .idle:
            EmptyView()
        case .recording:
            HStack(spacing: AppSpacing.small) {
                ProgressView()
                Text(localized("session.ohp.journal.recording"))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("session.ohp.journal.recording")
        case .recorded:
            Text(localized("session.ohp.journal.recorded"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.stateSuccess, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("session.ohp.journal.recorded")
        case .failed:
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(localized("session.ohp.journal.error"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("session.ohp.journal.error")
                Button(localized("session.ohp.journal.retry")) {
                    Task { await viewModel.retrySymptomJournal() }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 52)
                .accessibilityIdentifier("session.ohp.journal.retry")
            }
        }
    }

    @ViewBuilder
    private var ohpVariant: some View {
        if viewModel.canReportCurrentOHPSymptom {
            switch viewModel.ohpSafetyState {
            case let .awaitingPreviousSessionResponse(_, entryVariant),
                 let .ready(entryVariant, _):
                AppCard {
                    HStack(spacing: AppSpacing.compact) {
                        Image(systemName: "lock.shield")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("session.ohp.variant.heading"))
                                .font(AppTypography.caption)
                            Text(ohpVariantText(entryVariant))
                                .font(AppTypography.label)
                                .accessibilityIdentifier("session.ohp.variant")
                        }
                    }
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                }
            case .notRequired, .stopped:
                EmptyView()
            }
        }
    }

    private var navigationActions: some View {
        VStack(spacing: AppSpacing.standard) {
            PrimaryActionButton(
                title: localized("session.exercise.next"),
                accessibilityLabel: localized("session.exercise.next"),
                minimumHeight: 52,
                action: {
                    Task { await viewModel.advanceExercise() }
                }
            )
            .accessibilityIdentifier("session.exercise.next")
            .accessibilityHint(
                String(localized: "session.exercise.next.hint", bundle: .module)
            )
            HStack(spacing: AppSpacing.standard) {
                Button {
                    Task { await viewModel.goBack() }
                } label: {
                    Text(localized("session.exercise.back"))
                        .frame(maxWidth: .infinity, minHeight: 53)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("session.exercise.back")

                Button(role: .destructive) {
                    Task { await viewModel.finishIncomplete() }
                } label: {
                    Text(localized("session.exercise.finishIncomplete"))
                        .frame(maxWidth: .infinity, minHeight: 53)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("session.exercise.finish-incomplete")
            }
            .font(AppTypography.label)
            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
        }
    }

    private var recommendationText: String {
        switch viewModel.recommendationReason {
        case .templateStartingValues:
            return localized("session.recommendation.template")
        case .sameSessionPrevious:
            return localized("session.recommendation.sameSession")
        case .priorSessionSameIndex:
            return localized("session.recommendation.priorSession")
        case .doubleProgressionIncrease:
            return localized("session.recommendation.doubleProgression.increase")
        case let .doubleProgressionHold(reason):
            return doubleProgressionHoldText(reason)
        case let .bodyweight(reason):
            return bodyweightText(reason)
        case let .weeklyPallof(reason):
            return weeklyPallofText(reason)
        case let .ohp(reason):
            return ohpRecommendationText(reason)
        case let .equipmentCeiling(reason):
            return equipmentCeilingText(reason)
        case .phaseTrainingFocus(.boneFocusLowerBound):
            return localized("session.recommendation.phaseTrainingFocus")
        case let .deload(reason):
            return deloadRecommendationText(reason)
        case .noPrefill:
            return localized("session.recommendation.none")
        }
    }

    @ViewBuilder
    private var deloadLoadInformation: some View {
        if case .active = viewModel.deloadState {
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    StatusPill(
                        text: localized("session.deload.active"),
                        systemImage: "exclamationmark.triangle.fill",
                        style: .warning
                    )
                    Text(localized("session.deload.load"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("session.deload.load")
                }
            }
        }
    }

    private func deloadRecommendationText(
        _ reason: SessionDeloadRecommendationReason
    ) -> String {
        switch reason.reason {
        case .scheduled:
            localized("session.recommendation.deload.scheduled")
        case .reactive:
            localized("session.recommendation.deload.reactive")
        }
    }

    @ViewBuilder
    private var equipmentCeilingInformation: some View {
        if case .equipmentCeiling = viewModel.recommendationReason {
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    StatusPill(
                        text: localized("session.recommendation.equipmentCeiling.investment.title"),
                        systemImage: "info.circle",
                        style: .info
                    )
                    Text(localized("session.recommendation.equipmentCeiling.investment"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("session.equipment-ceiling.investment-information")
        }
    }

    private func equipmentCeilingText(_ reason: SessionEquipmentCeilingReason) -> String {
        let weight = formatWeight(reason.weightKg)
        let ceilingText: String
        if reason.phaseFocusApplied {
            ceilingText = String(
                format: localized("session.recommendation.equipmentCeiling.withPhaseFocus"),
                locale: .current,
                weight
            )
        } else {
            ceilingText = String(
                format: localized("session.recommendation.equipmentCeiling"),
                locale: .current,
                weight
            )
        }
        guard let ohpReason = reason.ohpReason else { return ceilingText }
        return "\(ohpRecommendationText(ohpReason)) \(ceilingText)"
    }

    private func formatWeight(_ value: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: Measurement(value: value, unit: UnitMass.kilograms))
    }

    private func ohpRecommendationText(
        _ reason: SessionOHPRecommendationReason
    ) -> String {
        switch reason {
        case .firstSession:
            localized("session.recommendation.ohp.firstSession")
        case .previousResponseRequired:
            localized("session.recommendation.ohp.previousResponseRequired")
        case .previousSymptomsPresent:
            localized("session.recommendation.ohp.previousSymptomsPresent")
        case .previousResponseUncertain:
            localized("session.recommendation.ohp.previousResponseUncertain")
        case .currentSymptomsPresent:
            localized("session.recommendation.ohp.currentSymptomsPresent")
        case .increaseAllowed:
            localized("session.recommendation.ohp.increaseAllowed")
        case let .progressionHold(holdReason):
            doubleProgressionHoldText(holdReason)
        }
    }

    private func ohpVariantText(_ variant: SessionOHPEntryVariant) -> String {
        switch variant {
        case .seatedNeutral:
            localized("session.ohp.variant.seatedNeutral")
        case .standingNeutral:
            localized("session.ohp.variant.standingNeutral")
        case .standingStandard:
            localized("session.ohp.variant.standingStandard")
        }
    }

    private func bodyweightText(
        _ reason: SessionBodyweightRecommendationReason
    ) -> String {
        switch reason {
        case .noWorkingSets:
            localized("session.recommendation.bodyweight.noWorkingSets")
        case .missingRepCeiling:
            localized("session.recommendation.bodyweight.missingRepCeiling")
        case .inconsistentVariants:
            localized("session.recommendation.bodyweight.inconsistentVariants")
        case .buildRepetitions:
            localized("session.recommendation.bodyweight.buildRepetitions")
        case .advanceToDefinedVariant:
            localized("session.recommendation.bodyweight.advanceToDefinedVariant")
        case .programAdjustmentRequired:
            localized("session.recommendation.bodyweight.programAdjustmentRequired")
        }
    }

    private func weeklyPallofText(
        _ reason: SessionWeeklyPallofRecommendationReason
    ) -> String {
        switch reason {
        case .pallofDue:
            localized("session.recommendation.weeklyPallof.pallofDue")
        case .pallofCompletedThisWeek:
            localized("session.recommendation.weeklyPallof.pallofCompletedThisWeek")
        }
    }

    private func doubleProgressionHoldText(
        _ reason: SessionDoubleProgressionHoldReason
    ) -> String {
        switch reason {
        case .noWorkingSets:
            localized("session.recommendation.doubleProgression.hold.noWorkingSets")
        case .missingRepCeiling:
            localized("session.recommendation.doubleProgression.hold.missingRepCeiling")
        case .repetitionsBelowCeiling:
            localized("session.recommendation.doubleProgression.hold.repetitionsBelowCeiling")
        case .missingRIR:
            localized("session.recommendation.doubleProgression.hold.missingRIR")
        case .rirAboveThreshold:
            localized("session.recommendation.doubleProgression.hold.rirAboveThreshold")
        case .missingExternalWeight:
            localized("session.recommendation.doubleProgression.hold.missingExternalWeight")
        }
    }

    private func targetText(_ exercise: SessionExerciseSnapshot) -> String {
        let setAndRepTarget: String
        switch (exercise.repLow, exercise.repHigh) {
        case let (low?, high?) where low == high:
            setAndRepTarget = String(
                format: localized("session.exercise.target.fixed"),
                locale: .current,
                Int64(exercise.targetSets),
                Int64(low)
            )
        case let (low?, high?):
            setAndRepTarget = String(
                format: localized("session.exercise.target.range"),
                locale: .current,
                Int64(exercise.targetSets),
                Int64(low),
                Int64(high)
            )
        default:
            setAndRepTarget = String(
                format: localized("session.exercise.target.sets"),
                locale: .current,
                Int64(exercise.targetSets)
            )
        }

        if exercise.rirLow == exercise.rirHigh {
            return String(
                format: localized("session.exercise.target.rir.fixed"),
                locale: .current,
                setAndRepTarget,
                Int64(exercise.rirLow)
            )
        }
        return String(
            format: localized("session.exercise.target.rir.range"),
            locale: .current,
            setAndRepTarget,
            Int64(exercise.rirLow),
            Int64(exercise.rirHigh)
        )
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
