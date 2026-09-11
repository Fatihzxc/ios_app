import Foundation

enum ReportsLocalization {
    static func string(
        _ key: String.LocalizationValue,
        locale: Locale
    ) -> String {
        let resource = LocalizedStringResource(
            key,
            table: nil,
            locale: locale,
            bundle: .atURL(Bundle.module.bundleURL)
        )
        return String(localized: resource)
    }

    static func format(
        _ key: String.LocalizationValue,
        locale: Locale,
        arguments: [CVarArg]
    ) -> String {
        String(
            format: string(key, locale: locale),
            locale: locale,
            arguments: arguments
        )
    }
}
