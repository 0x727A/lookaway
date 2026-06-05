// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "my_lookaway",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LookAway", targets: ["my_lookaway"])
    ],
    targets: [
        .executableTarget(
            name: "my_lookaway",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
