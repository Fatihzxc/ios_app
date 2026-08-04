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
        .library(name: "CoreModels", targets: ["CoreModels"])
    ],
    targets: [
        .target(
            name: "CoreModels",
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "CoreModelsTests",
            dependencies: ["CoreModels"],
            swiftSettings: strictConcurrency
        )
    ]
)
