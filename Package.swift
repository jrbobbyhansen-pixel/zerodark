// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ZeroDark",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ZeroDark",
            targets: ["ZeroDark"]
        ),
    ],
    dependencies: [
        // MLX - Apple Silicon ML framework
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.18.0"),
        
        // MLX LM - LLM implementations
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
    ],
    targets: [
        .target(
            name: "ZeroDark",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
            ],
            path: "Sources/MLXEdgeLLM"
        ),
    ]
)
