import SwiftUI

public enum QuickEntryActionLayout: Equatable, Sendable {
    case horizontal
    case vertical
}

public enum QuickEntryFormContract {
    public static let minimumActionHeight: CGFloat = 52
    public static let keyboardDismissAccessibilityIdentifier = "quick-entry.keyboard.dismiss"
    public static let keyboardDismissLocalizationKey = "designSystem.quick-entry.keyboard.dismiss"

    public static func actionLayout(isAccessibilitySize: Bool) -> QuickEntryActionLayout {
        isAccessibilitySize ? .vertical : .horizontal
    }
}

public struct QuickEntryFormScaffold<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @FocusState private var isInputFocused: Bool

    private let title: String
    private let primaryActionTitle: String
    private let primaryActionAccessibilityLabel: String
    private let primaryActionAccessibilityIdentifier: String?
    private let isPrimaryActionLoading: Bool
    private let isPrimaryActionEnabled: Bool
    private let secondaryActionTitle: String?
    private let secondaryActionAccessibilityLabel: String?
    private let secondaryActionAccessibilityIdentifier: String?
    private let primaryAction: () -> Void
    private let secondaryAction: (() -> Void)?
    private let content: (FocusState<Bool>.Binding) -> Content

    public init(
        title: String,
        primaryActionTitle: String,
        primaryActionAccessibilityLabel: String,
        primaryActionAccessibilityIdentifier: String? = nil,
        isPrimaryActionLoading: Bool = false,
        isPrimaryActionEnabled: Bool = true,
        secondaryActionTitle: String? = nil,
        secondaryActionAccessibilityLabel: String? = nil,
        secondaryActionAccessibilityIdentifier: String? = nil,
        primaryAction: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (FocusState<Bool>.Binding) -> Content
    ) {
        self.title = title
        self.primaryActionTitle = primaryActionTitle
        self.primaryActionAccessibilityLabel = primaryActionAccessibilityLabel
        self.primaryActionAccessibilityIdentifier = primaryActionAccessibilityIdentifier
        self.isPrimaryActionLoading = isPrimaryActionLoading
        self.isPrimaryActionEnabled = isPrimaryActionEnabled
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryActionAccessibilityLabel = secondaryActionAccessibilityLabel
        self.secondaryActionAccessibilityIdentifier = secondaryActionAccessibilityIdentifier
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            Text(title)
                .font(AppTypography.titleLarge)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                content($isInputFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            actionBar
                .transition(actionTransition)
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.comfortable)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(
                    String(
                        localized: "designSystem.quick-entry.keyboard.dismiss",
                        bundle: .module
                    )
                ) {
                    isInputFocused = false
                }
                .accessibilityIdentifier(
                    QuickEntryFormContract.keyboardDismissAccessibilityIdentifier
                )
            }
        }
        .animation(
            AppMotion.animation(reduceMotion: accessibilityReduceMotion),
            value: actionLayout
        )
    }

    @ViewBuilder
    private var actionBar: some View {
        switch actionLayout {
        case .horizontal:
            HStack(spacing: AppSpacing.standard) {
                secondaryButton
                primaryButton
            }
        case .vertical:
            VStack(spacing: AppSpacing.standard) {
                primaryButton
                secondaryButton
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        let button = PrimaryActionButton(
            title: primaryActionTitle,
            accessibilityLabel: primaryActionAccessibilityLabel,
            isLoading: isPrimaryActionLoading,
            isEnabled: isPrimaryActionEnabled,
            minimumHeight: QuickEntryFormContract.minimumActionHeight,
            action: primaryAction
        )
        if let primaryActionAccessibilityIdentifier {
            button.accessibilityIdentifier(primaryActionAccessibilityIdentifier)
        } else {
            button
        }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        if let secondaryActionTitle,
           let secondaryActionAccessibilityLabel,
           let secondaryAction {
            let button = Button(action: secondaryAction) {
                Text(secondaryActionTitle)
                    .font(AppTypography.label)
                    .multilineTextAlignment(.center)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: QuickEntryFormContract.minimumActionHeight
                    )
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(secondaryActionAccessibilityLabel)
            if let secondaryActionAccessibilityIdentifier {
                button.accessibilityIdentifier(secondaryActionAccessibilityIdentifier)
            } else {
                button
            }
        }
    }

    private var actionLayout: QuickEntryActionLayout {
        QuickEntryFormContract.actionLayout(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var actionTransition: AnyTransition {
        switch AppMotion.transition(reduceMotion: accessibilityReduceMotion) {
        case .opacity:
            .opacity
        case .standard:
            .opacity.combined(with: .scale(scale: 0.98))
        }
    }
}
