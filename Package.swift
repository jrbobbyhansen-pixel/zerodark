// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MLXEdgeLLM",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "MLXEdgeLLM",
            targets: ["MLXEdgeLLM"]
        ),
        .library(
            name: "MLXEdgeLLMUI",
            targets: ["MLXEdgeLLMUI"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            branch: "main"
        )
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "MLXEdgeLLM",
            dependencies: [
                .product(name: "MLXVLM",      package: "mlx-swift-lm"),
                .product(name: "MLXLLM",      package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/MLXEdgeLLM"
        ),
        
        // MARK: - UI
        .target(
            name: "MLXEdgeLLMUI",
            dependencies: [
                "MLXEdgeLLM"
            ],
            path: "Sources/MLXEdgeLLMUI"
        ),
        
        // MARK: - Example App
        .executableTarget(
            name: "MLXEdgeLLMExample",
            dependencies: [
                "MLXEdgeLLM",
                "MLXEdgeLLMUI"
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
