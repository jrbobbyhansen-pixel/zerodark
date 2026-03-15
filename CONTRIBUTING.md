# Contributing to Zero Dark

First off, thank you for considering contributing to Zero Dark! 🎉

## Code of Conduct

Be excellent to each other. We're building something cool here.

## How Can I Contribute?

### Reporting Bugs

- Use the GitHub issue tracker
- Include device info (iPhone model, iOS version, RAM)
- Include steps to reproduce
- Include crash logs if applicable

### Suggesting Features

- Open an issue with the "enhancement" label
- Explain the use case
- Bonus points for implementation ideas

### Pull Requests

1. Fork the repo
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftLint (config in repo)
- Add documentation comments for public APIs
- Write tests for new features

## Development Setup

```bash
# Clone
git clone https://github.com/bobbyhansenjr/zerodark.git
cd zerodark

# Open in Xcode
open Package.swift

# Build
swift build

# Test
swift test
```

## Areas We Need Help

### High Priority
- **Testing on different devices** — We need performance data from iPhone 15, 16, iPad Pro, Mac
- **Additional tools** — More agentic capabilities
- **Voice pipeline improvements** — Better wake word detection

### Medium Priority
- **UI polish** — Make it beautiful
- **Accessibility** — VoiceOver, Dynamic Type
- **Localization** — Translate to other languages

### Research
- **On-device fine-tuning** — LoRA training on device
- **Smaller models** — Distillation for older devices
- **Speculative decoding** — Speed improvements

## Architecture Overview

```
Sources/
├── MLXEdgeLLM/           # Core library
│   ├── Intelligence/     # Model routing, ensemble, memory
│   ├── Nuclear/          # Tools, code sandbox, integrations
│   ├── Models.swift      # Model definitions
│   └── BeastEngine.swift # MLX wrapper
├── MLXEdgeLLMUI/         # SwiftUI views
├── MLXEdgeLLMVoice/      # Voice pipeline
├── MLXEdgeLLMDocs/       # RAG/document support
└── ZeroDarkApp/          # Demo app
```

## Questions?

Open an issue or reach out on Twitter: [@bobbyhansenjr](https://twitter.com/bobbyhansenjr)

---

**Let's build the AI assistant Apple was too scared to build.** 🌑
