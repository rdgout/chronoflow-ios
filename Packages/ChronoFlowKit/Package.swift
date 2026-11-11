// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "ChronoFlowKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "LocalStore", targets: ["LocalStore"]),
        .library(name: "DataAccess", targets: ["DataAccess"]),
        .library(name: "Sync", targets: ["Sync"]),
        .library(name: "PlanUI", targets: ["PlanUI"]),
        .library(name: "Settings", targets: ["Settings"]),
        .library(name: "Reminders", targets: ["Reminders"]),
        .library(name: "PlanCore", targets: ["PlanCore"]),
        .library(name: "TripWizard", targets: ["TripWizard"]),
        .library(name: "TripWizardUI", targets: ["TripWizardUI"]),
        .library(name: "Launch", targets: ["Launch"]),
        .library(name: "Welcome", targets: ["Welcome"]),
        .library(name: "Auth", targets: ["Auth"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", .upToNextMinor(from: "1.19.0")),
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.8.0"),
    ],
    targets: [
        .target(
            name: "SnapshotSupport", dependencies: ["AppCore"], path: "Tests/SnapshotSupport",
            exclude: ["profiles.json"]),
        .target(
            name: "DesignSystem", resources: [.process("Resources")], swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "PlanCore", dependencies: ["AppCore"], resources: [.process("Resources")],
            swiftSettings: [.defaultIsolation(nil)]),
        .testTarget(
            name: "PlanCoreTests", dependencies: ["PlanCore", "SnapshotSupport"], resources: [.copy("Fixtures")],
            swiftSettings: [.defaultIsolation(nil)]),
        .target(
            name: "PlanUI", dependencies: ["PlanCore", "LocalStore", "Sync", "DesignSystem"],
            resources: [.process("Resources")], swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "PlanUITests", dependencies: ["PlanUI", "DataAccess", "SnapshotSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.defaultIsolation(nil)]),
        .target(
            name: "Settings",
            dependencies: ["AppCore", "LocalStore", "Sync", "PlanCore", "PlanUI", "DesignSystem", "Reminders"],
            resources: [.process("Resources")], swiftSettings: [.defaultIsolation(nil)]),
        .testTarget(
            name: "SettingsTests", dependencies: ["Settings", "DataAccess", "TripWizard"],
            swiftSettings: [.defaultIsolation(nil)]),
        .target(
            name: "Reminders",
            dependencies: ["AppCore", "LocalStore", "PlanCore", .product(name: "GRDB", package: "GRDB.swift")],
            resources: [.process("Resources")], swiftSettings: [.defaultIsolation(nil)]),
        .testTarget(
            name: "RemindersTests", dependencies: ["Reminders", "DataAccess"], resources: [.copy("Fixtures")],
            swiftSettings: [.defaultIsolation(nil)]),
        .target(name: "AppCore", swiftSettings: [.defaultIsolation(nil)]),
        .target(name: "DataAccess", dependencies: ["AppCore"], swiftSettings: [.defaultIsolation(nil)]),
        .testTarget(
            name: "DataAccessTests", dependencies: ["DataAccess", "LocalStore", "Sync"],
            exclude: ["Fixtures/README.md"],
            resources: [
                .copy("Fixtures/auth"), .copy("Fixtures/account"), .copy("Fixtures/trips"), .copy("Fixtures/errors"),
                .copy("Fixtures/plans"), .copy("Fixtures/wizard"),
            ],
            swiftSettings: [.defaultIsolation(nil), .define("CHRONOFLOW_MOCK_SCENARIOS")]),
        .target(
            name: "LocalStore", dependencies: ["AppCore", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.defaultIsolation(nil)]),
        .testTarget(
            name: "LocalStoreTests", dependencies: ["LocalStore"], resources: [.copy("Fixtures")],
            swiftSettings: [.defaultIsolation(nil)]),
        .target(
            name: "TripWizard", dependencies: ["AppCore", "DataAccess", "LocalStore", "Reminders"],
            swiftSettings: [.defaultIsolation(nil)]),
        .target(
            name: "TripWizardUI", dependencies: ["TripWizard", "DesignSystem", "PlanCore"],
            resources: [.process("Resources")], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(
            name: "TripWizardTests",
            dependencies: ["TripWizard", "TripWizardUI", "Sync", "DataAccess", "LocalStore", "PlanCore", "Reminders"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.defaultIsolation(nil)]),
        .target(
            name: "Sync", dependencies: ["AppCore", "LocalStore", "TripWizard"], swiftSettings: [.defaultIsolation(nil)]
        ),
        .testTarget(name: "SyncTests", dependencies: ["Sync", "DataAccess"], swiftSettings: [.defaultIsolation(nil)]),
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
        .target(
            name: "Auth", dependencies: ["DesignSystem", "AppCore"], resources: [.process("Resources")],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(
            name: "AuthTests", dependencies: ["Auth", "DataAccess", "SnapshotSupport"],
            swiftSettings: [.defaultIsolation(nil)]),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem", "SnapshotSupport"],
            resources: [.copy("Fixtures/PlanAudit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "ToolingTests", swiftSettings: [.defaultIsolation(nil)]),
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
            dependencies: ["Welcome", "SnapshotSupport"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
