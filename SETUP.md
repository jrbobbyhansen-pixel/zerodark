# DarkPhone Setup Guide

## What This Is

A custom iOS app for your iPhone 16 Pro Max that runs:
- **Text AI** — Local LLM (Qwen3, Llama, Gemma)
- **Vision AI** — Analyze photos, screenshots, documents
- **Voice AI** — Speak → LLM → Speaks back (100% local)
- **Document RAG** — Import PDFs, ask questions
- **OCR** — Extract text from images, receipts

All processing happens on-device. No internet. No cloud. Complete privacy.

---

## Prerequisites

- ✅ Xcode 16+ installed on your Mac
- ✅ Apple Developer account (you already have this)
- ✅ iPhone 16 Pro Max with USB-C cable
- ✅ WiFi for initial model downloads

---

## Step-by-Step Build

### 1. Open the Project

```bash
open ~/Developer/DarkPhone/Sources/DarkPhoneApp/DarkPhone.xcodeproj
```

### 2. Configure Signing (First Time Only)

1. In Xcode, click on **DarkPhone** in the left sidebar (the blue project icon)
2. Select **DarkPhone** under TARGETS
3. Click **Signing & Capabilities** tab
4. Check **"Automatically manage signing"**
5. Select your Team from the dropdown (Bobby Hansen or Hill Country Ventures)
6. If prompted, let Xcode create/update provisioning profiles

### 3. Connect Your Dark Phone

1. Plug in your iPhone 16 Pro Max via USB-C
2. Unlock the phone
3. If prompted "Trust This Computer?" → tap **Trust**
4. In Xcode top bar, select your iPhone as the build target (instead of simulator)

### 4. Build & Run

1. Press **⌘R** (Command + R) or click the Play button
2. Wait for build (first time takes 2-3 minutes)
3. App will install and launch on your phone
4. If prompted on phone, go to Settings → General → VPN & Device Management → Trust the developer profile

### 5. Download Models (One Time, Requires WiFi)

On the phone:
1. Open **DarkPhone** app
2. Go to **Models** tab
3. Recommended downloads:
   - **Qwen3 1.7B** (~1GB) — Best balance for text
   - **Qwen3.5 0.8B Vision** (~625MB) — Image analysis
   - **FastVLM 0.5B** (~1.25GB) — Receipt/document OCR
4. Tap each model to download
5. Wait for all downloads to complete

### 6. Go Dark

1. Close Xcode on your Mac
2. Unplug the phone
3. On the phone: **Settings → Airplane Mode → ON**
4. Done. App works forever, completely offline.

---

## Using the App

### Text Tab
- Type any question
- Get AI response
- Conversation history saved locally

### Voice Tab
- Tap mic → Speak
- AI processes your speech
- AI responds with voice
- All local, no network

### Vision Tab
- Take photo or select from library
- Ask: "What's in this image?"
- Get detailed analysis

### OCR Tab
- Point camera at receipt/document
- Get structured data extraction
- Works offline

### Docs Tab
- Import PDFs, DOCX, images
- Ask questions about your documents
- Local RAG (retrieval augmented generation)

### Models Tab
- See download status
- Download additional models
- Switch between models

---

## Model Recommendations

| Model | Size | Best For |
|-------|------|----------|
| Qwen3 0.6B | ~400MB | Ultra-fast, basic |
| **Qwen3 1.7B** ⭐ | ~1GB | Best balance |
| Qwen3 4B | ~2.5GB | Higher quality |
| **Qwen3.5 0.8B Vision** ⭐ | ~625MB | Photo analysis |
| Qwen3.5 2B Vision | ~1.7GB | Better accuracy |
| **FastVLM 0.5B** ⭐ | ~1.25GB | Receipt scanning |

⭐ = Recommended for iPhone 16 Pro Max

---

## Troubleshooting

### "Untrusted Developer" error
Settings → General → VPN & Device Management → Trust

### Build fails
1. Clean build: Shift + ⌘ + K
2. Try again: ⌘R

### Model download stuck
- Check WiFi connection
- Force close app, reopen
- Try downloading a smaller model first

### App crashes on launch
- Make sure you have the "Increased Memory Limit" entitlement (already configured)
- Try with smaller model (Qwen3 0.6B)

---

## Privacy

- All models run locally on the A18 Pro Neural Engine
- No data ever leaves your device
- No API keys, no accounts, no telemetry
- Works in airplane mode forever

---

Built with MLXEdgeLLM • https://github.com/wangxuncaiGH/MLXEdgeLLM
