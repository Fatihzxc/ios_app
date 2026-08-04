import SwiftUI

public enum ColorSchemeVariant: CaseIterable, Sendable {
    case light
    case dark
}

public enum AppColorRole: CaseIterable, Sendable {
    case backgroundBase
    case backgroundRaised
    case backgroundSunken
    case inkPrimary
    case inkSecondary
    case inkTertiary
    case accentAction
    case accentOnAction
    case stateSuccess
    case stateWarning
    case stateDanger
    case stateInfo
    case borderHairline
    case borderStrong
}

public enum AppColors {
    public static func value(_ role: AppColorRole, scheme: ColorSchemeVariant) -> SRGBColor {
        switch (role, scheme) {
        case (.backgroundBase, .light): token("#FAF9F7")
        case (.backgroundRaised, .light): token("#FFFFFF")
        case (.backgroundSunken, .light): token("#EFEDE9")
        case (.inkPrimary, .light): token("#14151A")
        case (.inkSecondary, .light): token("#4A4E57")
        case (.inkTertiary, .light): token("#626873")
        case (.accentAction, .light): token("#9A3412")
        case (.accentOnAction, .light): token("#FFFFFF")
        case (.stateSuccess, .light): token("#1E6B45")
        case (.stateWarning, .light): token("#8A5A00")
        case (.stateDanger, .light): token("#B3261E")
        case (.stateInfo, .light): token("#2A5AA8")
        case (.borderHairline, .light): token("#00000014")
        case (.borderStrong, .light): token("#00000070")
        case (.backgroundBase, .dark): token("#0E0F12")
        case (.backgroundRaised, .dark): token("#17191E")
        case (.backgroundSunken, .dark): token("#08090B")
        case (.inkPrimary, .dark): token("#F2F3F5")
        case (.inkSecondary, .dark): token("#A8ADB7")
        case (.inkTertiary, .dark): token("#949AA5")
        case (.accentAction, .dark): token("#FF9A5C")
        case (.accentOnAction, .dark): token("#1A0E06")
        case (.stateSuccess, .dark): token("#6EDBA5")
        case (.stateWarning, .dark): token("#F5C462")
        case (.stateDanger, .dark): token("#FF8A80")
        case (.stateInfo, .dark): token("#8CB6FF")
        case (.borderHairline, .dark): token("#FFFFFF1A")
        case (.borderStrong, .dark): token("#FFFFFF5C")
        }
    }

    public static func color(_ role: AppColorRole, scheme: ColorScheme) -> Color {
        value(role, scheme: scheme == .dark ? .dark : .light).swiftUIColor
    }

    private static func token(_ hex: String) -> SRGBColor {
        guard let color = try? SRGBColor(hex: hex) else {
            preconditionFailure("The DesignSystem palette contains an invalid token.")
        }
        return color
    }
}
