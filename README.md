# Zero Dark 🌑

**The AI assistant Apple was too scared to build.**

Zero Dark is a fully on-device AI operating system for iOS, iPadOS, macOS, and visionOS. No cloud. No telemetry. No censorship. Just raw intelligence running on Apple Silicon.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017%2B%20%7C%20macOS%2014%2B-blue.svg)](https://apple.com)

---

## Why Zero Dark?

| Siri | Zero Dark |
|------|-----------|
| Cloud-dependent | **100% on-device** |
| "I found this on the web" | **Actually executes tasks** |
| Can't reason | **14B parameter reasoning** |
| No memory | **Remembers across sessions** |
| Censored | **Uncensored option** |
| One model | **17 models, auto-routed** |
| No code execution | **Runs JS/Python locally** |
| "I can't do that" | **Actually tries** |

---

## Features

### 🧠 Intelligence Layer
- **17 LLM models** from 0.6B to 14B parameters
- **Smart routing** — auto-selects best model for each task
- **5 ensemble modes** — parallel, cascade, consensus, speculative
- **Long-term memory** — remembers across sessions
- **Quality scoring** — learns from your feedback

### 🔧 Agentic Tool Use (22 tools)
Execute real actions, not just "here's what I found":

```
"What's on my calendar today?" → Reads EventKit, lists events
"Remind me to call mom at 3pm" → Creates real Apple Reminder
"Get directions to the airport" → MapKit search + turn-by-turn
"What's 15% of $847?" → Calculator → $127.05
"Turn on the living room lights" → HomeKit command
"How did I sleep last night?" → HealthKit analysis
```

### 💻 Code Execution Sandbox
Run code directly on device:
```javascript
// Model writes code, sandbox executes
[5, 2, 8, 1, 9].sort((a, b) => a - b)
// → [1, 2, 5, 8, 9]
```

### 🎤 Voice Pipeline
Full hands-free assistant:
```
🎤 You speak → 🧠 LLM processes → 🔊 AI responds
All on-device. All private.
```

### 🏠 Smart Home Control
Natural language HomeKit:
```
"Turn off everything in the bedroom"
"Set thermostat to 72"
"Run movie night scene"
```

### ❤️ Health Integration
Private health analysis:
```
"How active was I this week?"
→ Steps, calories, exercise, sleep — all from HealthKit
→ Never leaves your device
```

### 🌐 Live Translation
On-device translation (iOS 17.4+):
```
12 languages, works offline
Real-time conversation mode
```

---

## Models

### Standard Tier (Any iPhone)
| Model | Size | Use Case |
|-------|------|----------|
| Qwen3 0.6B | 0.4GB | Ultra-fast responses |
| Llama 3.2 1B | 0.7GB | Quick tasks |
| Qwen3 4B | 2.5GB | Balanced |

### Beast Tier (8GB RAM — iPhone 16 Pro)
| Model | Size | Use Case |
|-------|------|----------|
| ⚡ Qwen3 8B | 4.5GB | Best general |
| 🔓 Qwen3 8B Abliterated | 4.5GB | Uncensored |
| 🧠 DeepSeek R1 8B | 4.5GB | Reasoning |
| 💻 Qwen2.5 Coder 7B | 4.0GB | Code |
| 👁️ Qwen3 VL 8B | 4.8GB | Vision |

### PRO Tier (16GB RAM — iPad Pro M4 / Mac)
| Model | Size | Use Case |
|-------|------|----------|
| 🚀 Qwen2.5 14B | 7.5GB | Desktop-class |
| 🚀 DeepSeek R1 14B | 7.5GB | Deep reasoning |
| 🚀 Qwen2.5 Coder 14B | 7.5GB | Professional code |

---

## Installation

### Requirements
- iOS 17+ / macOS 14+ / visionOS 1+
- Xcode 15+
- ~5GB free storage (per model)

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/bobbyhansenjr/zerodark.git", branch: "main")
]
```

### Build from Source

```bash
git clone https://github.com/bobbyhansenjr/zerodark.git
cd zerodark
open Package.swift
# Build and run in Xcode
```

---

## Quick Start

```swift
import MLXEdgeLLM
import MLXEdgeLLMUI

// Basic chat
struct ContentView: View {
    var body: some View {
        ZeroDarkView()
    }
}

// Programmatic use
let ai = ZeroDarkAI.shared

// Simple generation
let response = try await ai.generate("Explain quantum computing")

// With tool use
let result = try await ai.generate(
    "What's on my calendar tomorrow?",
    enableTools: true
)

// Voice conversation
let voice = VoicePipeline.shared
try voice.startListening()
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      ZERO DARK                               │
├─────────────────────────────────────────────────────────────┤
│  User Input                                                  │
│      ↓                                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Model Router│→ │Ensemble Eng │→ │Quality Score│         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│      ↓                                                       │
│  ┌─────────────────────────────────────────────────┐        │
│  │              NUCLEAR MODE                        │        │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐   │        │
│  │  │ Tools  │ │  Code  │ │ Voice  │ │ Health │   │        │
│  │  │ (22)   │ │Sandbox │ │Pipeline│ │  Kit   │   │        │
│  │  └────────┘ └────────┘ └────────┘ └────────┘   │        │
│  │  ┌────────┐ ┌────────┐ ┌────────┐              │        │
│  │  │HomeKit │ │Translate│ │ Screen │              │        │
│  │  │Control │ │  (12)  │ │  OCR   │              │        │
│  │  └────────┘ └────────┘ └────────┘              │        │
│  └─────────────────────────────────────────────────┘        │
│      ↓                                                       │
│  Response (text / speech / action)                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Privacy

**Zero Dark sends nothing to the cloud. Ever.**

- All models run locally via MLX
- All tools execute on-device
- Conversations stored locally (SQLite)
- No telemetry, no analytics, no tracking
- Your data stays on your device

---

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Areas We Need Help
- [ ] More model support
- [ ] Additional tools
- [ ] UI improvements
- [ ] Documentation
- [ ] Testing on different devices
- [ ] Localization

---

## Roadmap

- [ ] Apple Watch companion
- [ ] CarPlay integration
- [ ] Shortcuts automation
- [ ] On-device fine-tuning (LoRA)
- [ ] Offline knowledge packs
- [ ] Widget support
- [ ] iCloud encrypted sync

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Credits

Built with:
- [MLX](https://github.com/ml-explore/mlx) by Apple
- [mlx-swift](https://github.com/ml-explore/mlx-swift)
- [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)

Models from:
- [Qwen](https://github.com/QwenLM/Qwen)
- [Meta Llama](https://llama.meta.com)
- [DeepSeek](https://github.com/deepseek-ai/DeepSeek-R1)
- [Mistral](https://mistral.ai)

---

<p align="center">
  <b>The AI assistant Apple was too scared to build.</b><br>
  <sub>Private. Powerful. Yours.</sub>
</p>
