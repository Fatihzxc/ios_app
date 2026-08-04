import SwiftUI

public enum AppTypography {
    public static let directive = Font.largeTitle.bold()
    public static let titleLarge = Font.title.weight(.semibold)
    public static let titleMedium = Font.title3.weight(.semibold)
    public static let body = Font.body
    public static let label = Font.subheadline.weight(.medium)
    public static let caption = Font.footnote
    public static let micro = Font.caption2.weight(.semibold)
    public static let numericHero = Font.largeTitle.bold().monospacedDigit()
    public static let numericRow = Font.body.weight(.medium).monospacedDigit()
}
