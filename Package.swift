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
            url: "https://github.com/ml-explore/mlx-swift-lm",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: "MLXEdgeLLM",
            dependencies: [
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/MLXEdgeLLM"
        ),
        // MARK: - Example App
        .executableTarget(
            name: "MLXEdgeLLMExample",
            dependencies: [
                "MLXEdgeLLM"
            ],
            path: "Sources/MLXEdgeLLMExample"
        ),
        
        // MARK: - Tests
        .testTarget(
            name: "MLXEdgeLLMTests",
            dependencies: ["MLXEdgeLLM"],
            path: "Tests/MLXEdgeLLMTests"
        )
    ]
)
