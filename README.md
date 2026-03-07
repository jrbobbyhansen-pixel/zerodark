# MLXEdgeLLM

Lightweight on-device LLM & VLM Swift package for iOS/macOS, powered by MLX. Run Qwen3, Llama, Gemma, SmolVLM and other models locally — no API keys, no binary dependencies, fully private.

---

## Requirements

- iOS 17+ / macOS 14+ / visionOS 1+
- Xcode 16+
- `Increased Memory Limit` entitlement (required for models > 500 MB)

---

## Installation

Add via Swift Package Manager:

```
https://github.com/iOSDevC/MLXEdgeLLM
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/iOSDevC/MLXEdgeLLM", branch: "main")
```

### Modules

| Module | Contents |
|--------|----------|
| `MLXEdgeLLM` | Core inference, models, conversation persistence |
| `MLXEdgeLLMUI` | SwiftUI views and ViewModels for drop-in UI |

```swift
// Core only
import MLXEdgeLLM

// Core + prebuilt SwiftUI interface
import MLXEdgeLLM
import MLXEdgeLLMUI
```

---

## Text Chat

```swift
import MLXEdgeLLM

// One-liner
let reply = try await MLXEdgeLLM.chat("¿Cuánto gasté esta semana?")

// Reusable instance (loads model once — preferred for multiple calls)
let llm = try await MLXEdgeLLM.text(.qwen3_1_7b) { progress in
    print(progress) // "Downloading Qwen3 1.7B: 42%"
}
let reply = try await llm.chat("Summarize my expenses")

// Streaming
for try await token in llm.stream("Explain this transaction") {
    print(token, terminator: "")
}

// With system prompt
let reply = try await llm.chat(
    "What is the VAT rate in Mexico?",
    systemPrompt: "You are a personal finance assistant."
)
```

### Text Models

| Model | Size | Best for |
|-------|------|----------|
| `.qwen3_0_6b` | ~400 MB | Ultra-fast responses |
| `.qwen3_1_7b` ⭐ | ~1.0 GB | Balanced (default) |
| `.qwen3_4b` | ~2.5 GB | Higher quality |
| `.gemma3_1b` | ~700 MB | Google alternative |
| `.phi3_5_mini` | ~2.2 GB | Microsoft alternative |
| `.llama3_2_1b` | ~700 MB | Meta, lightweight |
| `.llama3_2_3b` | ~1.8 GB | Meta, higher quality |

---

## Vision / Image Analysis

```swift
import MLXEdgeLLM

// One-liner receipt extraction
let json = try await MLXEdgeLLM.extractDocument(receiptImage)
// → {"store":"OXXO","date":"2026-03-06","items":[...],"total":125.50,"currency":"MXN"}

// Reusable instance
let vlm = try await MLXEdgeLLM.vision(.qwen35_0_8b) { print($0) }

// Free-form image analysis
let description = try await vlm.analyze("What items are on this receipt?", image: photo)

// Streaming with image
for try await token in vlm.streamVision("Describe this image", image: photo) {
    print(token, terminator: "")
}
```

### Vision Models

| Model | Size | Best for |
|-------|------|----------|
| `.qwen35_0_8b` ⭐ | ~625 MB | Default, iPhone |
| `.qwen35_2b` | ~1.7 GB | iPad, higher accuracy |
| `.smolvlm_500m` | ~1.0 GB | Minimum memory |
| `.smolvlm_2b` | ~1.5 GB | SmolVLM, balanced |

---

## OCR & Document Extraction

Specialized models optimized for receipts, invoices, and structured documents.

```swift
import MLXEdgeLLM

// FastVLM — outputs structured JSON
let ocr = try await MLXEdgeLLM.specialized(.fastVLM_0_5b_fp16) { print($0) }
let json = try await ocr.extractDocument(receiptImage)

// Granite Docling — outputs DocTags, converted to Markdown
let docOCR = try await MLXEdgeLLM.specialized(.graniteDocling_258m)
let raw = try await docOCR.extractDocument(documentImage)
let markdown = MLXEdgeLLM.parseDocTags(raw)
```

### Specialized Models

| Model | Size | Output |
|-------|------|--------|
| `.fastVLM_0_5b_fp16` ⭐ | ~1.25 GB | JSON (receipts) |
| `.fastVLM_1_5b_int8` | ~800 MB | JSON (receipts) |
| `.graniteDocling_258m` | ~631 MB | DocTags → Markdown |
| `.graniteVision_3_3` | ~1.2 GB | Plain text |

---

## Receipt Scanner Example

```swift
import MLXEdgeLLM

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

func scanReceipt(_ image: PlatformImage) async throws -> ReceiptData {
    let json = try await MLXEdgeLLM.extractDocument(image)
    return try JSONDecoder().decode(ReceiptData.self, from: Data(json.utf8))
}
```

---

## Conversation Persistence

`ConversationStore` provides a SQLite-backed store (no external dependencies) for persisting chat history. The LLM automatically loads a context window of the most recent turns that fit within the token budget.

```swift
import MLXEdgeLLM

let store = ConversationStore.shared

// Create a conversation
let conv = try await store.createConversation(model: .qwen3_1_7b, title: "Finance assistant")

// Chat with automatic history — context window managed automatically
let llm = try await MLXEdgeLLM.text(.qwen3_1_7b)
let reply = try await llm.chat("What is 2+2?", in: conv.id)
let reply2 = try await llm.chat("Why?", in: conv.id) // includes previous exchange

// Streaming with history
for try await token in llm.stream("Tell me more", in: conv.id) {
    print(token, terminator: "")
}

// One-liner (creates conversation automatically)
let (reply, convID) = try await MLXEdgeLLM.chat("Hello", model: .qwen3_1_7b)

// List all conversations
let conversations = try await store.allConversations()

// Full-text search across all messages
let results = try await store.search("VAT Mexico")

// Auto-title based on first message
try await llm.autoTitle(conversationID: conv.id)

// Prune and summarize long conversations
try await llm.summarizeAndPrune(conversationID: conv.id)
```

### Context Window Management

When a conversation exceeds the token budget, `summarizeAndPrune` uses the model itself to summarize older turns and replace them with a compact system-level summary — preserving semantic continuity without truncating abruptly.

```swift
// Automatically called during chat if conversation exceeds 4096 tokens
try await llm.summarizeAndPrune(
    conversationID: conv.id,
    keepLastN: 10,        // always keep the 10 most recent turns
    maxContextTokens: 4096
)
```

---

## Prebuilt SwiftUI Interface

`MLXEdgeLLMUI` provides a ready-to-use tabbed interface with Text Chat, Vision, OCR, and a model browser.

```swift
import SwiftUI
import MLXEdgeLLMUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView() // 4-tab interface, ready to use
        }
    }
}
```

Tabs included:

| Tab | Description |
|-----|-------------|
| **Text** | Persistent multi-conversation chat with streaming |
| **Vision** | Image analysis with standard and streaming modes |
| **OCR** | Document and receipt extraction |
| **Models** | Browser showing all models and download status |

---

## Model Discovery

```swift
import MLXEdgeLLM

// Filtered collections — downloaded models sorted first
let textModels        = Model.textModels
let visionModels      = Model.visionModels
let specializedModels = Model.specializedModels

// Check download status
if Model.qwen3_1_7b.isDownloaded {
    print("Ready at: \(Model.qwen3_1_7b.cacheDirectory.path)")
}

// Model metadata
let model = Model.qwen3_1_7b
print(model.displayName)       // "Qwen3 1.7B"
print(model.approximateSizeMB) // 1000
print(model.purpose)           // .text
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
MLXEdgeLLM (public API)
├── MLXEdgeLLM.text()        →  TextEngine  →  MLXLLM
├── MLXEdgeLLM.vision()      →  VisionEngine  →  MLXVLM
├── MLXEdgeLLM.specialized() →  VisionEngine  →  MLXVLM
├── ConversationStore        →  SQLite (no external deps)
└── MLXEdgeLLM+History       →  context window · auto-title · pruning

MLXEdgeLLMUI (optional)
├── ContentView  (TabView)
├── TextChatTab  →  TextChatViewModel  →  ConversationStore
├── VisionTab    →  VisionViewModel
├── OCRTab       →  OCRViewModel
└── ModelsTab

All models download automatically on first use and are cached at:
  ~/Library/Caches/models/<org>/<repo>/
```

---

## License

Apache 2.0
