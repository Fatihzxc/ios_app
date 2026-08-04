import XCTest
@testable import DesignSystem

@MainActor
final class ColorContrastTests: XCTestCase {
    func testApprovedLightPaletteUsesExactSRGBValues() {
        assertHex(AppColors.value(.backgroundBase, scheme: .light), equals: "#FAF9F7")
        assertHex(AppColors.value(.backgroundRaised, scheme: .light), equals: "#FFFFFF")
        assertHex(AppColors.value(.backgroundSunken, scheme: .light), equals: "#EFEDE9")
        assertHex(AppColors.value(.inkPrimary, scheme: .light), equals: "#14151A")
        assertHex(AppColors.value(.inkSecondary, scheme: .light), equals: "#4A4E57")
        assertHex(AppColors.value(.inkTertiary, scheme: .light), equals: "#626873")
        assertHex(AppColors.value(.accentAction, scheme: .light), equals: "#9A3412")
        assertHex(AppColors.value(.accentOnAction, scheme: .light), equals: "#FFFFFF")
        assertHex(AppColors.value(.stateSuccess, scheme: .light), equals: "#1E6B45")
        assertHex(AppColors.value(.stateWarning, scheme: .light), equals: "#8A5A00")
        assertHex(AppColors.value(.stateDanger, scheme: .light), equals: "#B3261E")
        assertHex(AppColors.value(.stateInfo, scheme: .light), equals: "#2A5AA8")
        assertHex(AppColors.value(.borderHairline, scheme: .light), equals: "#00000014")
        assertHex(AppColors.value(.borderStrong, scheme: .light), equals: "#00000070")
    }

    func testApprovedDarkPaletteUsesExactSRGBValues() {
        assertHex(AppColors.value(.backgroundBase, scheme: .dark), equals: "#0E0F12")
        assertHex(AppColors.value(.backgroundRaised, scheme: .dark), equals: "#17191E")
        assertHex(AppColors.value(.backgroundSunken, scheme: .dark), equals: "#08090B")
        assertHex(AppColors.value(.inkPrimary, scheme: .dark), equals: "#F2F3F5")
        assertHex(AppColors.value(.inkSecondary, scheme: .dark), equals: "#A8ADB7")
        assertHex(AppColors.value(.inkTertiary, scheme: .dark), equals: "#949AA5")
        assertHex(AppColors.value(.accentAction, scheme: .dark), equals: "#FF9A5C")
        assertHex(AppColors.value(.accentOnAction, scheme: .dark), equals: "#1A0E06")
        assertHex(AppColors.value(.stateSuccess, scheme: .dark), equals: "#6EDBA5")
        assertHex(AppColors.value(.stateWarning, scheme: .dark), equals: "#F5C462")
        assertHex(AppColors.value(.stateDanger, scheme: .dark), equals: "#FF8A80")
        assertHex(AppColors.value(.stateInfo, scheme: .dark), equals: "#8CB6FF")
        assertHex(AppColors.value(.borderHairline, scheme: .dark), equals: "#FFFFFF1A")
        assertHex(AppColors.value(.borderStrong, scheme: .dark), equals: "#FFFFFF5C")
    }

    func testNormalTextPairsMeetWCAGAAInBothSchemes() {
        for scheme in ColorSchemeVariant.allCases {
            assertContrast(.inkPrimary, .backgroundBase, scheme: scheme, minimum: 4.5)
            assertContrast(.inkPrimary, .backgroundRaised, scheme: scheme, minimum: 4.5)
            assertContrast(.inkSecondary, .backgroundBase, scheme: scheme, minimum: 4.5)
            assertContrast(.inkTertiary, .backgroundBase, scheme: scheme, minimum: 4.5)
            assertContrast(.accentOnAction, .accentAction, scheme: scheme, minimum: 4.5)
        }
    }

    func testStateIconsMeetUIContrastInBothSchemes() {
        for scheme in ColorSchemeVariant.allCases {
            for role in [AppColorRole.stateSuccess, .stateWarning, .stateDanger, .stateInfo] {
                assertContrast(role, .backgroundBase, scheme: scheme, minimum: 3.0)
            }
        }
    }

    func testRetryForegroundUsesActionRoleAndMeetsNormalTextContrastOnEverySurface() {
        let retryForeground = FeatureStateView.retryForegroundRole
        XCTAssertEqual(retryForeground, .accentAction)

        for scheme in ColorSchemeVariant.allCases {
            let foreground = AppColors.value(retryForeground, scheme: scheme)
            for surfaceRole in [AppColorRole.backgroundBase, .backgroundRaised, .backgroundSunken] {
                let surface = AppColors.value(surfaceRole, scheme: scheme)
                let renderedForeground = foreground.composited(over: surface)
                let ratio = renderedForeground.contrastRatio(against: surface)
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    4.5,
                    "Retry foreground \(retryForeground) on \(surfaceRole) in \(scheme) was \(ratio)."
                )
            }
        }
    }

    func testStrongBorderMeetsUIContrastOnEveryIntendedSurface() {
        for scheme in ColorSchemeVariant.allCases {
            for surface in [AppColorRole.backgroundBase, .backgroundRaised, .backgroundSunken] {
                assertContrast(.borderStrong, surface, scheme: scheme, minimum: 3.0)
            }
        }
    }

    func testContrastCompositingUsesEncodedSRGBSourceOver() {
        let result = TestSRGBColor(hex: "#00000080").composited(over: TestSRGBColor(hex: "#FFFFFF"))
        let expected = 127.0 / 255.0

        XCTAssertEqual(result.red, expected, accuracy: 0.000_001)
        XCTAssertEqual(result.green, expected, accuracy: 0.000_001)
        XCTAssertEqual(result.blue, expected, accuracy: 0.000_001)
        XCTAssertEqual(result.alpha, 1.0, accuracy: 0.000_001)
    }

    private func assertHex(_ color: SRGBColor, equals expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectedColor = TestSRGBColor(hex: expected)
        XCTAssertEqual(color.red, expectedColor.red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(color.green, expectedColor.green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(color.blue, expectedColor.blue, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(color.alpha, expectedColor.alpha, accuracy: 0.000_001, file: file, line: line)
    }

    private func assertContrast(_ foreground: AppColorRole, _ background: AppColorRole, scheme: ColorSchemeVariant, minimum: Double, file: StaticString = #filePath, line: UInt = #line) {
        let surface = TestSRGBColor(AppColors.value(background, scheme: scheme))
        let renderedForeground = TestSRGBColor(AppColors.value(foreground, scheme: scheme)).composited(over: surface)
        let ratio = renderedForeground.contrastRatio(against: surface)
        XCTAssertGreaterThanOrEqual(ratio, minimum, "\(foreground) on \(background) in \(scheme) was \(ratio)", file: file, line: line)
    }
}

private struct TestSRGBColor {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(hex: String) {
        let digits = hex.drop(while: { $0 == "#" })
        precondition(digits.count == 6 || digits.count == 8)
        let value = UInt64(digits, radix: 16)!
        red = Double((value >> (digits.count == 8 ? 24 : 16)) & 0xFF) / 255.0
        green = Double((value >> (digits.count == 8 ? 16 : 8)) & 0xFF) / 255.0
        blue = Double((value >> (digits.count == 8 ? 8 : 0)) & 0xFF) / 255.0
        alpha = digits.count == 8 ? Double(value & 0xFF) / 255.0 : 1.0
    }

    init(_ color: SRGBColor) {
        red = color.red
        green = color.green
        blue = color.blue
        alpha = color.alpha
    }

    func composited(over background: TestSRGBColor) -> TestSRGBColor {
        precondition(background.alpha == 1.0, "A contrast surface must be opaque.")
        guard alpha < 1.0 else { return self }

        return TestSRGBColor(
            red: (alpha * red) + ((1.0 - alpha) * background.red),
            green: (alpha * green) + ((1.0 - alpha) * background.green),
            blue: (alpha * blue) + ((1.0 - alpha) * background.blue),
            alpha: 1.0
        )
    }

    func contrastRatio(against other: TestSRGBColor) -> Double {
        precondition(alpha == 1.0 && other.alpha == 1.0, "Composite alpha tokens before contrast measurement.")
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: Double {
        (0.2126 * linearized(red)) + (0.7152 * linearized(green)) + (0.0722 * linearized(blue))
    }

    private func linearized(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    private init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
