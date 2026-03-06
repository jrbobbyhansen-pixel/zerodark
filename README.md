# MLXEdgeLLM

Lightweight on-device LLM & VLM Swift package for iOS/macOS, powered by MLX. Run Qwen3.5, SmolVLM and other vision-language models locally — no API keys, no binary dependencies.

---

## Requirements

- iOS 17+ / macOS 14+
- Xcode 16+
- `Increased Memory Limit` entitlement (required for models > 500 MB)

## Installation

Add via Swift Package Manager:

```
https://github.com/iOSDevC/MLXEdgeLLM
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/iOSDevC/MLXEdgeLLM", branch: "main")
```

---

## Text Chat

```swift
import MLXEdgeLLM

// One-liner
let reply = try await MLXEdgeLLM.chat("¿Cuánto gasté esta semana?")

// Instance (recommended for multiple calls — loads model once)
let llm = try await MLXEdgeLLM(
    model: .qwen3_1_7b,
    onProgress: { print("Downloading: \(Int($0 * 100))%") }
)
let reply = try await llm.chat("Summarize my expenses")

// Streaming
for try await token in await llm.stream("Explain this transaction") {
    print(token, terminator: "")
}

// With system prompt
let options = MLXEdgeLLM.Options(systemPrompt: "You are a personal finance assistant.")
let llm = try await MLXEdgeLLM(model: .qwen3_1_7b, options: options)
```

### Text Models

| Model | Size | Best for |
|-------|------|----------|
| `.qwen3_0_6b` | ~400 MB | Ultra-fast responses |
| `.qwen3_1_7b` ⭐ | ~1.0 GB | Balanced (default) |
| `.qwen3_4b` | ~2.5 GB | Higher quality |
| `.gemma3_1b` | ~700 MB | Google alternative |
| `.phi3_5_mini` | ~2.2 GB | Microsoft alternative |
| `.llama3_2_1b` | ~700 MB | Meta alternative |
| `.llama3_2_3b` | ~1.8 GB | Meta, higher quality |

---

## Vision / Image Analysis

```swift
import MLXEdgeLLM
import UIKit

// Receipt extraction (one-liner)
let json = try await MLXEdgeLLMVision.extractReceipt(ticketUIImage)
// → { "store": "OXXO", "date": "2026-03-06", "items": [...], "total": 125.50, "currency": "MXN" }

// Free-form image analysis
let description = try await MLXEdgeLLMVision.analyze(
    "What items are on this receipt?",
    image: receiptImage
)

// Instance (recommended for multiple calls)
let vision = try await MLXEdgeLLMVision(
    model: .qwen35_0_8b,
    onProgress: { print("Downloading: \(Int($0 * 100))%") }
)
let json1 = try await vision.extractReceipt(ticket1)
let json2 = try await vision.extractReceipt(ticket2)

// Streaming with image
for try await token in vision.stream("Describe this image", image: photo) {
    print(token, terminator: "")
}

// Text-only chat (no image)
let answer = try await vision.chat("What is the average tax rate in Mexico?")
```

### Vision Models

| Model | Size | Best for |
|-------|------|----------|
| `.qwen35_0_8b` ⭐ | ~1.0 GB | iPhone, receipt OCR (default) |
| `.qwen35_2b` | ~1.8 GB | iPad, higher accuracy |
| `.qwen35_4b` | ~3.2 GB | Mac / iPad Pro |
| `.qwen25vl_2b` | ~1.4 GB | Stable alternative |
| `.gemma3_4b` | ~2.5 GB | Google alternative |
| `.smolvlm_500m` | ~500 MB | Minimum memory |
| `.smolvlm_2b` | ~1.2 GB | SmolVLM, balanced |

---

## Receipt Scanner Example

```swift
import MLXEdgeLLM
import UIKit

struct ReceiptData: Codable {
    let store: String
    let date: String
    let items: [Item]
    let subtotal: Double
    let tax: Double
    let total: Double
    let currency: String

    struct Item: Codable {
        let name: String
        let quantity: Int
        let price: Double
    }
}

func scanReceipt(_ image: UIImage) async throws -> ReceiptData {
    let json = try await MLXEdgeLLMVision.extractReceipt(image)
    return try JSONDecoder().decode(ReceiptData.self, from: Data(json.utf8))
}
```

---

## Entitlements

Add to your `.entitlements` file for models larger than 500 MB:

```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

---

## Architecture

```
MLXEdgeLLM (text)         MLXEdgeLLMVision (image + text)
       │                              │
  TextEngine                    VisionEngine
       │                              │
  MLXLLM                         MLXVLM
       └──────────────┬───────────────┘
                mlx-swift-examples
                (mlx-community / HuggingFace)
```

Models download automatically on first use and are cached locally in `~/Library/Caches/`.

---

## License

Apache 2.0
