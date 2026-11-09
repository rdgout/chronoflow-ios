// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "ChronoFlowKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "Launch", targets: ["Launch"]),
        .library(name: "Welcome", targets: ["Welcome"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", .upToNextMinor(from: "1.19.0"))
    ],
    targets: [
        .target(name: "SnapshotSupport", path: "Tests/SnapshotSupport", exclude: ["profiles.json"]),
        .target(
            name: "DesignSystem", resources: [.process("Resources")], swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(name: "AppCore", swiftSettings: [.defaultIsolation(nil)]),
        .target(
            name: "Launch",
            dependencies: ["DesignSystem", "AppCore"],
            resources: [.process("Resources")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "Welcome",
            dependencies: ["DesignSystem", "AppCore"],
            resources: [.process("Resources")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"], swiftSettings: [.defaultIsolation(nil)]),
        .testTarget(
            name: "LaunchTests",
            dependencies: [
                "Launch", "SnapshotSupport", .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "WelcomeTests",
            dependencies: ["Welcome"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
