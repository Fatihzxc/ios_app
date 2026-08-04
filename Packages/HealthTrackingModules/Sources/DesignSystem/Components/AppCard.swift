import SwiftUI

public struct AppCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(AppSpacing.comfortable)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.color(.backgroundRaised, scheme: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous))
    }
}
