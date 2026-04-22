// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZeroDark",
    platforms: [.iOS(.v17)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.18.0"),
        // Pinned to a specific revision (PR-C9) — branch-tracking could
        // surface API changes on random rebuilds. Bump intentionally along
        // with the matching pin in ZeroDark.xcodeproj.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "edd42fcd947eea0b19665248acf2975a28ddf58b"),
        .package(url: "https://github.com/insidegui/MultipeerKit", from: "0.4.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.0"),
    ],
    targets: []
)
