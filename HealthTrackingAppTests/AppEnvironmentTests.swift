import Foundation
@testable import HealthTrackingApp
import XCTest

final class AppEnvironmentTests: XCTestCase {
    // Mutation caught: changing the app-facing wrapper away from ProcessInfo and
    // Bundle would disconnect real launch configuration from the tested seams.
    func testWrapperRetainsProcessInfoAndBundleSignature() {
        let resolve: (ProcessInfo, Bundle) throws -> AppEnvironment = AppEnvironment.resolve(processInfo:bundle:)
        withExtendedLifetime(resolve) {}
    }

    // Mutation caught: dropping Sendable from stable configuration or store errors
    // would make app-environment failures unsafe to carry across concurrency domains.
    func testEnvironmentErrorsRemainEquatableAndSendable() {
        requireSendable(AppEnvironment.ConfigurationError.self)
        requireSendable(AppEnvironment.StorePathError.self)

        XCTAssertEqual(AppEnvironment.ConfigurationError.invalidCloudKitEnabled, .invalidCloudKitEnabled)
        XCTAssertEqual(AppEnvironment.StorePathError.applicationSupportUnavailable, .applicationSupportUnavailable)
    }

    // Mutation caught: consulting Info.plist or the persistent-store resolver before
    // recognizing the exact UI-test launch argument would make automation stateful.
    func testExactUITestingArgumentWinsBeforeConfigurationOrStoreLookup() throws {
        let malformedValues: [Any?] = [nil, "MAYBE", NSNumber(value: 1)]

        for value in malformedValues {
            var configurationReads = 0
            var storeResolutions = 0

            let environment = try AppEnvironment.resolve(
                arguments: ["-ui-testing"],
                configurationValue: { _ in
                    configurationReads += 1
                    return value
                },
                storeURL: {
                    storeResolutions += 1
                    return URL(fileURLWithPath: "/unused.sqlite")
                }
            )

            XCTAssertEqual(environment, .uiTesting)
            XCTAssertEqual(configurationReads, 0)
            XCTAssertEqual(storeResolutions, 0)
        }
    }

    // Mutation caught: substring matching launch arguments would accidentally enable
    // UI-test mode in normal launches that merely contain a lookalike value.
    func testUITestingLookalikesDoNotActivateUITesting() throws {
        let lookalikes = ["--ui-testing", "-ui-testing=true", "prefix-ui-testing", "-UI-testing", "-ui-testing "]
        let expectedStoreURL = URL(fileURLWithPath: "/stores/local.sqlite")

        for argument in lookalikes {
            var storeResolutions = 0
            let environment = try AppEnvironment.resolve(
                arguments: [argument],
                configurationValue: { key in key == "CloudKitEnabled" ? false : nil },
                storeURL: {
                    storeResolutions += 1
                    return expectedStoreURL
                }
            )

            XCTAssertEqual(environment, .local(storeURL: expectedStoreURL), argument)
            XCTAssertEqual(storeResolutions, 1, argument)
        }
    }

    // Mutation caught: permissive coercion of plist values would turn malformed cloud
    // configuration into an unintended storage mode.
    func testCloudKitEnabledAcceptsOnlyBooleanOrExactYESAndNOStrings() throws {
        let storeURL = URL(fileURLWithPath: "/stores/app.sqlite")
        let acceptedValues: [(Any, AppEnvironment)] = [
            (true, .cloud(containerIdentifier: "iCloud.example.health", storeURL: storeURL)),
            (false, .local(storeURL: storeURL)),
            ("YES", .cloud(containerIdentifier: "iCloud.example.health", storeURL: storeURL)),
            ("NO", .local(storeURL: storeURL)),
        ]

        for (value, expected) in acceptedValues {
            var storeResolutions = 0
            let environment = try AppEnvironment.resolve(
                arguments: [],
                configurationValue: { key in
                    key == "CloudKitEnabled" ? value : "iCloud.example.health"
                },
                storeURL: {
                    storeResolutions += 1
                    return storeURL
                }
            )

            XCTAssertEqual(environment, expected)
            XCTAssertEqual(storeResolutions, 1)
        }
    }

    // Mutation caught: NSNumber bridging, case folding, trimming, or substitution
    // acceptance would silently reinterpret an invalid CloudKitEnabled setting.
    func testInvalidCloudKitEnabledValuesHaveOneStableTypedError() {
        let invalidValues: [Any?] = [
            nil,
            0,
            NSNumber(value: 0),
            NSNumber(value: true),
            "yes",
            "no",
            " YES",
            "NO ",
            "$(CLOUDKIT_ENABLED)",
            "enabled",
            ["YES"],
        ]

        for value in invalidValues {
            XCTAssertThrowsError(
                try AppEnvironment.resolve(
                    arguments: [],
                    configurationValue: { _ in value },
                    storeURL: { URL(fileURLWithPath: "/unused.sqlite") }
                )
            ) { error in
                XCTAssertEqual(error as? AppEnvironment.ConfigurationError, .invalidCloudKitEnabled)
            }
        }
    }

    // Mutation caught: eagerly reading the container identifier while CloudKit is
    // disabled makes a local launch depend on unrelated, invalid plist data.
    func testLocalCloudKitSettingNeverInspectsIdentifierAndResolvesStoreOnce() throws {
        let invalidIdentifierValues: [Any?] = [nil, "", "   ", 17, "$(ICLOUD_CONTAINER_IDENTIFIER)"]
        let expectedStoreURL = URL(fileURLWithPath: "/stores/local.sqlite")

        for identifier in invalidIdentifierValues {
            var identifierReads = 0
            var storeResolutions = 0
            let environment = try AppEnvironment.resolve(
                arguments: [],
                configurationValue: { key in
                    if key == "CloudKitEnabled" { return false }
                    identifierReads += 1
                    return identifier
                },
                storeURL: {
                    storeResolutions += 1
                    return expectedStoreURL
                }
            )

            XCTAssertEqual(environment, .local(storeURL: expectedStoreURL))
            XCTAssertEqual(identifierReads, 0)
            XCTAssertEqual(storeResolutions, 1)
        }
    }

    // Mutation caught: accepting an empty, non-string, or unresolved container ID
    // would start CloudKit with an unusable identifier.
    func testCloudKitRequiresPresentNonblankResolvedStringIdentifier() {
        let invalidIdentifiers: [Any?] = [nil, "", "   ", 17, "$(ICLOUD_CONTAINER_IDENTIFIER)"]

        for identifier in invalidIdentifiers {
            XCTAssertThrowsError(
                try AppEnvironment.resolve(
                    arguments: [],
                    configurationValue: { key in
                        key == "CloudKitEnabled" ? true : identifier
                    },
                    storeURL: { URL(fileURLWithPath: "/unused.sqlite") }
                )
            ) { error in
                XCTAssertEqual(error as? AppEnvironment.ConfigurationError, .invalidCloudKitContainerIdentifier)
            }
        }
    }

    // Mutation caught: deriving path inputs internally would make the store location
    // nondeterministic and would bypass the app-support and bundle-ID failure paths.
    func testStoreURLUsesOnlyInjectedInputsWithDeterministicDirectoryAndFilename() throws {
        let baseURL = URL(fileURLWithPath: "/test/Application Support", isDirectory: true)
        var createdDirectory: URL?

        let storeURL = try AppEnvironment.resolveStoreURL(
            applicationSupportDirectory: baseURL,
            bundleIdentifier: "com.example.healthtracking",
            createDirectory: { createdDirectory = $0 }
        )

        let expectedDirectory = baseURL.appendingPathComponent("com.example.healthtracking", isDirectory: true)
        XCTAssertEqual(createdDirectory, expectedDirectory)
        XCTAssertEqual(storeURL, expectedDirectory.appendingPathComponent("HealthTracking.sqlite"))
        XCTAssertEqual(storeURL.lastPathComponent, "HealthTracking.sqlite")
    }

    // Mutation caught: falling back to the real filesystem or leaking underlying
    // errors would hide deterministic failures in persistent-store setup.
    func testStoreURLReportsUnavailableInputsAndDirectoryCreationFailure() {
        let baseURL = URL(fileURLWithPath: "/test/Application Support", isDirectory: true)

        XCTAssertThrowsError(
            try AppEnvironment.resolveStoreURL(
                applicationSupportDirectory: nil,
                bundleIdentifier: "com.example.healthtracking",
                createDirectory: { _ in }
            )
        ) { error in
            XCTAssertEqual(error as? AppEnvironment.StorePathError, .applicationSupportUnavailable)
        }

        for bundleIdentifier in [nil, "", "   "] {
            XCTAssertThrowsError(
                try AppEnvironment.resolveStoreURL(
                    applicationSupportDirectory: baseURL,
                    bundleIdentifier: bundleIdentifier,
                    createDirectory: { _ in }
                )
            ) { error in
                XCTAssertEqual(error as? AppEnvironment.StorePathError, .invalidBundleIdentifier)
            }
        }

        XCTAssertThrowsError(
            try AppEnvironment.resolveStoreURL(
                applicationSupportDirectory: baseURL,
                bundleIdentifier: "com.example.healthtracking",
                createDirectory: { _ in throw StoreSetupFailure() }
            )
        ) { error in
            XCTAssertEqual(error as? AppEnvironment.StorePathError, .directoryCreationFailed)
        }
    }

    // This closure is intentionally never invoked: type checking the no-argument call
    // protects the wrapper's required ProcessInfo and Bundle default arguments.
    private static let resolveWithDefaultArgumentsIsTypeChecked: () -> Void = {
        _ = try? AppEnvironment.resolve()
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}

    private struct StoreSetupFailure: Error {}
}
