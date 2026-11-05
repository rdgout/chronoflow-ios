// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AssetGen",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AssetGen", targets: ["AssetGen"])],
    dependencies: [.package(path: "../TokenGen")],
    targets: [
        .target(name: "AssetGenCore", dependencies: [.product(name: "TokenGenCore", package: "TokenGen")]),
        .executableTarget(
            name: "AssetGen", dependencies: ["AssetGenCore", .product(name: "TokenGenCore", package: "TokenGen")]),
        .testTarget(
            name: "AssetGenTests", dependencies: ["AssetGenCore", .product(name: "TokenGenCore", package: "TokenGen")]),
    ]
)
