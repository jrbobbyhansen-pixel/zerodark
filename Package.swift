// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZeroDark",
    platforms: [.iOS(.v17)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.18.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        .package(url: "https://github.com/insidegui/MultipeerKit", from: "0.4.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.0"),
        .package(url: "https://github.com/ngageoint/mgrs-ios", from: "2.0.0"),
        .package(url: "https://github.com/ngageoint/gars-ios", from: "2.0.0"),
        .package(url: "https://github.com/ngageoint/geopackage-ios", from: "9.0.0"),
    ],
    targets: []
)
