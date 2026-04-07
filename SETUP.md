# ZeroDark Setup Guide

## Requirements

- iOS 17+ device (iPhone or iPad)
- Xcode 15+
- Apple Developer account (free or paid)
- USB cable for device deployment

## Build & Install

### 1. Clone and open

```bash
git clone https://github.com/jrbobbyhansen-pixel/zerodark.git
cd zerodark
open ZeroDark.xcodeproj
```

### 2. Configure signing

1. Select the **ZeroDark** project in Xcode's navigator
2. Under **Signing & Capabilities**, check "Automatically manage signing"
3. Select your development team
4. Let Xcode create provisioning profiles

### 3. Connect your device

1. Plug in your iPhone/iPad via USB
2. Unlock and trust the computer if prompted
3. Select your device as the build target in Xcode's toolbar

### 4. Build and run

Press **Cmd+R**. First build takes 2-3 minutes. The app will install and launch.

If you see "Untrusted Developer" on the device: Settings > General > VPN & Device Management > Trust.

## First Launch

The app launches into four tabs:

- **Map** — Your tactical map with peer tracking, waypoints, and navigation tools
- **LiDAR** — 3D scanning (requires LiDAR-equipped device)
- **Intel** — Knowledge base search and threat analysis
- **Ops** — Mission planning and team coordination

All features work immediately without any AI models.

## AI Models (Optional)

To enable the on-device AI assistant:

1. Open **Settings** (gear icon in top-right)
2. Browse available models
3. Download over WiFi — models range from 400MB to 7.5GB
4. Once downloaded, the AI assistant works fully offline

Recommended starting model: **Llama 3.2 1B** (~700MB) for a good balance of speed and quality.

## Offline Maps

For map access without connectivity:

1. Obtain a `.pmtiles` file for your area of operations
2. Drop it into the app's Documents directory (via Files app or Xcode)
3. The app auto-detects and renders tiles behind the map layer

## TAK Integration

To connect with FreeTAK Server or ATAK peers:

1. Go to Settings > TAK Configuration
2. Enter your server address and credentials
3. Peers will appear as annotations on the Map tab

## Mesh Networking

For off-grid comms via Meshtastic:

1. Pair a Meshtastic radio via Bluetooth
2. The app bridges messages through the mesh network
3. Connected peers show on the Map tab with status indicators

## Troubleshooting

**Build fails:** Clean build (Shift+Cmd+K) and retry.

**App crashes on launch:** Ensure "Increased Memory Limit" entitlement is present in ZeroDark.entitlements.

**Models won't download:** Check WiFi connection. Try a smaller model first.

**Offline tiles not showing:** Verify the .pmtiles file is in the app's Documents directory and restart the app.
