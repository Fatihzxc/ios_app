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
    let todayNutritionViewModel: TodayNutritionViewModel
    let nutritionDayViewModel: NutritionDayViewModel
    let foodLibraryViewModel: FoodLibraryViewModel
    let recipeLibraryViewModel: RecipeLibraryViewModel
    let nutritionQuickAddViewModel: NutritionQuickAddViewModel
    let nutritionManualEntryViewModel: NutritionManualEntryViewModel
    let makeSessionViewModel: @MainActor () -> SessionViewModel
    let makeTrackerFeatureRouter: @MainActor () -> any TrackerFeatureRouting
    let trainingHapticController: TrainingHapticController?
    let shouldLoadFoundation: Bool
    let persistencePresentation: FoundationPersistencePresentation

    @State private var selectedTab = AppTab.today
    @State private var hasStartedFoundationLoad = false
    @State private var sessionRoute: SessionRoute?
    @State private var nutritionQuickAddIntent: NutritionQuickAddIntent?
    @State private var trackerFeatureRouter: (any TrackerFeatureRouting)?
    @State private var trackerEntryRoute: TrackerEntryRoute?

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
        .overlay(alignment: .topLeading) {
            #if DEBUG
            if exposesLaunchPerformanceEvidence,
               let evidence = AppLaunchPerformance.evidenceValue() {
                Text(String(localized: "today.performance.breakdown"))
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("today.performance.breakdown")
                    .accessibilityValue(evidence)
                    .allowsHitTesting(false)
            }
            #endif
        }
        .task {
            guard shouldLoadFoundation, !hasStartedFoundationLoad else { return }
            hasStartedFoundationLoad = true
            if todayViewModel.state == .loading {
                await todayViewModel.load()
            }
            async let nutritionLoad: Void = loadTodayNutritionIfMeaningful()
            await foundationViewModel.load()
            await phaseTransitionViewModel.load()
            await nutritionLoad
        }
        .fullScreenCover(item: $sessionRoute) { route in
            TrainingSessionView(
                viewModel: route.viewModel,
                workoutDayID: route.workoutDayID,
                onClose: {
                    sessionRoute = nil
                    Task {
                        await todayViewModel.load()
                        await loadTodayNutritionIfMeaningful()
                        await foundationViewModel.load()
                        await phaseTransitionViewModel.load()
                        await trainingHistoryViewModel.load()
                    }
                }
            )
        }
        .sheet(item: $trackerEntryRoute) { route in
            if let trackerFeatureRouter {
                switch route {
                case .bodyMetric:
                    trackerFeatureRouter.makeBodyMetricEntryView(
                        onClose: { trackerEntryRoute = nil }
                    )
                case .lifestyle:
                    trackerFeatureRouter.makeLifestyleEntryView(
                        onClose: { trackerEntryRoute = nil }
                    )
                case .posture:
                    trackerFeatureRouter.makePostureEntryView(
                        onClose: { trackerEntryRoute = nil }
                    )
                case .healthChecks:
                    trackerFeatureRouter.makeHealthCheckListView(
                        onCommittedMutation: {
                            Task { await todayViewModel.load() }
                        },
                        onClose: { trackerEntryRoute = nil }
                    )
                case .bloodwork:
                    trackerFeatureRouter.makeBloodworkListView(
                        onCommittedMutation: {},
                        onClose: { trackerEntryRoute = nil }
                    )
                case .progressPhotos:
                    trackerFeatureRouter.makeProgressPhotoLifecycleView(
                        onClose: { trackerEntryRoute = nil }
                    )
                }
            }
        }
        .onChange(of: selectedTab) { _, selectedTab in
            if selectedTab == .progress {
                resolveTrackerFeatureBundle()
            }
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
                nutritionState: todayNutritionViewModel.state,
                exposesLaunchPerformanceEvidence: exposesLaunchPerformanceEvidence,
                onPerformAction: performTodayAction,
                onAddMeal: performTodayNutritionAction,
                onOpenTrackers: performTodayTrackerAction,
                onOpenLifestyle: performTodayLifestyleAction,
                onOpenPosture: performTodayPostureAction,
                onOpenHealthChecks: performTodayHealthCheckAction
            )
        case .training:
            FoundationProgramView(
                viewModel: foundationViewModel,
                phaseTransitionViewModel: phaseTransitionViewModel,
                historyViewModel: trainingHistoryViewModel,
                onOpenSession: openSession
            )
        case .nutrition:
            NutritionFoundationView(
                dayViewModel: nutritionDayViewModel,
                foodLibraryViewModel: foodLibraryViewModel,
                recipeLibraryViewModel: recipeLibraryViewModel,
                quickAddViewModel: nutritionQuickAddViewModel,
                manualEntryViewModel: nutritionManualEntryViewModel,
                externalQuickAddIntent: nutritionQuickAddIntent,
                onNutritionSnapshot: publishNutritionSnapshot
            )
        case .progress:
            if let trackerFeatureRouter {
                trackerFeatureRouter.makeProgressView(
                    onOpenBloodwork: {
                        trackerEntryRoute = .bloodwork
                    },
                    onOpenProgressPhotos: {
                        trackerEntryRoute = .progressPhotos
                    }
                )
            } else {
                ReportsFoundationView()
            }
        case .settings:
            SettingsFoundationView(
                persistencePresentation: persistencePresentation,
                phaseTransitionViewModel: phaseTransitionViewModel,
                trainingHapticController: trainingHapticController
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

    private func loadTodayNutritionIfMeaningful() async {
        guard case .content = todayViewModel.state else { return }
        await todayNutritionViewModel.load()
    }

    private func performTodayNutritionAction() {
        let date = Date.now
        guard let intent = try? NutritionQuickAddIntent.suggested(
            at: date,
            calendar: .autoupdatingCurrent
        ) else { return }
        selectedTab = .nutrition
        nutritionQuickAddIntent = intent
    }

    private func performTodayTrackerAction() {
        resolveTrackerFeatureBundle()
        trackerEntryRoute = .bodyMetric
    }

    private func performTodayLifestyleAction() {
        resolveTrackerFeatureBundle()
        trackerEntryRoute = .lifestyle
    }

    private func performTodayPostureAction() {
        resolveTrackerFeatureBundle()
        trackerEntryRoute = .posture
    }

    private func performTodayHealthCheckAction() {
        resolveTrackerFeatureBundle()
        trackerEntryRoute = .healthChecks
    }

    private func resolveTrackerFeatureBundle() {
        guard trackerFeatureRouter == nil else { return }
        trackerFeatureRouter = makeTrackerFeatureRouter()
    }

    private func publishNutritionSnapshot(
        _ snapshot: NutritionDayEntriesSnapshot,
        _ targets: NutritionMacroTargets?
    ) {
        todayNutritionViewModel.apply(snapshot: snapshot, targets: targets)
    }

    private var exposesLaunchPerformanceEvidence: Bool {
        #if DEBUG
        AppUITestLaunchConfiguration.resolve()?.exposesLaunchPerformanceEvidence == true
        #else
        false
        #endif
    }
}

private struct SessionRoute: Identifiable {
    let id = UUID()
    let workoutDayID: UUID
    let viewModel: SessionViewModel
}

private enum TrackerEntryRoute: String, Identifiable {
    case bodyMetric
    case lifestyle
    case posture
    case healthChecks
    case bloodwork
    case progressPhotos

    var id: String { rawValue }
}
