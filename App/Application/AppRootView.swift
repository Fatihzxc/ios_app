import Foundation
import NutritionKit
import ReportsKit
import SettingsKit
import SwiftUI
import TrainingKit

@MainActor
struct AppRootView: View {
    let todayViewModel: TodayViewModel
    let foundationViewModel: FoundationProgramViewModel
    let phaseTransitionViewModel: PhaseTransitionViewModel
    let trainingHistoryViewModel: TrainingHistoryViewModel
    let makeSessionViewModel: @MainActor () -> SessionViewModel
    let shouldLoadFoundation: Bool
    let persistencePresentation: FoundationPersistencePresentation

    @State private var selectedTab = AppTab.today
    @State private var hasStartedFoundationLoad = false
    @State private var sessionRoute: SessionRoute?

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                modernTabView
            } else {
                legacyTabView
            }
        }
        .background {
            TabBarAccessibilityIdentifierInstaller(
                identifiers: AppTab.allCases.map(\.tabIdentifier)
            )
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .task {
            guard shouldLoadFoundation, !hasStartedFoundationLoad else { return }
            hasStartedFoundationLoad = true
            if todayViewModel.state == .loading {
                await todayViewModel.load()
            }
            await foundationViewModel.load()
            await phaseTransitionViewModel.load()
        }
        .fullScreenCover(item: $sessionRoute) { route in
            TrainingSessionView(
                viewModel: route.viewModel,
                workoutDayID: route.workoutDayID,
                onClose: {
                    sessionRoute = nil
                    Task {
                        await todayViewModel.load()
                        await foundationViewModel.load()
                        await phaseTransitionViewModel.load()
                        await trainingHistoryViewModel.load()
                    }
                }
            )
        }
    }

    @available(iOS 18.0, *)
    private var modernTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(value: tab) {
                    tabContent(for: tab)
                } label: {
                    tabLabel(for: tab)
                }
                .accessibilityIdentifier(tab.tabIdentifier)
                .accessibilityHint(tab.hint)
            }
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                tabContent(for: tab)
                    .tag(tab)
                    .tabItem { legacyTabLabel(for: tab) }
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayView(
                viewModel: todayViewModel,
                onPerformAction: performTodayAction
            )
        case .training:
            FoundationProgramView(
                viewModel: foundationViewModel,
                phaseTransitionViewModel: phaseTransitionViewModel,
                historyViewModel: trainingHistoryViewModel,
                onOpenSession: openSession
            )
        case .nutrition:
            NutritionFoundationView()
        case .progress:
            ReportsFoundationView()
        case .settings:
            SettingsFoundationView(
                persistencePresentation: persistencePresentation,
                phaseTransitionViewModel: phaseTransitionViewModel
            )
        }
    }

    private func tabLabel(for tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }

    private func legacyTabLabel(for tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
            .accessibilityIdentifier(tab.tabIdentifier)
            .accessibilityHint(tab.hint)
    }

    private func openSession(workoutDayID: UUID) {
        sessionRoute = SessionRoute(
            workoutDayID: workoutDayID,
            viewModel: makeSessionViewModel()
        )
    }

    private func performTodayAction(_ action: TodayMainAction) {
        openSession(workoutDayID: action.workoutDayID)
    }
}

private struct SessionRoute: Identifiable {
    let id = UUID()
    let workoutDayID: UUID
    let viewModel: SessionViewModel
}
