import Foundation
import SwiftUI
import UIKit

@MainActor
public struct PhotoThumbnailView: View {
    private let data: Data

    public init(data: Data) {
        self.data = data
    }

    public var body: some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 260)
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}
