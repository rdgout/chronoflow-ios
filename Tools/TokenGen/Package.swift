// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TokenGen",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenGenCore", targets: ["TokenGenCore"]), .executable(name: "TokenGen", targets: ["TokenGen"]),
    ],
    targets: [
        .target(name: "TokenGenCore"), .executableTarget(name: "TokenGen", dependencies: ["TokenGenCore"]),
        .testTarget(name: "TokenGenTests", dependencies: ["TokenGenCore"]),
    ]
)
