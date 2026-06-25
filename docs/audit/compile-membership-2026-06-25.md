# ZeroDark pbxproj Compile-Membership Map — 2026-06-25

Authoritative Compile Sources membership, after the F1 dead-tree purge (Hardware + 227 fake navigator-only files removed). Remaining navigator-only files are REAL-but-unwired engines kept for later wiring (LiDAR pipeline, RAG corpora, crypto/opsec, training sims).

| Module | compiled / total | navigator-only |
|---|---:|---:|
| Navigation | 43/59 | 16 |
| LiDAR | 18/47 | 29 |
| App | 39/40 | 1 |
| Intelligence | 30/31 | 1 |
| CommunicationCore | 21/28 | 7 |
| Services | 20/21 | 1 |
| Security | 8/16 | 8 |
| SpatialIntelligence | 15/16 | 1 |
| Coordination | 12/14 | 2 |
| Mapping | 11/12 | 1 |
| SecurityLayer | 11/11 | 0 |
| Medical | 9/10 | 1 |
| Planning | 7/7 | 0 |
| AI | 0/7 | 7 |
| (root) | 3/3 | 0 |
| Tier1 | 3/3 | 0 |
| UI | 0/2 | 2 |
| Config | 2/2 | 0 |
| Training | 0/2 | 2 |
| Interop | 0/2 | 2 |
| Diagnostics | 2/2 | 0 |
| Scenarios | 0/2 | 2 |
| Logistics | 1/2 | 1 |
| Hardware | 1/1 | 0 |
| FieldOps | 1/1 | 0 |
| IntelligenceEngine | 1/1 | 0 |
| Store | 0/1 | 1 |
| **TOTAL** | **258/343** | **85** |

> 258/343 files (~75%) compiled. Remaining 85 navigator-only are intentional harvest/wiring targets.

## Remaining navigator-only (real-but-unwired — keep)

### LiDAR (29)
- `LiDAR/Fusion/IMUBuffer.swift`
- `LiDAR/Fusion/KalmanConfig.swift`
- `LiDAR/Fusion/KalmanFuse.swift`
- `LiDAR/Fusion/MotionUndistortion.swift`
- `LiDAR/Mesh/MeshRepair.swift`
- `LiDAR/Mesh/MeshSimplifier.swift`
- `LiDAR/NeRF/DepthExtrapolator.swift`
- `LiDAR/NeRF/GaussianSplatEngine.swift`
- `LiDAR/NeRF/GaussianTrainer.swift`
- `LiDAR/Core/ClutterFilter.swift`
- `LiDAR/Core/Colorization.swift`
- `LiDAR/Core/DeviceCapability.swift`
- `LiDAR/Core/LiDARPipeline.swift`
- `LiDAR/Core/NoiseRemoval.swift`
- `LiDAR/Core/PipelineBenchmark.swift`
- `LiDAR/Core/ThermalMonitor.swift`
- `LiDAR/IO/LasHandler.swift`
- `LiDAR/Terrain/CurvatureAnalysis.swift`
- `LiDAR/Terrain/CutFillAnalysis.swift`
- `LiDAR/Terrain/DemGenerator.swift`
- `LiDAR/Terrain/HillshadeGenerator.swift`
- `LiDAR/Terrain/LandformClassification.swift`
- `LiDAR/Terrain/TerrainRoughness.swift`
- `LiDAR/Measure/DistanceMeasure.swift`
- `LiDAR/Detection/HazardDetector.swift`
- `LiDAR/Detection/ObjectSegmentation.swift`
- `LiDAR/Detection/PersonDetector.swift`
- `LiDAR/Detection/YOLOService.swift`
- `LiDAR/Detection/YOLOThreatDetector.swift`

### Navigation (16)
- `Navigation/BreadcrumbTrail.swift`
- `Navigation/MagneticDeclination.swift`
- `Navigation/NavigationViewModel.swift`
- `Navigation/TerrainMeshGenerator.swift`
- `Navigation/Core/NavigationInterface.swift`
- `Navigation/Core/NavigationTypes.swift`
- `Navigation/Core/TacticalNavigationStack.swift`
- `Navigation/TrajectoryOptimization/SimBandOptimizer.swift`
- `Navigation/GraphPlanning/GraphEdge.swift`
- `Navigation/GraphPlanning/GraphNode.swift`
- `Navigation/GraphPlanning/NavigationGraph.swift`
- `Navigation/Persistence/NavLogStore.swift`
- `Navigation/Views/TacticalNavigationView.swift`
- `Navigation/Control/PurePursuitController.swift`
- `Navigation/PathPlanning/GridMap.swift`
- `Navigation/PathPlanning/HybridAStarPlanner.swift`

### Security (8)
- `Security/Encryption/EncryptedBackup.swift`
- `Security/Encryption/EncryptedExport.swift`
- `Security/Encryption/FileEncryption.swift`
- `Security/OpSec/DeviceSecurity.swift`
- `Security/OpSec/LocationPrivacy.swift`
- `Security/OpSec/NetworkIsolation.swift`
- `Security/OpSec/ScreenPrivacy.swift`
- `Security/Incident/RecoveryManager.swift`

### AI (7)
- `AI/RAG/EmbeddingEngine.swift`
- `AI/RAG/HybridSearchIndex.swift`
- `AI/RAG/IntelCorpus.swift`
- `AI/RAG/LessonsLearnedDb.swift`
- `AI/RAG/TacticalCorpus.swift`
- `AI/RAG/VectorStore.swift`
- `AI/RAG/VerifyPipeline.swift`

### CommunicationCore (7)
- `CommunicationCore/ContactReport.swift`
- `CommunicationCore/DtnBundle.swift`
- `CommunicationCore/EncryptionManager.swift`
- `CommunicationCore/FrequencyScanner.swift`
- `CommunicationCore/MeshDiagnostics.swift`
- `CommunicationCore/MessagePriority.swift`
- `CommunicationCore/PositionReport.swift`

### UI (2)
- `UI/Feedback/HapticFeedback.swift`
- `UI/Feedback/TacticalHapticOverlay.swift`

### Coordination (2)
- `Coordination/CoordinationView.swift`
- `Coordination/IncidentStore.swift`

### Training (2)
- `Training/Scenarios/ResourceSimulator.swift`
- `Training/Scenarios/VirtualVictims.swift`

### Interop (2)
- `Interop/Radio/Ax25Handler.swift`
- `Interop/Radio/NmeaParser.swift`

### Scenarios (2)
- `Scenarios/Hazmat/HotZoneClassifier.swift`
- `Scenarios/MCI/HospitalCapacity.swift`

### Mapping (1)
- `Mapping/GISOverlayProvider.swift`

### App (1)
- `App/Terrain3DView.swift`

### Intelligence (1)
- `Intelligence/TimelineReconstructor.swift`

### SpatialIntelligence (1)
- `SpatialIntelligence/ScanMatching/SubmapStore.swift`

### Medical (1)
- `Medical/HypothermiaCalc.swift`

### Logistics (1)
- `Logistics/BatteryManager.swift`

### Services (1)
- `Services/LightningPredictor.swift`

### Store (1)
- `Store/IAPManager.swift`
