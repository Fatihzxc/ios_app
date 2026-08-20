import CoreModels
import DesignSystem
import SwiftUI

@MainActor
public struct EditSetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Bindable private var viewModel: TrainingHistoryViewModel

    public init(viewModel: TrainingHistoryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    if let editing = viewModel.editingSet {
                        measurementControls(editing)
                        mutationMessage
                        PrimaryActionButton(
                            title: localized("history.edit.save"),
                            accessibilityLabel: localized("history.edit.save"),
                            isLoading: viewModel.mutationState == .saving,
                            action: save
                        )
                        .accessibilityIdentifier("training.history.edit.save")
                    } else {
                        Text(localized("history.edit.missing"))
                            .font(AppTypography.body)
                            .foregroundStyle(
                                AppColors.color(.inkSecondary, scheme: colorScheme)
                            )
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.large)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(localized("history.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("history.edit.cancel")) {
                        viewModel.cancelEditing()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.mutationState == .saving)
        .accessibilityIdentifier("training.history.edit.root")
    }

    @ViewBuilder
    private func measurementControls(_ editing: TrainingHistoryEditingSet) -> some View {
        switch editing.measurementKind {
        case .weightReps:
            weightControl(editing.measurement)
            repetitionsControl(editing.measurement)
        case .reps:
            optionalWeightControl(editing.measurement)
            repetitionsControl(editing.measurement)
        case .duration:
            durationControl(editing.measurement)
        case .steps:
            optionalWeightControl(editing.measurement)
            stepsControl(editing.measurement)
        case .quality:
            qualityControls(editing.measurement)
        }
        variantControl(editing.measurement)
        rirControl(editing.measurement)
    }

    private func weightControl(_ measurement: SetMeasurementInput) -> some View {
        numericControl(
            title: localized("history.edit.weight"),
            value: formatted(measurement.weightKg),
            identifier: "weight",
            decrement: { changeWeight(by: -2.5, allowsNil: false) },
            increment: { changeWeight(by: 2.5, allowsNil: false) }
        )
    }

    private func optionalWeightControl(_ measurement: SetMeasurementInput) -> some View {
        numericControl(
            title: localized("history.edit.optionalWeight"),
            value: formatted(measurement.weightKg),
            identifier: "weight",
            decrement: { changeWeight(by: -2.5, allowsNil: true) },
            increment: { changeWeight(by: 2.5, allowsNil: true) }
        )
    }

    private func repetitionsControl(_ measurement: SetMeasurementInput) -> some View {
        numericControl(
            title: localized("history.edit.repetitions"),
            value: formatted(measurement.reps),
            identifier: "reps",
            decrement: { changeInteger(\.reps, by: -1) },
            increment: { changeInteger(\.reps, by: 1) }
        )
    }

    private func durationControl(_ measurement: SetMeasurementInput) -> some View {
        numericControl(
            title: localized("history.edit.duration"),
            value: formatted(measurement.durationSec),
            identifier: "duration",
            decrement: { changeInteger(\.durationSec, by: -5) },
            increment: { changeInteger(\.durationSec, by: 5) }
        )
    }

    private func stepsControl(_ measurement: SetMeasurementInput) -> some View {
        numericControl(
            title: localized("history.edit.steps"),
            value: formatted(measurement.distanceSteps),
            identifier: "steps",
            decrement: { changeInteger(\.distanceSteps, by: -1) },
            increment: { changeInteger(\.distanceSteps, by: 1) }
        )
    }

    private func qualityControls(_ measurement: SetMeasurementInput) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(localized("history.edit.quality"))
                .font(AppTypography.label)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            repetitionsControl(measurement)
            durationControl(measurement)
            Button(localized("history.edit.quality.clear")) {
                update { value in
                    value.reps = nil
                    value.durationSec = nil
                }
            }
            .font(AppTypography.label)
            .frame(minHeight: 44)
        }
    }

    private func numericControl(
        title: String,
        value: String,
        identifier: String,
        decrement: @escaping @MainActor () -> Void,
        increment: @escaping @MainActor () -> Void
    ) -> some View {
        AppCard {
            HStack(spacing: AppSpacing.standard) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(title)
                        .font(AppTypography.label)
                    Text(value)
                        .font(AppTypography.numericRow)
                }
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                Spacer()
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(
                    Text(
                        String(
                            format: localized("history.edit.decrement"),
                            locale: .current,
                            title
                        )
                    )
                )
                .accessibilityIdentifier("training.history.edit.\(identifier).decrement")
                Button(action: increment) {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(
                    Text(
                        String(
                            format: localized("history.edit.increment"),
                            locale: .current,
                            title
                        )
                    )
                )
                .accessibilityIdentifier("training.history.edit.\(identifier).increment")
            }
        }
    }

    private func variantControl(_ measurement: SetMeasurementInput) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(localized("history.edit.variant"))
                .font(AppTypography.label)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            TextField(
                localized("history.edit.variant.prompt"),
                text: Binding(
                    get: { measurement.performedVariant ?? "" },
                    set: { variant in
                        update { value in
                            let trimmed = variant.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            value.performedVariant = trimmed.isEmpty ? nil : trimmed
                        }
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("training.history.edit.variant")
        }
    }

    private func rirControl(_ measurement: SetMeasurementInput) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(localized("history.edit.rir"))
                .font(AppTypography.label)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.compact) {
                    rirButton(nil, measurement: measurement)
                    ForEach(0...10, id: \.self) { value in
                        rirButton(value, measurement: measurement)
                    }
                }
            }
        }
    }

    private func rirButton(
        _ value: Int?,
        measurement: SetMeasurementInput
    ) -> some View {
        let isSelected = measurement.rir == value
        return Button {
            update { $0.rir = value }
        } label: {
            Text(value.map(String.init) ?? localized("history.edit.rir.unset"))
                .font(AppTypography.label)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, AppSpacing.small)
                .background(
                    AppColors.color(
                        isSelected ? .accentAction : .backgroundRaised,
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
    }

    @ViewBuilder
    private var mutationMessage: some View {
        switch viewModel.mutationState {
        case .validationFailed:
            Text(localized("history.edit.validationError"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
        case .repositoryFailed:
            Text(localized("history.edit.repositoryError"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
        case .idle, .saving:
            EmptyView()
        }
    }

    private func changeWeight(by delta: Double, allowsNil: Bool) {
        update { measurement in
            let current = measurement.weightKg ?? 0
            let next = current + delta
            if allowsNil, next <= 0 {
                measurement.weightKg = nil
            } else {
                measurement.weightKg = max(0, next)
            }
        }
    }

    private func changeInteger(
        _ keyPath: WritableKeyPath<SetMeasurementInput, Int?>,
        by delta: Int
    ) {
        update { measurement in
            let current = measurement[keyPath: keyPath] ?? 0
            let next = current + delta
            measurement[keyPath: keyPath] = next > 0 ? next : nil
            if keyPath == \.reps, next > 0 {
                measurement.durationSec = nil
            } else if keyPath == \.durationSec, next > 0 {
                measurement.reps = nil
            }
        }
    }

    private func update(_ mutation: (inout SetMeasurementInput) -> Void) {
        guard var measurement = viewModel.editingSet?.measurement else { return }
        mutation(&measurement)
        viewModel.updateEditingMeasurement(measurement)
    }

    private func formatted(_ value: Double?) -> String {
        value?.formatted(
            .number.locale(.current).precision(.fractionLength(0...2))
        ) ?? localized("history.measurement.unset")
    }

    private func formatted(_ value: Int?) -> String {
        value?.formatted(.number.locale(.current)) ??
            localized("history.measurement.unset")
    }

    private func save() {
        Task {
            await viewModel.saveEditingSet()
            if viewModel.editingSet == nil {
                dismiss()
            }
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
