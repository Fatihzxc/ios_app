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
        .library(name: "PersistenceKit", targets: ["PersistenceKit"])
    ],
    targets: [
        .target(
            name: "CoreModels",
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "TrainingKit",
            dependencies: ["CoreModels"],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "PersistenceKit",
            dependencies: ["CoreModels", "TrainingKit"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "CoreModelsTests",
            dependencies: ["CoreModels"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "PersistenceKitTests",
            dependencies: ["CoreModels", "TrainingKit", "PersistenceKit"],
            swiftSettings: strictConcurrency
        )
    ]
)
