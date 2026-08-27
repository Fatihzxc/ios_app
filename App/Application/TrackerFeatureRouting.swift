import SwiftUI

@MainActor
protocol TrackerFeatureRouting: AnyObject {
    func makeBodyMetricEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView

    func makeLifestyleEntryView(
        onClose: @escaping @MainActor () -> Void
    ) -> AnyView

    func makeProgressView() -> AnyView
}
