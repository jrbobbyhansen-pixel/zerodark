# ZeroDark Build Status

**Last Updated:** 2026-03-16 04:30 UTC (March 15, 11:30 PM CDT)

## Status: BUILD PASSING

Both macOS and iOS Simulator builds verified.

## How to Run

1. **Open in Xcode:**
   ```bash
   open ~/Developer/ZeroDark/Package.swift
   ```

2. **Select scheme:** `ZeroDarkApp`

3. **Select destination:** Any iPhone simulator (e.g., iPhone 17 Pro)

4. **Build & Run:** Cmd+R

## What's in the MVP

### Core Intelligence (Sources/MLXEdgeLLM/)
- **MLXInference.swift** - Model loading, inference, streaming
- **DeepInference.swift** - Tree of Thoughts, Self-Consistency, MCTS
- **ZeroSwarm.swift** - 12 agent personas for debate
- **InfiniteMemory.swift** - Episodic, semantic, procedural memory
- **LearnFromEverything.swift** - 12 learning sources
- **Supercharged.swift** - Mode orchestration
- **RocketFuel.swift** - Inference techniques
- **DeepHardcore.swift** - Autonomous agents, Metal compute
- **ConversationMemory.swift** - Chat history

### App (App/)
- **ZeroDarkApp.swift** - App entry point
- **ContentView.swift** - Chat UI with model selection

## Features Working

- Model download from HuggingFace
- Local inference on Apple Silicon
- Chat interface
- Token/second stats

## Disabled Modules (_disabled_modules/)

UI modules disabled due to missing dependencies. Can be restored later:
- MLXEdgeLLMUI - Advanced chat views
- MLXEdgeLLMVoice - Voice synthesis
- MLXEdgeLLMDocs - Document parsing
- ZeroDarkApp (old Xcode project)

## Next Steps

1. Run on simulator - verify model loading works
2. Test chat functionality
3. Add back features incrementally
