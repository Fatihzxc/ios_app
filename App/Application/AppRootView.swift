import NutritionKit
import ReportsKit
import SettingsKit
import SwiftUI
import TrainingKit

@MainActor
struct AppRootView: View {
    let foundationViewModel: FoundationProgramViewModel
    let shouldLoadFoundation: Bool
    let persistencePresentation: FoundationPersistencePresentation

    @State private var selectedTab = AppTab.today
    @State private var hasStartedFoundationLoad = false

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
            await foundationViewModel.load()
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
            FoundationTodayView(viewModel: foundationViewModel)
        case .training:
            FoundationProgramView(viewModel: foundationViewModel)
        case .nutrition:
            NutritionFoundationView()
        case .progress:
            ReportsFoundationView()
        case .settings:
            SettingsFoundationView(persistencePresentation: persistencePresentation)
        }
    }

    private func tabLabel(for tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }

    private func legacyTabLabel(for tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
            .accessibilityIdentifier(tab.tabIdentifier)
    }
}
