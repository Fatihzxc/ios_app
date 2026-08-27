import DesignSystem
import Foundation
import HealthSafetyKit
import SwiftUI

@MainActor
public struct HealthCheckListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: HealthChecksViewModel
    private let calendar: Calendar
    private let now: @MainActor () -> Date
    private let onClose: @MainActor () -> Void

    @State private var selectedID: UUID?

    public init(
        viewModel: HealthChecksViewModel,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @MainActor () -> Date = { .now },
        onClose: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.calendar = calendar
        self.now = now
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let selected = selectedSnapshot {
                        detail(selected)
                    } else {
                        listContent
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(localized("health-check.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized("health-check.close"), action: onClose)
                        .accessibilityIdentifier("health-check.close")
                }
            }
        }
        .task {
            if viewModel.loadPhase == .idle {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        switch viewModel.loadPhase {
        case .idle, .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("health-check.list.loading")
        case .failed:
            FeatureStateView(
                state: .error(message: localized("health-check.load.error")),
                retry: { Task { await viewModel.load() } }
            )
            .accessibilityIdentifier("health-check.list.error")
        case .loaded:
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                disclaimer
                Text(localized("health-check.list.loaded"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .accessibilityIdentifier("health-check.list.loaded")
                if viewModel.snapshots.isEmpty {
                    AppCard {
                        Text(localized("health-check.empty"))
                            .font(AppTypography.body)
                    }
                } else {
                    ForEach(viewModel.snapshots) { snapshot in
                        Button {
                            selectedID = snapshot.id
                        } label: {
                            row(snapshot)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(rowLabel(snapshot))
                        .accessibilityIdentifier(rowIdentifier(snapshot))
                    }
                }
            }
        }
    }

    private func detail(_ snapshot: HealthCheckReminderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            disclaimer
            Button {
                selectedID = nil
            } label: {
                Label(localized("health-check.detail.back"), systemImage: "chevron.left")
                    .frame(minHeight: 52)
            }
            .accessibilityIdentifier("health-check.detail.back")

            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(snapshot.name)
                        .font(AppTypography.titleMedium)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(snapshot.dueDate.formatted(date: .abbreviated, time: .shortened))
                        .font(AppTypography.body)
                    Text(statusText(snapshot))
                        .font(AppTypography.label)
                }
            }

            if snapshot.status == .pending {
                PrimaryActionButton(
                    title: localized("health-check.detail.complete"),
                    accessibilityLabel: localized("health-check.detail.complete")
                ) {
                    Task { await viewModel.complete(snapshot) }
                }
                .frame(minHeight: 52)
                .disabled(viewModel.mutationPhase == .saving)
                .accessibilityIdentifier("health-check.detail.complete")
            } else {
                Text(localized("health-check.detail.completed"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.stateSuccess, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("health-check.detail.completed")
            }

            if viewModel.mutationPhase == .failed {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(localized("health-check.detail.complete.error"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("health-check.detail.complete-error")
                    Button(localized("health-check.detail.retry")) {
                        Task { await viewModel.retryCompletion() }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("health-check.detail.retry")
                }
            }

            if let successor = viewModel.lastCompletion?.successor,
               viewModel.lastCompletion?.completed.id == snapshot.id {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(localized("health-check.detail.successor.heading"))
                            .font(AppTypography.label)
                        Text(successor.dueDate.formatted(date: .abbreviated, time: .shortened))
                            .font(AppTypography.body)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("health-check.detail.successor")
            }
        }
    }

    private var disclaimer: some View {
        Text(MedicalDisclaimerPresentation.permanent.text)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("medical.disclaimer.l1")
    }

    private func row(_ snapshot: HealthCheckReminderSnapshot) -> some View {
        AppCard {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.standard) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(snapshot.name)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(snapshot.dueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                }
                Spacer(minLength: AppSpacing.small)
                Text(statusText(snapshot))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
    }

    private var selectedSnapshot: HealthCheckReminderSnapshot? {
        guard let selectedID else { return nil }
        return viewModel.snapshots.first(where: { $0.id == selectedID })
    }

    private func statusText(_ snapshot: HealthCheckReminderSnapshot) -> String {
        switch snapshot.dueState(at: now(), calendar: calendar) {
        case .done:
            localized("health-check.status.done")
        case .due, .pending:
            localized("health-check.status.pending")
        }
    }

    private func rowLabel(_ snapshot: HealthCheckReminderSnapshot) -> String {
        "\(snapshot.name), \(statusText(snapshot))"
    }

    private func rowIdentifier(_ snapshot: HealthCheckReminderSnapshot) -> String {
        "health-check.row.\(snapshot.id.uuidString.lowercased())"
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
