import SwiftUI

public enum SRGBColorError: Error, Equatable, Sendable {
    case invalidHex
}

public struct SRGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(hex: String) throws {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy({ $0.isHexDigit }),
              let value = UInt64(digits, radix: 16) else {
            throw SRGBColorError.invalidHex
        }

        let includesAlpha = digits.count == 8
        red = Double((value >> (includesAlpha ? 24 : 16)) & 0xFF) / 255.0
        green = Double((value >> (includesAlpha ? 16 : 8)) & 0xFF) / 255.0
        blue = Double((value >> (includesAlpha ? 8 : 0)) & 0xFF) / 255.0
        alpha = includesAlpha ? Double(value & 0xFF) / 255.0 : 1.0
    }

    public var isOpaque: Bool {
        alpha == 1.0
    }

    public var relativeLuminance: Double {
        (0.2126 * linearized(red)) + (0.7152 * linearized(green)) + (0.0722 * linearized(blue))
    }

    public func composited(over background: SRGBColor) -> SRGBColor {
        precondition(background.isOpaque, "A contrast surface must be opaque.")
        guard !isOpaque else { return self }

        return SRGBColor(
            red: (alpha * red) + ((1.0 - alpha) * background.red),
            green: (alpha * green) + ((1.0 - alpha) * background.green),
            blue: (alpha * blue) + ((1.0 - alpha) * background.blue),
            alpha: 1.0
        )
    }

    public func contrastRatio(against other: SRGBColor) -> Double {
        precondition(isOpaque && other.isOpaque, "Composite alpha tokens before contrast measurement.")
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    private init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    private func linearized(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}
