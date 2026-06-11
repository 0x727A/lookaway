// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "lookaway",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LookAway", targets: ["lookaway"])
    ],
    targets: [
        .executableTarget(
            name: "lookaway",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
