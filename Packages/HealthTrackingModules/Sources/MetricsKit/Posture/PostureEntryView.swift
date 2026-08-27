import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct PostureEntryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AccessibilityFocusState private var levelTwoHeadingFocused: Bool
    @Bindable private var viewModel: PostureViewModel
    private let initialDate: Date
    private let onClose: @MainActor () -> Void

    @State private var date: Date
    @State private var symptomText = ""
    @State private var didPrepare = false

    public init(
        viewModel: PostureViewModel,
        initialDate: Date = .now,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.initialDate = initialDate
        self.onClose = onClose
        _date = State(initialValue: initialDate)
    }

    public var body: some View {
        NavigationStack {
            QuickEntryFormScaffold(
                title: localized("posture.entry.title"),
                primaryActionTitle: localized("posture.entry.save"),
                primaryActionAccessibilityLabel: localized("posture.entry.save"),
                primaryActionAccessibilityIdentifier: "posture.entry.save",
                isPrimaryActionLoading: isSaving,
                isPrimaryActionEnabled: !isSaving,
                secondaryActionTitle: localized("posture.entry.close"),
                secondaryActionAccessibilityLabel: localized("posture.entry.close"),
                secondaryActionAccessibilityIdentifier: "posture.entry.close",
                primaryAction: {
                    Task { await viewModel.save(date: date) }
                },
                secondaryAction: onClose
            ) { focus in
                formContent(focus: focus)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
        }
        .task {
            guard !didPrepare else { return }
            didPrepare = true
            date = initialDate
            if viewModel.loadPhase == .idle {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private func formContent(focus: FocusState<Bool>.Binding) -> some View {
        switch viewModel.loadPhase {
        case .idle, .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("posture.entry.loading")
        case .failed:
            FeatureStateView(
                state: .error(message: localized("posture.entry.load.error")),
                retry: { Task { await viewModel.load() } }
            )
            .accessibilityIdentifier("posture.entry.load-error")
        case .loaded:
            VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                Text(localized("posture.entry.loaded"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("posture.entry.loaded")

                safetyContent

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(localized("posture.entry.date"))
                        .font(AppTypography.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 160, alignment: .leading)
                        .accessibilityIdentifier("posture.entry.date.label")
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel(localized("posture.entry.date"))
                        .accessibilityIdentifier("posture.entry.date")
                }

                wallTestField

                textField(
                    title: localized("posture.entry.symptom"),
                    text: $symptomText,
                    identifier: "posture.entry.symptom",
                    keyboardType: .numberPad,
                    focus: focus
                )
                .onChange(of: symptomText) { _, value in
                    viewModel.symptomScore = Int(value)
                }

                textField(
                    title: localized("posture.entry.region"),
                    text: $viewModel.region,
                    identifier: "posture.entry.region",
                    keyboardType: .default,
                    focus: focus
                )

                textField(
                    title: localized("posture.entry.note"),
                    text: $viewModel.note,
                    identifier: "posture.entry.note",
                    keyboardType: .default,
                    focus: focus
                )

                mutationStatus
                validationStatus
            }
        }
    }

    private var safetyContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(viewModel.safetyPresentation.disclaimer.text)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("medical.disclaimer.l1")
            if let notice = viewModel.safetyPresentation.levelTwo {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(localized("medical.safety.l2.heading"))
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("medical.safety.l2.heading")
                        .accessibilityFocused($levelTwoHeadingFocused)
                    Text(notice.message)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("medical.safety.l2")
                }
                .onAppear {
                    updateLevelTwoHeadingFocus(isPresented: true)
                }
                .transition(levelTwoTransition)
            }
        }
        .onChange(of: isLevelTwoPresented) { _, isPresented in
            updateLevelTwoHeadingFocus(isPresented: isPresented)
        }
    }

    private var isLevelTwoPresented: Bool {
        viewModel.safetyPresentation.levelTwo != nil
    }

    private var levelTwoTransition: AnyTransition {
        MedicalSafetyMotionPolicy.transition(
            reduceMotion: accessibilityReduceMotion,
            identity: .identity,
            opacity: .opacity
        )
    }

    private func updateLevelTwoHeadingFocus(isPresented: Bool) {
        levelTwoHeadingFocused = MedicalSafetyFocusPolicy.headingFocused(
            isLevelTwoPresented: isPresented
        )
    }

    private var wallTestField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(localized("posture.entry.wall"))
                .font(AppTypography.label)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("posture.entry.wall.label")
            HStack(spacing: AppSpacing.standard) {
                wallButton(
                    title: localized("posture.entry.wall.pass"),
                    value: true,
                    identifier: "posture.entry.wall.pass"
                )
                wallButton(
                    title: localized("posture.entry.wall.fail"),
                    value: false,
                    identifier: "posture.entry.wall.fail"
                )
            }
        }
    }

    private func wallButton(
        title: String,
        value: Bool,
        identifier: String
    ) -> some View {
        Button {
            viewModel.wallTestPass = value
        } label: {
            Label(
                title,
                systemImage: viewModel.wallTestPass == value
                    ? "checkmark.circle.fill"
                    : "circle"
            )
            .font(AppTypography.label)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(identifier)
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
                .fixedSize(horizontal: false, vertical: true)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(keyboardType)
                .focused(focus)
                .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private var mutationStatus: some View {
        switch viewModel.savePhase {
        case .idle, .saving:
            EmptyView()
        case .saved:
            Text(localized("posture.entry.saved"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.stateSuccess, scheme: colorScheme))
                .accessibilityIdentifier("posture.entry.saved")
        case .failed:
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(localized("posture.entry.save.error"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("posture.entry.save-error")
                Button(localized("posture.entry.retry")) {
                    Task { await viewModel.retrySave() }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 52)
                .accessibilityIdentifier("posture.entry.retry")
            }
        }
    }

    @ViewBuilder
    private var validationStatus: some View {
        if let issue = viewModel.validationIssue {
            Text(issue.localizedMessage)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(issue.id)
        }
    }

    private var isSaving: Bool {
        if case .saving = viewModel.savePhase { return true }
        return false
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
