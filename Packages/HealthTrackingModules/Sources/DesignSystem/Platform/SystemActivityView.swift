import Foundation
import SwiftUI
import UIKit

@MainActor
public struct SystemActivityView: UIViewControllerRepresentable {
    private let activityItemURL: URL?
    private let additionalActivityItemURLs: [URL]
    private let artifactID: UUID
    private let accessibilityIdentifier: String
    private let onCompletion: @MainActor (UUID, Bool, Error?) -> Void
    private let onPresentationFailure: @MainActor (UUID) -> Void

    public init(
        activityItemURL: URL,
        artifactID: UUID,
        accessibilityIdentifier: String,
        onCompletion: @escaping @MainActor (UUID, Bool, Error?) -> Void,
        onPresentationFailure: @escaping @MainActor (UUID) -> Void
    ) {
        self.activityItemURL = activityItemURL
        additionalActivityItemURLs = []
        self.artifactID = artifactID
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onCompletion = onCompletion
        self.onPresentationFailure = onPresentationFailure
    }

    public init(
        activityItemURLs: [URL],
        artifactID: UUID,
        accessibilityIdentifier: String,
        onCompletion: @escaping @MainActor (UUID, Bool, Error?) -> Void,
        onPresentationFailure: @escaping @MainActor (UUID) -> Void
    ) {
        activityItemURL = activityItemURLs.first
        additionalActivityItemURLs = Array(activityItemURLs.dropFirst())
        self.artifactID = artifactID
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onCompletion = onCompletion
        self.onPresentationFailure = onPresentationFailure
    }

    var activityItemURLs: [URL] {
        guard let activityItemURL else { return [] }
        return [activityItemURL] + additionalActivityItemURLs
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            artifactID: artifactID,
            onCompletion: onCompletion,
            onPresentationFailure: onPresentationFailure
        )
    }

    public func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        let controller: UIActivityViewController
        if let activityItemURL, additionalActivityItemURLs.isEmpty {
            controller = UIActivityViewController(
                activityItems: [activityItemURL],
                applicationActivities: nil
            )
        } else {
            controller = UIActivityViewController(
                activityItems: activityItemURLs,
                applicationActivities: nil
            )
        }
        controller.view.accessibilityIdentifier = accessibilityIdentifier
        controller.completionWithItemsHandler = {
            [weak coordinator = context.coordinator] _, completed, _, error in
            coordinator?.complete(completed: completed, error: error)
        }
        if activityItemURLs.isEmpty || activityItemURLs.contains(where: {
            !$0.isFileURL || !FileManager.default.fileExists(atPath: $0.path)
        }) {
            context.coordinator.presentationFailed()
        }
        return controller
    }

    public func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
        _ = uiViewController
        _ = context
    }

    @MainActor
    public final class Coordinator {
        private var didReachTerminal = false
        private let artifactID: UUID
        private let onCompletion: @MainActor (UUID, Bool, Error?) -> Void
        private let onPresentationFailure: @MainActor (UUID) -> Void

        init(
            artifactID: UUID,
            onCompletion: @escaping @MainActor (UUID, Bool, Error?) -> Void,
            onPresentationFailure: @escaping @MainActor (UUID) -> Void
        ) {
            self.artifactID = artifactID
            self.onCompletion = onCompletion
            self.onPresentationFailure = onPresentationFailure
        }

        func complete(completed: Bool, error: Error?) {
            guard !didReachTerminal else { return }
            didReachTerminal = true
            onCompletion(artifactID, completed, error)
        }

        func presentationFailed() {
            guard !didReachTerminal else { return }
            didReachTerminal = true
            onPresentationFailure(artifactID)
        }
    }
}
