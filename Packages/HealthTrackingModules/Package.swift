// swift-tools-version: 5.9
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency")
]

let package = Package(
    name: "HealthTrackingModules",
    defaultLocalization: "tr",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CoreModels", targets: ["CoreModels"]),
        .library(name: "TrainingKit", targets: ["TrainingKit"]),
        .library(name: "GuidanceKit", targets: ["GuidanceKit"]),
        .library(name: "PersistenceKit", targets: ["PersistenceKit"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "NutritionKit", targets: ["NutritionKit"]),
        .library(name: "HealthSafetyKit", targets: ["HealthSafetyKit"]),
        .library(name: "MetricsKit", targets: ["MetricsKit"]),
        .library(name: "SleepMoodKit", targets: ["SleepMoodKit"]),
        .library(name: "ReportsKit", targets: ["ReportsKit"]),
        .library(name: "SettingsKit", targets: ["SettingsKit"])
    ],
    targets: [
        .target(
            name: "CoreModels",
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "TrainingKit",
            dependencies: ["CoreModels", "DesignSystem", "GuidanceKit"],
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "GuidanceKit",
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "PersistenceKit",
            dependencies: ["CoreModels", "GuidanceKit", "MetricsKit", "NutritionKit", "SleepMoodKit", "TrainingKit"],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "NutritionKit",
            dependencies: ["CoreModels", "DesignSystem"],
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "HealthSafetyKit",
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "MetricsKit",
            dependencies: ["CoreModels", "DesignSystem", "HealthSafetyKit"],
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "SleepMoodKit",
            dependencies: ["CoreModels", "DesignSystem"],
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "ReportsKit",
            dependencies: ["DesignSystem"],
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "SettingsKit",
            dependencies: ["DesignSystem", "TrainingKit"],
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "CoreModelsTests",
            dependencies: ["CoreModels"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "GuidanceKitTests",
            dependencies: ["GuidanceKit"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "PersistenceKitTests",
            dependencies: ["CoreModels", "MetricsKit", "NutritionKit", "SleepMoodKit", "TrainingKit", "PersistenceKit"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "TrainingKitTests",
            dependencies: ["CoreModels", "TrainingKit"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "NutritionKitTests",
            dependencies: ["CoreModels", "NutritionKit"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "HealthSafetyKitTests",
            dependencies: ["HealthSafetyKit"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "MetricsKitTests",
            dependencies: ["CoreModels", "HealthSafetyKit", "MetricsKit"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "SleepMoodKitTests",
            dependencies: ["CoreModels", "SleepMoodKit"],
            swiftSettings: strictConcurrency
        )
    ]
)
