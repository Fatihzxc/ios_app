import DesignSystem
import Foundation
import HealthSafetyKit
import SwiftUI
import UIKit

@MainActor
public struct BloodworkListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: BloodworkViewModel
    private let now: @MainActor () -> Date
    private let onCommittedMutation: @MainActor () -> Void
    private let onClose: @MainActor () -> Void

    @State private var destination = Destination.list
    @State private var date: Date
    @State private var marker = ""
    @State private var valueText = ""
    @State private var unit = ""
    @State private var note = ""
    @State private var localValidationMessage: String?
    @State private var isConfirmingDelete = false

    public init(
        viewModel: BloodworkViewModel,
        now: @escaping @MainActor () -> Date = { .now },
        onCommittedMutation: @escaping @MainActor () -> Void = {},
        onClose: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.now = now
        self.onCommittedMutation = onCommittedMutation
        self.onClose = onClose
        _date = State(initialValue: now())
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch destination {
                case .list:
                    listRoot
                case let .detail(id):
                    detailRoot(id: id)
                case let .editor(id):
                    editorRoot(id: id)
                }
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(localized("bloodwork.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized("bloodwork.close"), action: onClose)
                        .accessibilityIdentifier("bloodwork.close")
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task {
            if viewModel.loadPhase == .idle {
                await viewModel.load()
            }
        }
    }

    private var listRoot: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                Text(localized("bloodwork.title"))
                    .font(AppTypography.titleLarge)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("bloodwork.list.content")
                disclaimer
                listState
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var listState: some View {
        switch viewModel.loadPhase {
        case .idle, .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("bloodwork.list.loading")
        case .failed:
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                FeatureStateView(
                    state: .error(message: localized("bloodwork.load.error"))
                )
                .accessibilityIdentifier("bloodwork.list.error")
                Button(localized("bloodwork.retry")) {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 52)
                .accessibilityIdentifier("bloodwork.list.retry")
            }
        case .loaded:
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                PrimaryActionButton(
                    title: localized("bloodwork.add"),
                    accessibilityLabel: localized("bloodwork.add")
                ) {
                    openCreateEditor()
                }
                .accessibilityIdentifier("bloodwork.add")

                if viewModel.snapshots.isEmpty {
                    AppCard {
                        Text(localized("bloodwork.empty"))
                            .font(AppTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("bloodwork.list.empty")
                } else {
                    ForEach(viewModel.snapshots) { snapshot in
                        Button {
                            destination = .detail(snapshot.id)
                        } label: {
                            row(snapshot)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(rowLabel(snapshot))
                        .accessibilityIdentifier("bloodwork.row.\(snapshot.id.uuidString)")
                    }
                }
            }
        }
    }

    private func detailRoot(id: UUID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                disclaimer
                backButton(destination: .list)
                if let snapshot = viewModel.snapshots.first(where: { $0.id == id }) {
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Text(snapshot.marker)
                                .font(AppTypography.titleLarge)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("bloodwork.detail.content")
                            Text(snapshot.date.formatted(date: .abbreviated, time: .omitted))
                                .font(AppTypography.body)
                            Text(valueLabel(snapshot))
                                .font(AppTypography.titleMedium)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("bloodwork.detail.value")
                            if let note = snapshot.note {
                                Text(note)
                                    .font(AppTypography.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Button(localized("bloodwork.detail.edit")) {
                        openEditEditor(snapshot)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("bloodwork.detail.edit")

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Text(localized("bloodwork.detail.delete"))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("bloodwork.detail.delete")

                    detailMutationState(snapshot)
                } else {
                    AppCard {
                        Text(localized("bloodwork.empty"))
                            .font(AppTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            localized("bloodwork.delete.confirmation"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(localized("bloodwork.detail.delete"), role: .destructive) {
                Task { await delete(id: id) }
            }
            .accessibilityIdentifier("bloodwork.detail.delete-confirm")
            Button(localized("bloodwork.cancel"), role: .cancel) {}
        }
    }

    private func editorRoot(id: UUID?) -> some View {
        QuickEntryFormScaffold(
            title: localized(id == nil ? "bloodwork.editor.add.title" : "bloodwork.editor.edit.title"),
            primaryActionTitle: editorPrimaryTitle,
            primaryActionAccessibilityLabel: editorPrimaryTitle,
            primaryActionAccessibilityIdentifier: editorPrimaryIdentifier,
            isPrimaryActionLoading: isSaving,
            isPrimaryActionEnabled: !isSaving,
            secondaryActionTitle: localized("bloodwork.cancel"),
            secondaryActionAccessibilityLabel: localized("bloodwork.cancel"),
            secondaryActionAccessibilityIdentifier: "bloodwork.editor.cancel",
            primaryAction: { editorPrimaryAction(id: id) },
            secondaryAction: { destination = id.map(Destination.detail) ?? .list }
        ) { focus in
            VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                Text(localized("bloodwork.editor.reference-only"))
                    .font(AppTypography.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bloodwork.editor.content")
                disclaimer

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(localized("bloodwork.editor.date"))
                        .font(AppTypography.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("bloodwork.editor.date.label")
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel(localized("bloodwork.editor.date"))
                        .accessibilityIdentifier("bloodwork.editor.date")
                }

                field(
                    title: localized("bloodwork.editor.marker"),
                    text: $marker,
                    identifier: "bloodwork.editor.marker",
                    keyboardType: .default,
                    focus: focus
                )
                field(
                    title: localized("bloodwork.editor.value"),
                    text: $valueText,
                    identifier: "bloodwork.editor.value",
                    keyboardType: .numbersAndPunctuation,
                    focus: focus
                )
                field(
                    title: localized("bloodwork.editor.unit"),
                    text: $unit,
                    identifier: "bloodwork.editor.unit",
                    keyboardType: .default,
                    focus: focus
                )
                field(
                    title: localized("bloodwork.editor.note"),
                    text: $note,
                    identifier: "bloodwork.editor.note",
                    keyboardType: .default,
                    focus: focus
                )

                editorState
            }
        }
    }

    private func field(
        title: String,
        text: Binding<String>,
        identifier: String,
        keyboardType: UIKeyboardType,
        focus: FocusState<Bool>.Binding
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title)
                .font(AppTypography.label)
                .fixedSize(horizontal: false, vertical: true)
            TextField(title, text: text)
                .keyboardType(keyboardType)
                .textFieldStyle(.roundedBorder)
                .focused(focus)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }

    private var disclaimer: some View {
        Text(MedicalDisclaimerPresentation.permanent.text)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("bloodwork.disclaimer.l1")
    }

    private func row(_ snapshot: BloodworkResultSnapshot) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(snapshot.marker)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                Text(valueLabel(snapshot))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                Text(snapshot.date.formatted(date: .abbreviated, time: .omitted))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rowLabel(_ snapshot: BloodworkResultSnapshot) -> String {
        "\(snapshot.marker), \(valueLabel(snapshot)), "
            + snapshot.date.formatted(date: .abbreviated, time: .omitted)
    }

    private func valueLabel(_ snapshot: BloodworkResultSnapshot) -> String {
        "\(formatted(snapshot.value)) \(snapshot.unit)"
    }

    private func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func backButton(destination: Destination) -> some View {
        Button {
            self.destination = destination
        } label: {
            Label(localized("bloodwork.back"), systemImage: "chevron.left")
                .frame(minHeight: 52)
        }
        .accessibilityIdentifier("bloodwork.back")
    }

    @ViewBuilder
    private func detailMutationState(_ snapshot: BloodworkResultSnapshot) -> some View {
        if viewModel.editPhase == .failed {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(localized("bloodwork.mutation.error"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                    .accessibilityIdentifier("bloodwork.detail.delete-error")
                Button(localized("bloodwork.retry")) {
                    Task { await delete(snapshot: snapshot) }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 52)
                .accessibilityIdentifier("bloodwork.detail.delete-retry")
            }
        }

        if viewModel.lastCreatedSnapshot?.id == snapshot.id {
            switch viewModel.mutationPhase {
            case .saved:
                Button(localized("bloodwork.detail.undo")) {
                    Task {
                        if await viewModel.undoLastCreate() {
                            onCommittedMutation()
                            destination = .list
                        }
                    }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 52)
                .accessibilityIdentifier("bloodwork.detail.undo")
            case .undoFailed:
                Button(localized("bloodwork.retry")) {
                    Task {
                        if await viewModel.retryUndo() {
                            onCommittedMutation()
                            destination = .list
                        }
                    }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 52)
                .accessibilityIdentifier("bloodwork.detail.undo-retry")
            case .idle, .saving, .saveFailed, .undoing:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var editorState: some View {
        if let localValidationMessage {
            Text(localValidationMessage)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("bloodwork.editor.validation")
        }
        if isEditorFailure {
            Text(localized("bloodwork.mutation.error"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("bloodwork.editor.save-error")
        }
    }

    private var editorPrimaryTitle: String {
        isEditorFailure
            ? localized("bloodwork.retry")
            : localized("bloodwork.editor.save")
    }

    private var editorPrimaryIdentifier: String {
        isEditorFailure ? "bloodwork.editor.retry" : "bloodwork.editor.save"
    }

    private var isEditorFailure: Bool {
        switch destination {
        case .editor(nil):
            switch viewModel.mutationPhase {
            case .saveFailed, .undoFailed:
                true
            case .idle, .saving, .saved, .undoing:
                false
            }
        case .editor(.some(_)):
            viewModel.editPhase == .failed
        case .list, .detail(_):
            false
        }
    }

    private var isSaving: Bool {
        if viewModel.editPhase == .saving { return true }
        switch viewModel.mutationPhase {
        case .saving, .undoing:
            return true
        case .idle, .saved, .saveFailed, .undoFailed:
            return false
        }
    }

    private func editorPrimaryAction(id: UUID?) {
        if isEditorFailure, id == nil {
            Task {
                if await viewModel.retryCreate(),
                   let created = viewModel.lastCreatedSnapshot {
                    onCommittedMutation()
                    destination = .detail(created.id)
                }
            }
            return
        }
        Task { await saveEditor(id: id) }
    }

    private func saveEditor(id: UUID?) async {
        let input: BloodworkResultInput
        do {
            input = try BloodworkResultInput(
                date: date,
                marker: marker,
                value: try parsedValue(),
                unit: unit,
                note: note
            )
        } catch {
            localValidationMessage = localized("bloodwork.validation.invalid")
            return
        }
        localValidationMessage = nil

        if let id,
           let snapshot = viewModel.snapshots.first(where: { $0.id == id }) {
            if await viewModel.update(snapshot, input: input) {
                onCommittedMutation()
                destination = .detail(id)
            }
            return
        }

        if await viewModel.create(input),
           let created = viewModel.lastCreatedSnapshot {
            onCommittedMutation()
            destination = .detail(created.id)
        }
    }

    private func parsedValue() throws -> Double {
        let canonical = valueText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(canonical), parsed.isFinite else {
            throw BloodworkResultInputError.nonFiniteValue
        }
        return parsed
    }

    private func openCreateEditor() {
        viewModel.prepareForCreation()
        date = now()
        marker = ""
        valueText = ""
        unit = ""
        note = ""
        localValidationMessage = nil
        destination = .editor(nil)
    }

    private func openEditEditor(_ snapshot: BloodworkResultSnapshot) {
        viewModel.prepareForEditing()
        date = snapshot.date
        marker = snapshot.marker
        valueText = String(snapshot.value)
        unit = snapshot.unit
        note = snapshot.note ?? ""
        localValidationMessage = nil
        destination = .editor(snapshot.id)
    }

    private func delete(id: UUID) async {
        guard let snapshot = viewModel.snapshots.first(where: { $0.id == id }) else {
            destination = .list
            return
        }
        await delete(snapshot: snapshot)
    }

    private func delete(snapshot: BloodworkResultSnapshot) async {
        if await viewModel.delete(snapshot) {
            onCommittedMutation()
            destination = .list
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}

private enum Destination: Equatable {
    case list
    case detail(UUID)
    case editor(UUID?)
}
