import Foundation

enum AppEnvironment: Equatable {
    case uiTesting
    case local(storeURL: URL)
    case cloud(containerIdentifier: String, storeURL: URL)

    enum ConfigurationError: Error, Equatable, Sendable {
        case invalidCloudKitEnabled
        case invalidCloudKitContainerIdentifier
    }

    enum StorePathError: Error, Equatable, Sendable {
        case applicationSupportUnavailable
        case invalidBundleIdentifier
        case directoryCreationFailed
    }

    static func resolve(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) throws -> AppEnvironment {
        try resolve(
            arguments: processInfo.arguments,
            configurationValue: { bundle.object(forInfoDictionaryKey: $0) },
            storeURL: {
                try resolveStoreURL(
                    applicationSupportDirectory: FileManager.default.urls(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask
                    ).first,
                    bundleIdentifier: bundle.bundleIdentifier,
                    createDirectory: { directory in
                        try FileManager.default.createDirectory(
                            at: directory,
                            withIntermediateDirectories: true
                        )
                    }
                )
            }
        )
    }

    static func resolve(
        arguments: [String],
        configurationValue: (String) -> Any?,
        storeURL: () throws -> URL
    ) throws -> AppEnvironment {
        guard !arguments.contains("-ui-testing") else {
            return .uiTesting
        }

        let cloudKitEnabled = try parseCloudKitEnabled(configurationValue("CloudKitEnabled"))
        let resolvedStoreURL = try storeURL()

        guard cloudKitEnabled else {
            return .local(storeURL: resolvedStoreURL)
        }

        guard let identifier = resolvedContainerIdentifier(configurationValue("CloudKitContainerIdentifier")) else {
            throw ConfigurationError.invalidCloudKitContainerIdentifier
        }
        return .cloud(containerIdentifier: identifier, storeURL: resolvedStoreURL)
    }

    static func resolveStoreURL(
        applicationSupportDirectory: URL?,
        bundleIdentifier: String?,
        createDirectory: (URL) throws -> Void
    ) throws -> URL {
        guard let applicationSupportDirectory else {
            throw StorePathError.applicationSupportUnavailable
        }
        guard let bundleIdentifier, !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StorePathError.invalidBundleIdentifier
        }

        let applicationDirectory = applicationSupportDirectory.appendingPathComponent(
            bundleIdentifier,
            isDirectory: true
        )
        do {
            try createDirectory(applicationDirectory)
        } catch {
            throw StorePathError.directoryCreationFailed
        }
        return applicationDirectory.appendingPathComponent("HealthTracking.sqlite")
    }

    private static func parseCloudKitEnabled(_ value: Any?) throws -> Bool {
        guard let value else {
            throw ConfigurationError.invalidCloudKitEnabled
        }
        if type(of: value) == Bool.self, let boolValue = value as? Bool {
            return boolValue
        }
        if type(of: value) == String.self, let stringValue = value as? String {
            switch stringValue {
            case "YES": return true
            case "NO": return false
            default: break
            }
        }
        throw ConfigurationError.invalidCloudKitEnabled
    }

    private static func resolvedContainerIdentifier(_ value: Any?) -> String? {
        guard let value,
              type(of: value) == String.self,
              let identifier = value as? String,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !identifier.contains("$("),
              !identifier.contains("${") else {
            return nil
        }
        return identifier
    }
}
