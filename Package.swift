// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "my_lookaway",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "my_lookaway", targets: ["my_lookaway"])
    ],
    targets: [
        .executableTarget(
            name: "my_lookaway",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
