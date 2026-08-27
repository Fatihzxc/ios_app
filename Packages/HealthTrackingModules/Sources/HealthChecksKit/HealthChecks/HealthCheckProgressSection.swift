import DesignSystem
import Foundation
import HealthSafetyKit
import SwiftUI

@MainActor
public struct HealthCheckProgressSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: HealthChecksViewModel

    public init(viewModel: HealthChecksViewModel) {
        self.viewModel = viewModel
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
            if viewModel.snapshots.isEmpty {
                AppCard { Text(localized("health-check.empty")) }
            } else {
                ForEach(viewModel.snapshots) { snapshot in
                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Text(snapshot.name)
                                .font(AppTypography.label)
                            Text(snapshot.status == .done
                                ? localized("health-check.status.done")
                                : localized("health-check.status.pending"))
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
        let status = snapshot.status == .done
            ? localized("health-check.status.done")
            : localized("health-check.status.pending")
        return [snapshot.name, status].joined(separator: ", ")
    }
}
