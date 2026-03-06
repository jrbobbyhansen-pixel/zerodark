// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MLXEdgeLLM",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "MLXEdgeLLM",
            targets: ["MLXEdgeLLM"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-examples",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: "MLXEdgeLLM",
            dependencies: [
                .product(name: "MLXVLM", package: "mlx-swift-examples"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
            path: "Sources/MLXEdgeLLM"
        )
    ]
)
