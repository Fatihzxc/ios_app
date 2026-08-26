import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct BodyMetricEntryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: BodyMetricViewModel
    private let editingSnapshot: BodyMetricSnapshot?
    private let onClose: @MainActor () -> Void

    @State private var date = Date.now
    @State private var weightText = ""
    @State private var waistText = ""
    @State private var customName = ""
    @State private var customValueText = ""
    @State private var customUnit = ""
    @State private var localValidationMessage: String?
    @State private var didPrepare = false

    public init(
        viewModel: BodyMetricViewModel,
        editingSnapshot: BodyMetricSnapshot? = nil,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.editingSnapshot = editingSnapshot
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            QuickEntryFormScaffold(
                title: localized(
                    editingSnapshot == nil
                        ? "metrics.entry.title"
                        : "metrics.entry.edit.title"
                ),
                primaryActionTitle: primaryTitle,
                primaryActionAccessibilityLabel: primaryTitle,
                primaryActionAccessibilityIdentifier: primaryIdentifier,
                isPrimaryActionLoading: isSaving,
                isPrimaryActionEnabled: !isSaving,
                secondaryActionTitle: secondaryTitle,
                secondaryActionAccessibilityLabel: secondaryTitle,
                secondaryActionAccessibilityIdentifier: secondaryIdentifier,
                primaryAction: primaryAction,
                secondaryAction: secondaryAction
            ) { focus in
                VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                    DatePicker(
                        localized("metrics.entry.date"),
                        selection: $date,
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("metrics.entry.date")

                    metricField(
                        title: localized("metrics.entry.weight"),
                        unit: localized("metrics.unit.kg"),
                        text: $weightText,
                        identifier: "metrics.entry.weight",
                        focus: focus
                    )
                    metricField(
                        title: localized("metrics.entry.waist"),
                        unit: localized("metrics.unit.cm"),
                        text: $waistText,
                        identifier: "metrics.entry.waist",
                        focus: focus
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(localized("metrics.entry.custom.heading"))
                            .font(AppTypography.titleMedium)
                            .accessibilityAddTraits(.isHeader)
                        TextField(
                            localized("metrics.entry.custom.name"),
                            text: $customName
                        )
                        .textFieldStyle(.roundedBorder)
                        .focused(focus)
                        .accessibilityIdentifier("metrics.entry.custom.name")
                        TextField(
                            localized("metrics.entry.custom.value"),
                            text: $customValueText
                        )
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused(focus)
                        .accessibilityIdentifier("metrics.entry.custom.value")
                        TextField(
                            localized("metrics.entry.custom.unit"),
                            text: $customUnit
                        )
                        .textFieldStyle(.roundedBorder)
                        .focused(focus)
                        .accessibilityIdentifier("metrics.entry.custom.unit")
                    }

                    statePresentation
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task {
            prepareOnce()
        }
    }

    private func metricField(
        title: String,
        unit: String,
        text: Binding<String>,
        identifier: String,
        focus: FocusState<Bool>.Binding
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title)
                .font(AppTypography.label)
            HStack {
                TextField(title, text: text)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused(focus)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(identifier)
                Text(unit)
                    .font(AppTypography.body)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var statePresentation: some View {
        if let message = localValidationMessage
            ?? viewModel.validationIssue?.localizedMessage {
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("metrics.entry.validation")
        }
        if isFailure {
            Text(localized("metrics.entry.save.error"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("metrics.entry.save-error")
        }
        if isSaved {
            Text(localized("metrics.entry.save.success"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.stateSuccess, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("metrics.entry.saved")
        }
        if editingSnapshot != nil {
            Text(localized("metrics.entry.editing"))
                .font(AppTypography.caption)
                .accessibilityIdentifier("metrics.entry.editing")
        }
    }

    private var primaryTitle: String {
        if isSaved { return localized("metrics.entry.close") }
        if isFailure { return localized("metrics.entry.retry") }
        return localized("metrics.entry.save")
    }

    private var primaryIdentifier: String {
        if isSaved { return "metrics.entry.close" }
        if isFailure { return "metrics.entry.retry" }
        return "metrics.entry.save"
    }

    private var secondaryTitle: String? {
        guard editingSnapshot == nil,
              case .saved = viewModel.mutationPhase else { return nil }
        return localized("metrics.entry.undo")
    }

    private var secondaryIdentifier: String? {
        secondaryTitle == nil ? nil : "metrics.entry.undo"
    }

    private var secondaryAction: (() -> Void)? {
        guard secondaryTitle != nil else { return nil }
        return {
            Task { await viewModel.undoLastSave() }
        }
    }

    private var isSaving: Bool {
        if editingSnapshot != nil {
            return viewModel.editPhase == .saving
        }
        switch viewModel.mutationPhase {
        case .saving, .undoing:
            return true
        case .idle, .saved, .saveFailed, .undoFailed:
            return false
        }
    }

    private var isFailure: Bool {
        if editingSnapshot != nil {
            return viewModel.editPhase == .failed
        }
        switch viewModel.mutationPhase {
        case .saveFailed, .undoFailed:
            return true
        case .idle, .saving, .saved, .undoing:
            return false
        }
    }

    private var isSaved: Bool {
        if editingSnapshot != nil {
            return viewModel.editPhase == .saved
        }
        if case .saved = viewModel.mutationPhase { return true }
        return false
    }

    private func primaryAction() {
        if isSaved {
            onClose()
            return
        }
        if editingSnapshot == nil, isFailure {
            Task { await viewModel.retryFailedMutation() }
            return
        }
        Task { await save() }
    }

    private func save() async {
        localValidationMessage = nil
        if let editingSnapshot {
            guard let value = editedValue(for: editingSnapshot.type) else {
                localValidationMessage = localized("metrics.validation.invalid")
                return
            }
            await viewModel.update(editingSnapshot, date: date, value: value)
            return
        }

        do {
            viewModel.weightKilograms = try optionalNumber(from: weightText)
            viewModel.waistCentimeters = try optionalNumber(from: waistText)
            let hasCustomInput = [customName, customValueText, customUnit]
                .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if hasCustomInput {
                guard let customValue = number(from: customValueText) else {
                    throw EntryParseError.invalidNumber
                }
                viewModel.setCustomMetric(
                    try .custom(name: customName, value: customValue, unit: customUnit)
                )
            } else {
                viewModel.setCustomMetric(nil)
            }
            await viewModel.save(date: date)
        } catch {
            localValidationMessage = localized("metrics.validation.invalid")
        }
    }

    private func editedValue(for type: BodyMetricType) -> BodyMetricValueInput? {
        switch type {
        case .weight:
            guard let value = number(from: weightText) else { return nil }
            return try? .weight(kilograms: value)
        case .waist:
            guard let value = number(from: waistText) else { return nil }
            return try? .waist(centimeters: value)
        case .custom:
            guard let value = number(from: customValueText) else { return nil }
            return try? .custom(name: customName, value: value, unit: customUnit)
        }
    }

    private func optionalNumber(from text: String) throws -> Double? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let value = number(from: text) else {
            throw EntryParseError.invalidNumber
        }
        return value
    }

    private func number(from text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        return formatter.number(from: text)?.doubleValue
    }

    private func prepareOnce() {
        guard !didPrepare else { return }
        didPrepare = true
        guard let editingSnapshot else {
            viewModel.prepareForCreation()
            return
        }
        viewModel.prepareForEditing()
        date = editingSnapshot.date
        switch editingSnapshot.type {
        case .weight:
            weightText = formatted(editingSnapshot.value)
        case .waist:
            waistText = formatted(editingSnapshot.value)
        case .custom:
            customName = editingSnapshot.customName ?? ""
            customValueText = formatted(editingSnapshot.value)
            customUnit = editingSnapshot.unit
        }
    }

    private func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}

private enum EntryParseError: Error {
    case invalidNumber
}
