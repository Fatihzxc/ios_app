import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct LifestyleEntryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: LifestyleViewModel
    private let onClose: @MainActor () -> Void

    @State private var date: Date
    @State private var sleepDurationText = ""
    @State private var sleepQualityText = ""
    @State private var sleepNote = ""
    @State private var moodScoreText = ""
    @State private var moodTagsText = ""
    @State private var moodEnergyText = ""
    @State private var moodNote = ""
    @State private var localValidationMessage: String?
    @State private var didPrepare = false

    public init(
        viewModel: LifestyleViewModel,
        initialDate: Date,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        _date = State(initialValue: initialDate)
    }

    public var body: some View {
        NavigationStack {
            QuickEntryFormScaffold(
                title: localized("lifestyle.entry.title"),
                primaryActionTitle: primaryTitle,
                primaryActionAccessibilityLabel: primaryTitle,
                primaryActionAccessibilityIdentifier: primaryIdentifier,
                isPrimaryActionLoading: isSaving,
                isPrimaryActionEnabled: viewModel.loadPhase == .loaded && !isSaving,
                primaryAction: primaryAction
            ) { focus in
                VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                    loadMarker

                    dateField

                    sectionHeading(localized("lifestyle.sleep.heading"))
                    textField(
                        title: localized("lifestyle.sleep.duration"),
                        text: $sleepDurationText,
                        identifier: "lifestyle.sleep.duration",
                        keyboardType: .decimalPad,
                        focus: focus
                    )
                    textField(
                        title: localized("lifestyle.sleep.quality"),
                        text: $sleepQualityText,
                        identifier: "lifestyle.sleep.quality",
                        keyboardType: .numberPad,
                        focus: focus
                    )
                    textField(
                        title: localized("lifestyle.sleep.note"),
                        text: $sleepNote,
                        identifier: "lifestyle.sleep.note",
                        keyboardType: .default,
                        focus: focus
                    )

                    sectionHeading(localized("lifestyle.mood.heading"))
                    textField(
                        title: localized("lifestyle.mood.score"),
                        text: $moodScoreText,
                        identifier: "lifestyle.mood.score",
                        keyboardType: .numberPad,
                        focus: focus
                    )
                    textField(
                        title: localized("lifestyle.mood.tags"),
                        text: $moodTagsText,
                        identifier: "lifestyle.mood.tags",
                        keyboardType: .default,
                        focus: focus
                    )
                    textField(
                        title: localized("lifestyle.mood.energy"),
                        text: $moodEnergyText,
                        identifier: "lifestyle.mood.energy",
                        keyboardType: .numberPad,
                        focus: focus
                    )
                    textField(
                        title: localized("lifestyle.mood.note"),
                        text: $moodNote,
                        identifier: "lifestyle.mood.note",
                        keyboardType: .default,
                        focus: focus
                    )

                    statePresentation
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task { await prepareOnce() }
        .onChange(of: date) { _, newDate in
            guard didPrepare, !isSaving, !isFailure, !isSaved else { return }
            Task {
                await viewModel.load(date: newDate)
                synchronizeFieldsFromViewModel()
            }
        }
    }

    @ViewBuilder
    private var loadMarker: some View {
        switch viewModel.loadPhase {
        case .idle, .loading:
            HStack(spacing: AppSpacing.small) {
                ProgressView()
                    .accessibilityHidden(true)
                Text(localized("lifestyle.entry.loading"))
                    .font(AppTypography.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("lifestyle.entry.loading")
        case .loaded:
            Text(localized("lifestyle.entry.loaded"))
                .font(AppTypography.caption)
                .foregroundStyle(
                    AppColors.color(.inkSecondary, scheme: colorScheme)
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lifestyle.entry.loaded")
        case .failed:
            EmptyView()
        }
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(localized("lifestyle.entry.date"))
                .font(AppTypography.label)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lifestyle.entry.date.label")
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .accessibilityLabel(localized("lifestyle.entry.date"))
                .accessibilityIdentifier("lifestyle.entry.date")
                .disabled(isSaving || isFailure || isSaved)
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.titleMedium)
            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func textField(
        title: String,
        text: Binding<String>,
        identifier: String,
        keyboardType: UIKeyboardType,
        focus: FocusState<Bool>.Binding
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            TextField("", text: text)
                .keyboardType(keyboardType)
                .textFieldStyle(.roundedBorder)
                .focused(focus)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private var statePresentation: some View {
        if viewModel.loadPhase == .failed {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(localized("lifestyle.entry.load.error"))
                    .font(AppTypography.body)
                    .foregroundStyle(
                        AppColors.color(.stateDanger, scheme: colorScheme)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lifestyle.entry.load-error")
                Button(localized("lifestyle.entry.load.retry")) {
                    Task {
                        await viewModel.load(date: date)
                        synchronizeFieldsFromViewModel()
                    }
                }
                .font(AppTypography.label)
                .frame(minHeight: 52)
                .accessibilityIdentifier("lifestyle.entry.load-retry")
            }
        }
        if let message = localValidationMessage
            ?? viewModel.validationIssue?.localizedMessage {
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lifestyle.entry.validation")
        }
        if isFailure {
            Text(localized("lifestyle.entry.save.error"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lifestyle.entry.save-error")
        }
        if isSaved {
            Text(localized("lifestyle.entry.save.success"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.stateSuccess, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lifestyle.entry.saved")
        }
    }

    private var primaryTitle: String {
        if isSaved { return localized("lifestyle.entry.close") }
        if isFailure { return localized("lifestyle.entry.retry") }
        return localized("lifestyle.entry.save")
    }

    private var primaryIdentifier: String {
        if isSaved { return "lifestyle.entry.close" }
        if isFailure { return "lifestyle.entry.retry" }
        return "lifestyle.entry.save"
    }

    private var isSaving: Bool {
        if case .saving = viewModel.savePhase { return true }
        return false
    }

    private var isFailure: Bool {
        if case .saveFailed = viewModel.savePhase { return true }
        return false
    }

    private var isSaved: Bool {
        if case .saved = viewModel.savePhase { return true }
        return false
    }

    private func primaryAction() {
        if isSaved {
            onClose()
        } else if isFailure {
            Task { await viewModel.retrySave() }
        } else {
            Task { await save() }
        }
    }

    private func save() async {
        localValidationMessage = nil
        do {
            let duration = try optionalDouble(sleepDurationText)
            let quality = try optionalInteger(sleepQualityText)
            let score = try optionalInteger(moodScoreText)
            let energy = try optionalInteger(moodEnergyText)

            viewModel.sleepDurationHours = duration
            viewModel.sleepQuality = quality
            viewModel.sleepNote = sleepNote
            viewModel.moodScore = score
            viewModel.moodTagsText = moodTagsText
            viewModel.moodEnergy = energy
            viewModel.moodNote = moodNote
            await viewModel.save(date: date)
        } catch {
            localValidationMessage = localized("lifestyle.validation.number")
        }
    }

    private func prepareOnce() async {
        guard !didPrepare else { return }
        didPrepare = true
        viewModel.prepareForEntry()
        if isFailure {
            synchronizeFieldsFromViewModel()
            return
        }
        await viewModel.load(date: date)
        synchronizeFieldsFromViewModel()
    }

    private func synchronizeFieldsFromViewModel() {
        sleepDurationText = formatted(viewModel.sleepDurationHours)
        sleepQualityText = viewModel.sleepQuality.map(String.init) ?? ""
        sleepNote = viewModel.sleepNote
        moodScoreText = viewModel.moodScore.map(String.init) ?? ""
        moodTagsText = viewModel.moodTagsText
        moodEnergyText = viewModel.moodEnergy.map(String.init) ?? ""
        moodNote = viewModel.moodNote
    }

    private func optionalDouble(_ rawValue: String) throws -> Double? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        guard let value = formatter.number(from: normalized)?.doubleValue,
              value.isFinite else {
            throw EntryParsingError.invalidNumber
        }
        return value
    }

    private func optionalInteger(_ rawValue: String) throws -> Int? {
        guard let value = try optionalDouble(rawValue) else { return nil }
        guard value.rounded() == value,
              value >= Double(Int.min),
              value <= Double(Int.max) else {
            throw EntryParsingError.invalidNumber
        }
        return Int(value)
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private enum EntryParsingError: Error {
        case invalidNumber
    }
}
