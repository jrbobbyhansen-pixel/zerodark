# Contributing to ZeroDark

Thanks for your interest in contributing. Here's how to get involved.

## Reporting Issues

- Use the GitHub issue tracker
- Include device info (iPhone/iPad model, iOS version)
- Include steps to reproduce
- Attach crash logs if applicable

## Pull Requests

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes
4. Push and open a PR
5. Describe what you changed and why

## Code Style

- Follow Swift API Design Guidelines
- Keep files organized by domain module (see Architecture in README)
- Add doc comments for public APIs
- Prefer SwiftUI over UIKit unless there's a specific reason (e.g., offline tiles on iOS 17)

## Development Setup

```bash
git clone https://github.com/jrbobbyhansen-pixel/zerodark.git
cd zerodark
open ZeroDark.xcodeproj
```

Build target: any iOS 17+ device. The app works without AI models — mapping, navigation, and comms features are standalone.

## Areas Where Help Is Needed

**High priority:**
- Testing on different devices (iPhone 15/16, iPad Pro, iPad Air)
- Accessibility improvements (VoiceOver, Dynamic Type)
- Unit tests for Navigation and Mapping modules

**Medium priority:**
- Additional GIS format support (GeoJSON import)
- Improved contour rendering performance at high zoom
- CarPlay integration for navigation features

**Research:**
- On-device model fine-tuning (LoRA on Apple Silicon)
- Improved EKF tuning for different movement patterns
- Alternative offline tile formats

## Project Structure

```
Sources/MLXEdgeLLM/
├── AI/                  # RAG, embeddings, LLM inference
├── App/                 # SwiftUI tab views and sheets
├── CommunicationCore/   # TAK, Meshtastic, DTN, haptic, voice
├── Coordination/        # Team management, task assignment
├── FieldOps/            # Mission planning, reports
├── Hardware/            # Drone, sensor bridges
├── Intelligence/        # Threat analysis, pattern recognition
├── Interop/             # GIS handlers (KML, Shapefile, GPX)
├── LiDAR/               # Point cloud capture
├── Mapping/             # Offline tiles, GIS overlays
├── Medical/             # TCCC, triage protocols
├── Navigation/          # EKF engine, LOS, dead reckoning
├── Resources/           # Knowledge base, model configs
├── Scenarios/           # HazMat, SAR, emergency response
├── Security/            # Encryption, geofencing
├── Services/            # Weather, altitude, environmental
├── SpatialIntelligence/ # Distance/bearing, elevation profiles
├── Training/            # Exercises, skill tracking
└── UI/                  # Shared design components
```

## Questions?

Open an issue on GitHub.
