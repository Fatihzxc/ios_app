import SwiftUI

@MainActor
protocol TrackerFeatureRouting: AnyObject {
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
        onOpenBloodwork: @escaping @MainActor () -> Void,
        onOpenProgressPhotos: @escaping @MainActor () -> Void
    ) -> AnyView
}
