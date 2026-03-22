# ZeroDark iOS App — Tier 1 Features

**Platform:** iPhone 16 Pro Max (iOS 18+, Swift 6, SwiftUI)
**Architecture:** Fully offline. Zero internet, zero cell, zero cloud. All data AES-256-GCM encrypted on device.

---

## Features Built

| Feature | File | Status |
|---------|------|--------|
| Offline Speech Transcription + Keyword Alerting | Features/Transcription/ | ✅ Complete |
| DTMF Tone Sequence Logger (Goertzel DSP) | Features/DTMFLogger/ | ✅ Complete |
| Environmental Condition Monitor | Features/EnvironmentMonitor/ | ✅ Complete |
| Offline LLM Field Assistant | Features/LLMAssistant/ | ⚠️ Stub — needs MLXEdgeLLM |

---

## Architecture

```
CAPTURE LAYER
  Mic (AVAudioEngine)  →  Transcription, DTMF, Voice Input
  Sensors (CoreMotion) →  Environment Monitor
  GPS (CoreLocation)   →  [future features]
  LiDAR / Camera       →  [future features]
        ↓
PROCESS LAYER
  AVAudioEngine DSP    →  Goertzel DTMF detection, audio tap
  SFSpeechRecognizer   →  On-device speech-to-text (requiresOnDeviceRecognition=true)
  CoreMotion           →  RMS vibration, pressure delta, gyro threshold
  MLXEdgeLLM (stub)    →  On-device LLM inference [integrate below]
        ↓
VAULT LAYER
  VaultManager         →  AES-256-GCM via CryptoKit
  Key derivation       →  SHA-256(UIDevice.identifierForVendor)
  Storage              →  documentDirectory/ZeroDarkVault/
  Export               →  AirDrop or USB only (decrypted temp file)
```

---

## Adding to an Xcode Project

1. Create a new Xcode project (iOS App, SwiftUI, Swift 6)
2. Drag the `ZeroDark/` folder into the project navigator
3. Add required frameworks: `AVFoundation`, `Speech`, `CoreMotion`, `CryptoKit`, `UserNotifications`
4. Add Info.plist keys (see below)
5. Build and run on a physical device (speech recognition requires real hardware)

---

## Required Info.plist Keys

```xml
<key>NSMicrophoneUsageDescription</key>
<string>ZeroDark uses the microphone for offline speech transcription and DTMF detection.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>ZeroDark uses on-device speech recognition with no data sent to Apple servers.</string>

<key>NSMotionUsageDescription</key>
<string>ZeroDark monitors motion sensors to detect environmental anomalies.</string>
```

---

## Integrating MLXEdgeLLM (Feature 003)

1. Add Swift Package: `https://github.com/ml-explore/mlx-swift-examples`
2. Import: `import MLXLMCommon` and `import MLXLLM`
3. Replace `LocalLLMStub` in `LLMAssistant.swift`:

```swift
// Download model on first launch (WiFi required once):
let modelConfig = ModelConfiguration.predefined.first { $0.name.contains("Qwen3-0.6B") }!
let container = try await LLMModelFactory.shared.loadContainer(configuration: modelConfig)

// Wire to LLMProvider protocol:
actor MLXProvider: LLMProvider {
    let container: ModelContainer
    func generate(prompt: String) async -> String {
        let result = try? await container.perform { model, tokenizer in
            let messages = [["role": "user", "content": prompt]]
            return try await model.generate(messages: messages, maxTokens: 512, tokenizer: tokenizer)
        }
        return result ?? "Inference failed"
    }
}
```

4. Update `modelStatus` in `LLMAssistantViewModel` to reflect loaded model name.

**Recommended models for iPhone 16 Pro Max (8GB RAM):**
- `mlx-community/Qwen3-0.6B-4bit` — ~200MB, fastest
- `mlx-community/SmolLM2-360M-Instruct-4bit` — ~180MB, smallest
- `mlx-community/Llama-3.2-1B-Instruct-4bit` — ~500MB, best quality

---

## TRRS Cable Audio Input

To route Baofeng radio audio into the iPhone mic input:

```swift
// In any feature that uses AVAudioSession:
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, options: [
    .defaultToSpeaker,
    .allowBluetooth,
    .mixWithOthers  // remove if you want radio audio only
])
try session.setActive(true)
```

The Kenwood-compatible TRRS pinout (tip=audio out, ring1=audio in, ring2=PTT, sleeve=ground)
maps correctly to iPhone via a Lightning or USB-C TRRS adapter.

**Audio level calibration:** Match Baofeng earpiece output to iPhone mic input level.
If DTMF decoding or transcription is unreliable, add a 1kΩ inline attenuator to reduce
the Baofeng earpiece output level before it hits the iPhone mic input.

---

## Vault Location

All encrypted data stored at:
```
~/Documents/ZeroDarkVault/
  transcript_2026-03-21T...txt     (encrypted)
  dtmf_2026-03-21T...json          (encrypted)
  environment_2026-03-21T...json   (encrypted)
  llm_session_2026-03-21T...json   (encrypted)
```

Encryption: AES-256-GCM. Key: SHA-256(UIDevice.identifierForVendor). Not synced to iCloud.
Export: ShareLink creates a decrypted temp copy — original vault file remains encrypted.
