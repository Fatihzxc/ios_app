import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct SetEntryBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var draft: SetDraft
    private let saveState: SessionSetSaveState
    private let recommendationReason: SessionRecommendationReason
    private let variantOptions: [SessionVariantOption]
    private let selectVariant: (SessionVariantOption) -> Void
    private let save: () -> Void
    private let retry: () -> Void

    public init(
        draft: SetDraft,
        saveState: SessionSetSaveState,
        recommendationReason: SessionRecommendationReason,
        variantOptions: [SessionVariantOption],
        selectVariant: @escaping (SessionVariantOption) -> Void,
        save: @escaping () -> Void,
        retry: @escaping () -> Void
    ) {
        self.draft = draft
        self.saveState = saveState
        self.recommendationReason = recommendationReason
        self.variantOptions = variantOptions
        self.selectVariant = selectVariant
        self.save = save
        self.retry = retry
    }

    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                HStack {
                    Text(
                        String(
                            format: localized("session.set.index"),
                            locale: .current,
                            Int64(draft.setIndex)
                        )
                    )
                    .font(AppTypography.titleMedium)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .accessibilityIdentifier(
                        "session.set.family.\(draft.measurementKind.rawValue)"
                    )
                    Spacer()
                    StatusPill(
                        text: prefillText,
                        systemImage: "arrow.down.to.line",
                        style: .info
                    )
                    .accessibilityIdentifier("session.set.recommendation")
                }

                measurementControls
                variantControl
                rirControls
                saveFeedback

                PrimaryActionButton(
                    title: localized("session.set.save"),
                    accessibilityLabel: localized("session.set.save"),
                    isLoading: saveState == .saving,
                    action: save
                )
                .accessibilityIdentifier("session.set.save")
            }
        }
    }

    @ViewBuilder
    private var measurementControls: some View {
        switch draft.measurementKind {
        case .weightReps:
            weightControl
            integerControl(
                title: localized("session.set.reps"),
                value: draft.measurement.reps,
                decrementIdentifier: "session.set.reps.decrement",
                incrementIdentifier: "session.set.reps.increment",
                decrement: {
                    draft.measurement.reps = max(1, (draft.measurement.reps ?? 1) - 1)
                },
                increment: {
                    draft.measurement.reps = (draft.measurement.reps ?? 0) + 1
                }
            )
        case .reps:
            integerControl(
                title: localized("session.set.reps"),
                value: draft.measurement.reps,
                decrementIdentifier: "session.set.reps.decrement",
                incrementIdentifier: "session.set.reps.increment",
                decrement: {
                    draft.measurement.reps = max(1, (draft.measurement.reps ?? 1) - 1)
                },
                increment: {
                    draft.measurement.reps = (draft.measurement.reps ?? 0) + 1
                }
            )
        case .duration:
            integerControl(
                title: localized("session.set.duration"),
                value: draft.measurement.durationSec,
                decrementIdentifier: "session.set.duration.decrement",
                incrementIdentifier: "session.set.duration.increment",
                decrement: {
                    draft.measurement.durationSec = max(
                        1,
                        (draft.measurement.durationSec ?? 5) - 5
                    )
                },
                increment: {
                    draft.measurement.durationSec = (draft.measurement.durationSec ?? 0) + 5
                }
            )
        case .steps:
            weightControl
            integerControl(
                title: localized("session.set.steps"),
                value: draft.measurement.distanceSteps,
                decrementIdentifier: "session.set.steps.decrement",
                incrementIdentifier: "session.set.steps.increment",
                decrement: {
                    draft.measurement.distanceSteps = max(
                        1,
                        (draft.measurement.distanceSteps ?? 5) - 5
                    )
                },
                increment: {
                    draft.measurement.distanceSteps =
                        (draft.measurement.distanceSteps ?? 0) + 5
                }
            )
        case .quality:
            Text(localized("session.set.quality"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            integerControl(
                title: localized("session.set.quality.reps"),
                value: draft.measurement.reps,
                decrementIdentifier: "session.set.quality.reps.decrement",
                incrementIdentifier: "session.set.quality.reps.increment",
                decrement: {
                    draft.measurement.reps = max(1, (draft.measurement.reps ?? 1) - 1)
                    draft.measurement.durationSec = nil
                },
                increment: {
                    draft.measurement.reps = (draft.measurement.reps ?? 0) + 1
                    draft.measurement.durationSec = nil
                }
            )
            integerControl(
                title: localized("session.set.quality.duration"),
                value: draft.measurement.durationSec,
                decrementIdentifier: "session.set.quality.duration.decrement",
                incrementIdentifier: "session.set.quality.duration.increment",
                decrement: {
                    draft.measurement.durationSec = max(
                        1,
                        (draft.measurement.durationSec ?? 5) - 5
                    )
                    draft.measurement.reps = nil
                },
                increment: {
                    draft.measurement.durationSec = (draft.measurement.durationSec ?? 0) + 5
                    draft.measurement.reps = nil
                }
            )
        }
    }

    private var weightControl: some View {
        valueControl(
            title: localized("session.set.weight"),
            value: formatWeight(draft.measurement.weightKg),
            decrementIdentifier: "session.set.weight.decrement",
            incrementIdentifier: "session.set.weight.increment",
            decrement: {
                draft.measurement.weightKg = max(
                    0,
                    (draft.measurement.weightKg ?? 2.5) - 2.5
                )
            },
            increment: {
                draft.measurement.weightKg = (draft.measurement.weightKg ?? 0) + 2.5
            }
        )
    }

    @ViewBuilder
    private var variantControl: some View {
        if draft.enabledFields.contains(.performedVariant) {
            if variantOptions.isEmpty {
                TextField(
                    localized("session.set.variant"),
                    text: Binding(
                        get: { draft.measurement.performedVariant ?? "" },
                        set: { draft.selectPerformedVariant($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("session.set.variant")
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(localized("session.set.variant.choice"))
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    HStack(spacing: AppSpacing.compact) {
                        ForEach(variantOptions, id: \.rawValue) { option in
                            variantButton(option)
                        }
                    }
                }
            }
        }
    }

    private func variantButton(_ option: SessionVariantOption) -> some View {
        let isSelected = draft.measurement.performedVariant == option.rawValue
        return Button {
            selectVariant(option)
        } label: {
            Text(variantLabel(option))
                .font(AppTypography.label)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    AppColors.color(
                        isSelected ? .accentAction : .backgroundSunken,
                        scheme: colorScheme
                    )
                )
                .foregroundStyle(
                    AppColors.color(
                        isSelected ? .accentOnAction : .inkPrimary,
                        scheme: colorScheme
                    )
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? localized("session.selection.selected") : "")
        .accessibilityIdentifier("session.set.variant.\(option.rawValue)")
    }

    private func variantLabel(_ option: SessionVariantOption) -> String {
        switch option {
        case .pallof:
            localized("session.set.variant.pallof")
        case .plank:
            localized("session.set.variant.plank")
        }
    }

    private var rirControls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(localized("session.set.rir"))
                .font(AppTypography.label)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.compact) {
                    rirButton(value: nil, label: "—")
                    ForEach(0...10, id: \.self) { value in
                        rirButton(value: value, label: String(value))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var saveFeedback: some View {
        switch saveState {
        case .validationFailed:
            Text(localized("session.set.validationError"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                .accessibilityIdentifier("session.set.validation-error")
        case .repositoryFailed:
            HStack {
                Text(localized("session.set.repositoryError"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                Spacer()
                Button(localized("session.set.retry"), action: retry)
                    .font(AppTypography.label)
                    .accessibilityIdentifier("session.set.retry")
            }
        case .idle, .saving, .saved:
            EmptyView()
        }
    }

    private func integerControl(
        title: String,
        value: Int?,
        decrementIdentifier: String,
        incrementIdentifier: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        valueControl(
            title: title,
            value: value.map { String($0) } ?? "—",
            decrementIdentifier: decrementIdentifier,
            incrementIdentifier: incrementIdentifier,
            decrement: decrement,
            increment: increment
        )
    }

    private func valueControl(
        title: String,
        value: String,
        decrementIdentifier: String,
        incrementIdentifier: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: AppSpacing.standard) {
            Text(title)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            Spacer()
            Button(action: decrement) {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(
                String(
                    format: localized("session.set.decrement"),
                    locale: .current,
                    title
                )
            )
            .accessibilityIdentifier(decrementIdentifier)
            Text(value)
                .font(AppTypography.numericRow)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .frame(minWidth: 56)
            Button(action: increment) {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(
                String(
                    format: localized("session.set.increment"),
                    locale: .current,
                    title
                )
            )
            .accessibilityIdentifier(incrementIdentifier)
        }
    }

    private func rirButton(value: Int?, label: String) -> some View {
        let isSelected = draft.measurement.rir == value
        return Button {
            draft.selectRIR(value)
        } label: {
            Text(label)
                .font(AppTypography.label)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    AppColors.color(
                        isSelected ? .accentAction : .backgroundSunken,
                        scheme: colorScheme
                    )
                )
                .foregroundStyle(
                    AppColors.color(
                        isSelected ? .accentOnAction : .inkPrimary,
                        scheme: colorScheme
                    )
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            value.map {
                String(
                    format: localized("session.set.rir.value"),
                    locale: .current,
                    Int64($0)
                )
            } ?? localized("session.set.rir.unset")
        )
        .accessibilityValue(isSelected ? localized("session.selection.selected") : "")
        .accessibilityIdentifier("session.set.rir.\(value.map { String($0) } ?? "unset")")
    }

    private var prefillText: String {
        switch recommendationReason {
        case .templateStartingValues:
            return localized("session.recommendation.template.short")
        case .sameSessionPrevious:
            return localized("session.recommendation.sameSession.short")
        case .priorSessionSameIndex:
            return localized("session.recommendation.priorSession.short")
        case .doubleProgressionIncrease:
            return localized("session.recommendation.doubleProgression.increase.short")
        case .doubleProgressionHold:
            return localized("session.recommendation.doubleProgression.hold.short")
        case .bodyweight:
            return localized("session.recommendation.bodyweight.short")
        case .weeklyPallof:
            return localized("session.recommendation.weeklyPallof.short")
        case .ohp:
            return localized("session.recommendation.ohp.short")
        case .equipmentCeiling:
            return localized("session.recommendation.equipmentCeiling.short")
        case .phaseTrainingFocus:
            return localized("session.recommendation.phaseTrainingFocus.short")
        case .deload:
            return localized("session.recommendation.deload.short")
        case .noPrefill:
            return localized("session.recommendation.none.short")
        }
    }

    private func formatWeight(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: Measurement(value: value, unit: UnitMass.kilograms))
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
