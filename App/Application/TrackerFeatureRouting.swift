import SwiftUI

@MainActor
protocol TrackerFeatureRouting: AnyObject {
    func refreshReports() async

    func reconcileHealthCheckNotificationsAfterFirstMeaningfulTodayContent() async throws
    func reconcileHealthCheckNotificationsAfterCommittedMutation() async throws
    func requestHealthCheckNotificationAuthorizationFromExplicitUserAction() async

    func makeBodyMetricEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView

    func makeLifestyleEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView

    func makePostureEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView

    func makeHealthCheckListView(
        onCommittedMutation: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView

    func makeBloodworkListView(
        onCommittedMutation: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView

    func makeProgressPhotoLifecycleView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView

    func makeProgressView(
        onOpenBodyMetric: @escaping @MainActor () -> Void,
        onOpenLifestyle: @escaping @MainActor () -> Void,
        onOpenPosture: @escaping @MainActor () -> Void,
        onOpenHealthChecks: @escaping @MainActor () -> Void,
        onOpenBloodwork: @escaping @MainActor () -> Void,
        onOpenProgressPhotos: @escaping @MainActor () -> Void
    ) -> AnyView

    func makeProgressView(
        onOpenBodyMetric: @escaping @MainActor () -> Void,
        onOpenLifestyle: @escaping @MainActor () -> Void,
        onOpenPosture: @escaping @MainActor () -> Void,
        onOpenHealthChecks: @escaping @MainActor () -> Void,
        onOpenBloodwork: @escaping @MainActor () -> Void,
        onOpenProgressPhotos: @escaping @MainActor () -> Void,
        loadsReportsOnPresentation: Bool
    ) -> AnyView
}

extension TrackerFeatureRouting {
    func refreshReports() async {}

    func makeProgressView(
        onOpenBodyMetric: @escaping @MainActor () -> Void,
        onOpenLifestyle: @escaping @MainActor () -> Void,
        onOpenPosture: @escaping @MainActor () -> Void,
        onOpenHealthChecks: @escaping @MainActor () -> Void,
        onOpenBloodwork: @escaping @MainActor () -> Void,
        onOpenProgressPhotos: @escaping @MainActor () -> Void,
        loadsReportsOnPresentation: Bool
    ) -> AnyView {
        _ = loadsReportsOnPresentation
        return makeProgressView(
            onOpenBodyMetric: onOpenBodyMetric,
            onOpenLifestyle: onOpenLifestyle,
            onOpenPosture: onOpenPosture,
            onOpenHealthChecks: onOpenHealthChecks,
            onOpenBloodwork: onOpenBloodwork,
            onOpenProgressPhotos: onOpenProgressPhotos
        )
    }
}
