# ZeroDark

An open-source iOS tactical operations platform built on SwiftUI and on-device AI. Designed for field teams who need mapping, navigation, communications, and intelligence tools that work without cell service.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017%2B-blue.svg)](https://apple.com)

---

## What It Does

ZeroDark puts a full tactical toolkit on your iPhone or iPad — mapping, mesh comms, breadcrumb navigation, line-of-sight analysis, LiDAR scanning, and an on-device AI assistant. Everything runs locally. No cloud dependency, no subscriptions, no telemetry.

**Four tabs, one mission:**

- **Map** — SwiftUI Map with TAK peer tracking, MGRS grid overlay, range rings, breadcrumb trails, terrain contours, waypoint management, offline tile support, and line-of-sight raycast
- **LiDAR** — 3D point cloud capture and mesh export using ARKit
- **Intel** — Hybrid RAG search over a tactical knowledge base (115+ field manuals), threat scoring, and AI-generated situation reports
- **Ops** — Mission planning, team dashboard, comms strip, after-action reports, and OPSEC checklists

---

## Core Systems

### Navigation
- **EKF Breadcrumb Engine** — 7-state Extended Kalman Filter fusing GPS + IMU for smooth trail recording, even under tree canopy or urban canyons
- **Line-of-Sight Raycast** — DEM-based visibility analysis with earth curvature correction. Tap any point on the map to see what's visible and what's blocked
- **360° Viewshed** — Radial LOS computation showing visible/hidden terrain from your position
- **MGRS Grid** — Military Grid Reference System overlay with adaptive zoom levels
- **Celestial Navigation** — Sun/star position calculator for compass-free orientation
- **Dead Reckoning** — IMU-based position estimation when GPS is unavailable

### Mapping
- **Offline Tiles** — PMTiles support for map access without connectivity (UIViewRepresentable backing layer for iOS 17 compatibility)
- **GIS Overlays** — Import KML and Shapefile data directly onto the map
- **Terrain Contours** — Marching squares algorithm generates contour lines from DEM elevation data
- **HotZone Classification** — On-device MLX inference to classify sensor readings into hot/warm/cold zones

### Communications
- **TAK Integration** — Cursor on Target (CoT) protocol support via FreeTAK server and BLE bridge
- **Mesh Networking** — Meshtastic bridge for off-grid peer-to-peer comms with status tracking
- **Haptic Comms** — Tap-coded signal system between nearby devices
- **DTN Messaging** — Delay-Tolerant Networking for store-and-forward message delivery
- **PTT Voice** — Push-to-talk voice relay over mesh

### Intelligence
- **Tactical Knowledge Base** — 115+ field manuals covering medical, navigation, comms, SERE, urban ops, and more
- **Hybrid RAG Search** — Full-text + vector search with Reciprocal Rank Fusion for relevant results
- **Threat Scoring** — Cross-tab threat analysis that syncs between Intel and Map tabs
- **On-Device LLM** — MLX-powered inference (Llama, Qwen, DeepSeek) for situation analysis and field queries

### Field Operations
- **Mission Planning** — Briefings, phase tracking, contingency planning, objective management
- **Team Management** — Roster, check-ins, task assignment, shift scheduling
- **Medical** — TCCC protocols, triage tools, 9-line MEDEVAC formatting
- **Training** — Field exercise planning, scenario generation, skill assessments, after-action reviews

---

## Architecture

```
Sources/MLXEdgeLLM/
├── AI/              # RAG engine, LLM inference, embeddings, prompts
├── App/             # SwiftUI views (MapTabView, IntelTabView, OpsTabView, LiDARTabView)
├── CommunicationCore/  # TAK, Meshtastic, DTN, haptic, voice
├── Coordination/    # Team management, task assignment, incident logging
├── FieldOps/        # Mission planning, reports, team ops
├── Hardware/        # Drone integration, sensor bridges
├── Intelligence/    # Threat tracking, pattern analysis, SITREP generation
├── Interop/         # GIS handlers (KML, Shapefile, GeoPackage, GPX)
├── LiDAR/           # Point cloud capture and processing
├── Logistics/       # Supply tracking, equipment management
├── Mapping/         # Offline tiles, GIS overlays, tile providers
├── Medical/         # TCCC, triage, pharmacy reference
├── Navigation/      # EKF engine, LOS raycast, dead reckoning, terrain analysis
├── Planning/        # Route planning, contingency, resource allocation
├── Resources/       # Knowledge base (115+ field manuals), model configs
├── Scenarios/       # HazMat, SAR, wildfire, active shooter response
├── Security/        # Encryption, session keys, geofencing, runtime safety
├── Services/        # Weather, hydration calc, sun/moon, altitude tracking
├── SpatialIntelligence/  # Distance/bearing, elevation profiles, mesh export
├── Training/        # Exercises, skill tracking, tabletop scenarios
└── UI/              # Shared components and design tokens
```

---

## Getting Started

### Requirements
- iOS 17+ (iPhone or iPad)
- Xcode 15+
- ~5GB storage per AI model (optional — app works without models)

### Build

```bash
git clone https://github.com/jrbobbyhansen-pixel/zerodark.git
cd zerodark
open ZeroDark.xcodeproj
# Select your device target and build
```

The app runs without any AI models installed — mapping, navigation, comms, and ops features all work independently. To enable the AI assistant, download a model through the in-app settings.

### Offline Maps

Drop a `.pmtiles` file into the app's Documents directory for offline map access. The app auto-detects and renders tiles behind the SwiftUI Map layer.

---

## How It's Built

- **SwiftUI + MapKit** (iOS 17 Map API) for the primary interface
- **MLX Swift** for on-device LLM inference on Apple Silicon
- **CoreLocation + CoreMotion** for the EKF navigation engine
- **ARKit + LiDAR** for 3D point cloud capture
- **MultipeerConnectivity + BLE** for mesh networking
- **Combine** for cross-tab state management and event buses

The map system uses a hybrid approach: SwiftUI `Map` with `MapContentBuilder` handles annotations, polylines, and circles natively. For offline tiles (not supported in SwiftUI Map on iOS 17), a thin `MKMapView` UIViewRepresentable sits behind the SwiftUI layer in a ZStack with user interaction disabled.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. The codebase is organized by domain — pick a module that interests you and dive in.

---

## License

MIT License. See [LICENSE](LICENSE).

---

Built with [MLX](https://github.com/ml-explore/mlx-swift) by Apple.
