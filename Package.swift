// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZeroDark",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        // MARK: - Libraries (for embedding in other apps)
        .library(name: "ZeroDarkCore",    targets: ["MLXEdgeLLM"]),
        .library(name: "ZeroDarkUI",      targets: ["MLXEdgeLLMUI"]),
        .library(name: "ZeroDarkVoice",   targets: ["MLXEdgeLLMVoice"]),
        .library(name: "ZeroDarkDocs",    targets: ["MLXEdgeLLMDocs"]),
        
        // Legacy names (backward compat)
        .library(name: "MLXEdgeLLM",      targets: ["MLXEdgeLLM"]),
        .library(name: "MLXEdgeLLMUI",    targets: ["MLXEdgeLLMUI"]),
        .library(name: "MLXEdgeLLMVoice", targets: ["MLXEdgeLLMVoice"]),
        .library(name: "MLXEdgeLLMDocs",  targets: ["MLXEdgeLLMDocs"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            branch: "main"
        )
    ],
    targets: [
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Core Engine
        // ═══════════════════════════════════════════════════════════════
        .target(
            name: "MLXEdgeLLM",
            dependencies: [
                .product(name: "MLXVLM",      package: "mlx-swift-lm"),
                .product(name: "MLXLLM",      package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/MLXEdgeLLM",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - UI Components
        // ═══════════════════════════════════════════════════════════════
        .target(
            name: "MLXEdgeLLMUI",
            dependencies: [
                "MLXEdgeLLM",
                "MLXEdgeLLMVoice",
            ],
            path: "Sources/MLXEdgeLLMUI"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Voice Pipeline (STT + TTS)
        // ═══════════════════════════════════════════════════════════════
        .target(
            name: "MLXEdgeLLMVoice",
            dependencies: ["MLXEdgeLLM"],
            path: "Sources/MLXEdgeLLMVoice"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Document RAG
        // ═══════════════════════════════════════════════════════════════
        .target(
            name: "MLXEdgeLLMDocs",
            dependencies: ["MLXEdgeLLM"],
            path: "Sources/MLXEdgeLLMDocs"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Demo App (for Package-based building)
        // ═══════════════════════════════════════════════════════════════
        .executableTarget(
            name: "ZeroDarkApp",
            dependencies: [
                "MLXEdgeLLM",
                "MLXEdgeLLMUI",
                "MLXEdgeLLMVoice",
                "MLXEdgeLLMDocs",
            ],
            path: "Sources/ZeroDarkApp"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Example (minimal)
        // ═══════════════════════════════════════════════════════════════
        .target(
            name: "MLXEdgeLLMExample",
            dependencies: [
                "MLXEdgeLLM",
                "MLXEdgeLLMUI",
                "MLXEdgeLLMVoice",
                "MLXEdgeLLMDocs",
            ],
            path: "Sources/MLXEdgeLLMExample"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Tests
        // ═══════════════════════════════════════════════════════════════
        .testTarget(
            name: "ZeroDarkTests",
            dependencies: ["MLXEdgeLLM"],
            path: "Tests/MLXEdgeLLMTests"
        )
    ]
)
