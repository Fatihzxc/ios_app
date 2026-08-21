import SwiftUI

public enum StatusPillStyle: Sendable {
    case success
    case warning
    case danger
    case info

    fileprivate var colorRole: AppColorRole {
        switch self {
        case .success: .stateSuccess
        case .warning: .stateWarning
        case .danger: .stateDanger
        case .info: .stateInfo
        }
    }
}

public struct StatusPill: View {
    @Environment(\.colorScheme) private var colorScheme

    private let text: String
    private let systemImage: String?
    private let style: StatusPillStyle

    public init(text: String, systemImage: String? = nil, style: StatusPillStyle) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    public var body: some View {
        label
            .font(AppTypography.micro)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(AppColors.color(style.colorRole, scheme: colorScheme))
            .padding(.horizontal, AppSpacing.compact)
            .padding(.vertical, AppSpacing.small)
            .background(AppColors.color(style.colorRole, scheme: colorScheme).opacity(0.14))
            .clipShape(Capsule())
            .accessibilityLabel(text)
    }

    private var label: Text {
        guard let systemImage else { return Text(text) }
        return Text(Image(systemName: systemImage))
            + Text(verbatim: String(" "))
            + Text(text)
    }
}
