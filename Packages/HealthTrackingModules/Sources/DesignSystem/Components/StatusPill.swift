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
        HStack(spacing: AppSpacing.small) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(AppTypography.micro)
        .foregroundStyle(AppColors.color(style.colorRole, scheme: colorScheme))
        .padding(.horizontal, AppSpacing.compact)
        .padding(.vertical, AppSpacing.small)
        .background(AppColors.color(style.colorRole, scheme: colorScheme).opacity(0.14))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}
