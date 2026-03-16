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
| "I found this on the web" | **Actually executes 50+ tools** |
| Can't reason | **14B parameter reasoning** |
| No memory | **Remembers across sessions** |
| Censored | **Uncensored option** |
| One model | **17 models, auto-routed** |
| No code execution | **Runs JavaScript locally** |
| "I can't do that" | **Actually tries** |

---

## 🧰 50+ Real Tools

### Core Tools (34)
| Tool | What It Does |
|------|--------------|
| `weather` | Real weather from Open-Meteo API |
| `calendar` | Read your EventKit calendar |
| `reminder` | Create real Apple Reminders |
| `calculator` | Math via JavaScript engine |
| `timer` / `alarm` | Set timers and alarms |
| `contacts` | Search CNContactStore |
| `notes` | Create/read local notes |
| `directions` | MapKit search |
| `health` | HealthKit: steps, sleep, calories, HR |
| `homekit` | Control smart home devices |
| `translate` | On-device translation |
| `code` | Execute JavaScript safely |
| `clipboard` | Read/write system clipboard |
| `device` / `battery` | Device info, battery level |
| `brightness` / `volume` | Screen and audio control |
| `flashlight` | Toggle torch |
| `music` | Control playback |
| `call` | Initiate phone calls |
| `message` | Compose SMS/iMessage |
| `open_app` | Open any app (30+ URL schemes) |
| `location` | Current location |
| `convert` | Unit conversion |
| `currency` | Currency conversion (12 currencies) |
| `haptic` | Trigger haptic feedback |
| `speak` | Text-to-speech |
| `qr` | Generate QR codes |
| `random` | Random numbers |
| `define` | Dictionary definitions |

### Vision & Speech Tools
| Tool | What It Does |
|------|--------------|
| `ocr` | Extract text from images |
| `detect_objects` | Identify 1000+ objects |
| `face_detect` | Detect faces and landmarks |
| `read_barcode` | Scan QR/barcodes |
| `listen` | Speech-to-text |
| `shazam` | Identify songs |

### Motion & Sensors
| Tool | What It Does |
|------|--------------|
| `motion` | Accelerometer data |
| `pedometer` | Steps, distance, floors |
| `altitude` | Barometric altitude |
| `authenticate` | Face ID / Touch ID |

### Free APIs (No Keys Required)
| Tool | What It Does |
|------|--------------|
| `news` | Headlines via Hacker News API |
| `crypto` | Bitcoin/Ethereum prices (CoinGecko) |
| `nasa` | Picture of the Day |
| `quote` | Inspirational quotes |
| `joke` | Random jokes |
| `fact` | Random facts |
| `trivia` | Trivia questions |
| `wiki` | Wikipedia summaries |
| `air_quality` | AQI by city |
| `sunrise` / `sunset` | Sun times |
| `holidays` | Public holidays by country |
| `bible` | Bible verses |
| `hackernews` | Top HN stories |
| `dog` / `cat` | Random pet images |
| `ip` | Your IP and location |

### System Tools
| Tool | What It Does |
|------|--------------|
| `network` | Connection status |
| `disk` | Storage info |
| `memory` | RAM usage |
| `cpu` | Processor info |

---

## 🎤 Siri Integration (9 Intents)

Say these to activate Zero Dark via Siri:

```
"Hey Siri, ask ZeroDark..."
"Hey Siri, ZeroDark weather"
"Hey Siri, ZeroDark reminder"
"Hey Siri, ZeroDark calculate"
"Hey Siri, ZeroDark health"
"Hey Siri, ZeroDark timer"
"Hey Siri, ZeroDark open app"
"Hey Siri, ZeroDark convert"
"Hey Siri, ZeroDark speak"
```

---

## 🧠 Intelligence Layer

### Power Modes
| Mode | Time | Equivalent | Techniques |
|------|------|------------|------------|
| Quick | 1-2s | ~8B | Speculative decoding |
| Standard | 5-10s | ~50B | ToT + Self-Consistency |
| Deep | 30-60s | ~150B | ZeroSwarm (12 agents) |
| Maximum | 2-5min | ~300B+ | Full ensemble |
| Adaptive | Auto | Auto | Selects based on query |

### ZeroSwarm (12-Agent Debate)
When you need the highest quality, Zero Dark deploys 12 specialized AI agents that debate and reach consensus:

- Analyst, Critic, Creative, Devil's Advocate
- Synthesizer, Fact-Checker, Ethicist, Optimizer
- Generalist, Specialist, Simplifier, Visionary

### RocketFuel (25+ Techniques)
- Speculative decoding (3x speedup)
- Tree of Thoughts
- Monte Carlo Tree Search
- Self-Consistency (5 paths)
- Chain of Thought
- Self-Rewarding
- RAG (Retrieval Augmented Generation)
- And 18 more...

---

## 📱 Zeta³: Device Swarm

Connect multiple Apple devices to distribute AI inference:

```
iPad Pro (16GB) ←→ iPhone 16 Pro (8GB) ←→ Mac Mini (32GB)
         ↓                    ↓                    ↓
    Layers 0-10          Layers 11-20        Layers 21-32
```

- **MultipeerConnectivity** for local networking
- **Pipeline parallelism** across devices
- **Encrypted** communication
- Run models larger than any single device's RAM

---

## 🧠 Infinite Memory

Zero Dark remembers across sessions:

- **L0 (Hot)**: Always loaded, ~100 tokens
- **L1 (Warm)**: Loaded when relevant, ~500 tokens  
- **L2 (Cold)**: Full content, on-demand
- **95%+ token savings** via compression

---

## 🤖 Autonomous Agent

Give Zero Dark a task and watch it work:

```
"Check the weather and remind me if it's going to rain"

→ Analyzing task...
→ Executing: weather
→ ✓ San Antonio: 75°F, Partly cloudy
→ Executing: reminder
→ ✓ Reminder created: "Check for rain"
→ Done!
```

---

## 📊 Models

### Standard Tier (Any iPhone)
| Model | Size | Use Case |
|-------|------|----------|
| Qwen3 0.6B | 0.4GB | Ultra-fast |
| Llama 3.2 1B | 0.7GB | Quick tasks |
| Qwen3 4B | 2.5GB | Balanced |

### Beast Tier (8GB RAM)
| Model | Size | Use Case |
|-------|------|----------|
| ⚡ Qwen3 8B | 4.5GB | Best general |
| 🔓 Abliterated 8B | 4.5GB | Uncensored |
| 🧠 DeepSeek R1 8B | 4.5GB | Reasoning |
| 💻 Qwen Coder 7B | 4.0GB | Code |

### PRO Tier (16GB+ RAM)
| Model | Size | Use Case |
|-------|------|----------|
| 🚀 Qwen 14B | 7.5GB | Desktop-class |
| 🚀 DeepSeek 14B | 7.5GB | Deep reasoning |

---

## 🔒 Privacy

**Zero Dark sends nothing to the cloud. Ever.**

- All models run locally via MLX
- All tools execute on-device
- External APIs (weather, crypto) are optional
- Conversations stored locally
- No telemetry, no analytics, no tracking

---

## 📦 Installation

### Requirements
- iOS 17+ / macOS 14+
- Xcode 15+
- ~5GB storage per model

### Build from Source

```bash
git clone https://github.com/jrbobbyhansen-pixel/zerodark.git
cd zerodark
open ZeroDark.xcodeproj
# Build and run
```

---

## 🗺️ Roadmap

- [x] 50+ tool integrations
- [x] Siri App Intents
- [x] Device swarm
- [x] Power modes
- [x] Autonomous agent
- [ ] Apple Watch companion
- [ ] CarPlay integration
- [ ] Live Activities
- [ ] On-device fine-tuning
- [ ] Widget support

---

## 📄 License

MIT License. See [LICENSE](LICENSE).

---

## 🙏 Credits

Built with:
- [MLX](https://github.com/ml-explore/mlx) by Apple
- [mlx-swift](https://github.com/ml-explore/mlx-swift)
- [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)

---

<p align="center">
  <b>The AI assistant Apple was too scared to build.</b><br>
  <sub>Private. Powerful. Yours.</sub>
</p>
