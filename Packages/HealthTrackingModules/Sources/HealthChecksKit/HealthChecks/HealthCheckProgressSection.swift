import DesignSystem
import Foundation
import HealthSafetyKit
import SwiftUI

@MainActor
public struct HealthCheckProgressSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: HealthChecksViewModel
    private let calendar: Calendar
    private let now: @MainActor () -> Date
    private let onOpenBloodwork: @MainActor () -> Void

    public init(
        viewModel: HealthChecksViewModel,
        calendar: Calendar,
        now: @escaping @MainActor () -> Date = { .now },
        onOpenBloodwork: @escaping @MainActor () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.calendar = calendar
        self.now = now
        self.onOpenBloodwork = onOpenBloodwork
    }

    public var body: some View {
        Group {
            switch viewModel.loadPhase {
            case .idle, .loading:
                FeatureStateView(state: .loading)
                    .accessibilityIdentifier("health-check.history.loading")
            case .failed:
                FeatureStateView(
                    state: .error(message: localized("health-check.load.error")),
                    retry: { Task { await viewModel.load() } }
                )
                .accessibilityIdentifier("health-check.history.error")
            case .loaded:
                loadedContent
            }
        }
        .task {
            if viewModel.loadPhase == .idle {
                await viewModel.load()
            }
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(localized("health-check.history.heading"))
                .font(AppTypography.titleMedium)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("health-check.history.loaded")
            Text(MedicalDisclaimerPresentation.permanent.text)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("medical.disclaimer.l1")
            Button(action: onOpenBloodwork) {
                Label(localized("bloodwork.title"), systemImage: "cross.case")
                    .font(AppTypography.label)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("bloodwork.open")
            if viewModel.snapshots.isEmpty {
                AppCard { Text(localized("health-check.empty")) }
            } else {
                ForEach(viewModel.snapshots) { snapshot in
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Text(snapshot.name)
                                .font(AppTypography.label)
                            Text(statusText(snapshot))
                                .font(AppTypography.body)
                            Text(snapshot.dueDate.formatted(date: .abbreviated, time: .omitted))
                                .font(AppTypography.caption)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(rowLabel(snapshot))
                    .accessibilityIdentifier(
                        "health-check.row.\(snapshot.id.uuidString.lowercased())"
                    )
                }
            }
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private func rowLabel(_ snapshot: HealthCheckReminderSnapshot) -> String {
        let dueDate = snapshot.dueDate.formatted(date: .abbreviated, time: .omitted)
        return [snapshot.name, dueDate, statusText(snapshot)].joined(separator: ", ")
    }

    private func statusText(_ snapshot: HealthCheckReminderSnapshot) -> String {
        switch snapshot.dueState(at: now(), calendar: calendar) {
        case .done:
            localized("health-check.status.done")
        case .due:
            localized("health-check.status.due")
        case .pending:
            localized("health-check.status.pending")
        }
    }
}
