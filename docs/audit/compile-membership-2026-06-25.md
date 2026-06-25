# ZeroDark pbxproj Compile-Membership Map — 2026-06-25

Authoritative map of which Swift files are in the Xcode **Compile Sources** phase vs navigator-only. Foundation F1 makes this deliberate (compile-vs-delete per tree, harvest real orphans first).

| Module | compiled / total | navigator-only |
|---|---:|---:|
| Navigation | 43/59 | 16 |
| LiDAR | 18/57 | 39 |
| Training | 1/47 | 46 |
| Security | 8/43 | 35 |
| Scenarios | 0/42 | 42 |
| App | 39/40 | 1 |
| Interop | 0/40 | 40 |
| Intelligence | 30/31 | 1 |
| AI | 0/30 | 30 |
| FieldOps | 3/30 | 27 |
| CommunicationCore | 21/28 | 7 |
| Services | 20/21 | 1 |
| UI | 0/16 | 16 |
| SpatialIntelligence | 15/16 | 1 |
| Coordination | 12/14 | 2 |
| Mapping | 11/12 | 1 |
| SecurityLayer | 11/11 | 0 |
| Medical | 9/10 | 1 |
| Hardware | 1/9 | 8 |
| Planning | 7/7 | 0 |
| (root) | 3/3 | 0 |
| Tier1 | 3/3 | 0 |
| Logistics | 1/3 | 2 |
| Config | 2/2 | 0 |
| Diagnostics | 2/2 | 0 |
| IntelligenceEngine | 1/1 | 0 |
| Store | 0/1 | 1 |
| **TOTAL** | **261/578** | **317** |

> 317 of 578 files (55%) are navigator-only — not compiled, not shipped. This is the bulk of the felt bloat.

## Navigator-only files by module (F1 delete/harvest worklist)

### Training (46)
- `Training/Field/ControllerConsole.swift`
- `Training/Field/EvaluatorTools.swift`
- `Training/Field/FieldExercisePlanner.swift`
- `Training/Field/ParticipantTracker.swift`
- `Training/Field/PhotoVideoLog.swift`
- `Training/Field/PropsManager.swift`
- `Training/Team/BuddySystem.swift`
- `Training/Team/CommunicationDrill.swift`
- `Training/Team/CoordinationExercise.swift`
- `Training/Team/LeadershipScenarios.swift`
- `Training/Team/StressInoculation.swift`
- `Training/Team/TeamChallenge.swift`
- `Training/Knowledge/CaseStudyBrowser.swift`
- `Training/Knowledge/FlashcardEngine.swift`
- `Training/Knowledge/KnowledgeCheck.swift`
- `Training/Knowledge/LearningPath.swift`
- `Training/Knowledge/ProcedureTrainer.swift`
- `Training/Knowledge/QuickReference.swift`
- `Training/Knowledge/QuizBuilder.swift`
- `Training/Knowledge/VideoLibrary.swift`
- `Training/Tabletop/AarGenerator.swift`
- `Training/Tabletop/DiscussionTracker.swift`
- `Training/Tabletop/HotwashGuide.swift`
- `Training/Tabletop/ImprovementTracker.swift`
- `Training/Tabletop/RoleAssigner.swift`
- `Training/Tabletop/TabletopFacilitator.swift`
- `Training/Scenarios/CommsSimulator.swift`
- `Training/Scenarios/InjectManager.swift`
- `Training/Scenarios/ResourceSimulator.swift`
- `Training/Scenarios/ScenarioBuilder.swift`
- `Training/Scenarios/ScenarioEngine.swift`
- `Training/Scenarios/ScenarioLibrary.swift`
- `Training/Scenarios/ScenarioReplay.swift`
- `Training/Scenarios/TimePressure.swift`
- `Training/Scenarios/VirtualVictims.swift`
- `Training/Scenarios/WeatherSimulator.swift`
- `Training/Skills/CertTracker.swift`
- `Training/Skills/CompetencyTest.swift`
- `Training/Skills/PeerAssessment.swift`
- `Training/Skills/PerformanceTrends.swift`
- `Training/Skills/QualificationCard.swift`
- `Training/Skills/RemediationPlanner.swift`
- `Training/Skills/SkillDecay.swift`
- `Training/Skills/SkillTracker.swift`
- `Training/Skills/TeamSkills.swift`
- `Training/Skills/TrainingLog.swift`

### Scenarios (42)
- `Scenarios/Hazmat/DeconManager.swift`
- `Scenarios/Hazmat/ErgGuide.swift`
- `Scenarios/Hazmat/ExposureTracker.swift`
- `Scenarios/Hazmat/HotZoneClassifier.swift`
- `Scenarios/Hazmat/HotZoneMapper.swift`
- `Scenarios/Urban/SearchMarking.swift`
- `Scenarios/Urban/UsarDashboard.swift`
- `Scenarios/Urban/VictimExtrication.swift`
- `Scenarios/Flood/BoatOperations.swift`
- `Scenarios/Flood/DamBreachPlanner.swift`
- `Scenarios/Flood/FloodDashboard.swift`
- `Scenarios/Flood/HighWaterMarks.swift`
- `Scenarios/Flood/StrandedTracker.swift`
- `Scenarios/Flood/SwiftWaterProtocol.swift`
- `Scenarios/Flood/WaterLevelTracker.swift`
- `Scenarios/Wilderness/LostPersonProfile.swift`
- `Scenarios/Wilderness/PodCalculator.swift`
- `Scenarios/Wilderness/SearchUrgency.swift`
- `Scenarios/Wilderness/TrackTrapManager.swift`
- `Scenarios/Wilderness/WildernessDashboard.swift`
- `Scenarios/Wildfire/BurnoverProtocol.swift`
- `Scenarios/Wildfire/DivisionTracker.swift`
- `Scenarios/Wildfire/FireWeatherMonitor.swift`
- `Scenarios/Wildfire/FirelineMapper.swift`
- `Scenarios/Wildfire/RetardantTracker.swift`
- `Scenarios/Wildfire/SpotFireTracker.swift`
- `Scenarios/Wildfire/WildfireDashboard.swift`
- `Scenarios/Avalanche/AvalancheDashboard.swift`
- `Scenarios/Avalanche/AvyDogCoordinator.swift`
- `Scenarios/Avalanche/BeaconSearchGuide.swift`
- `Scenarios/Avalanche/BurialTimeTracker.swift`
- `Scenarios/Avalanche/ProbeLineManager.swift`
- `Scenarios/MCI/FamilyReunification.swift`
- `Scenarios/MCI/HospitalCapacity.swift`
- `Scenarios/MCI/MciDashboard.swift`
- `Scenarios/MCI/MciResourceTracker.swift`
- `Scenarios/MCI/TransportCoordinator.swift`
- `Scenarios/MCI/TreatmentAreaManager.swift`
- `Scenarios/Technical/ConfinedSpace.swift`
- `Scenarios/Technical/ElevatorRescue.swift`
- `Scenarios/Technical/RopeRescueCalc.swift`
- `Scenarios/Technical/VehicleExtrication.swift`

### Interop (40)
- `Interop/Mesh/DtnProtocol.swift`
- `Interop/Mesh/LoraPacket.swift`
- `Interop/Mesh/MeshDiscovery.swift`
- `Interop/Mesh/MeshGateway.swift`
- `Interop/Mesh/MeshRouting.swift`
- `Interop/Mesh/MeshtasticProtocol.swift`
- `Interop/Radio/AprsGenerator.swift`
- `Interop/Radio/AprsParser.swift`
- `Interop/Radio/Ax25Handler.swift`
- `Interop/Radio/DmrData.swift`
- `Interop/Radio/DstarData.swift`
- `Interop/Radio/NmeaParser.swift`
- `Interop/Radio/WinlinkInterface.swift`
- `Interop/Emergency/CapHandler.swift`
- `Interop/Emergency/EdxlHandler.swift`
- `Interop/Emergency/MutualAid.swift`
- `Interop/Emergency/NimsForms.swift`
- `Interop/Emergency/SarForms.swift`
- `Interop/Emergency/SituationReport.swift`
- `Interop/TAK/AtakPluginBridge.swift`
- `Interop/TAK/CotGenerator.swift`
- `Interop/TAK/CotParser.swift`
- `Interop/TAK/TakChat.swift`
- `Interop/TAK/TakClient.swift`
- `Interop/TAK/TakMarkerSync.swift`
- `Interop/TAK/TakMissionSync.swift`
- `Interop/TAK/TakOfflineCache.swift`
- `Interop/TAK/TakVideo.swift`
- `Interop/API/DataSyncEngine.swift`
- `Interop/API/ExportScheduler.swift`
- `Interop/API/JsonApiClient.swift`
- `Interop/API/MqttClient.swift`
- `Interop/API/XmlHandler.swift`
- `Interop/GIS/CoordinateConverter.swift`
- `Interop/GIS/CsvGeoImport.swift`
- `Interop/GIS/GeojsonHandler.swift`
- `Interop/GIS/KmlHandler.swift`
- `Interop/GIS/MbtilesHandler.swift`
- `Interop/GIS/ProjectionHandler.swift`
- `Interop/GIS/ShapefileHandler.swift`

### LiDAR (39)
- `LiDAR/Fusion/IMUBuffer.swift`
- `LiDAR/Fusion/KalmanConfig.swift`
- `LiDAR/Fusion/KalmanFuse.swift`
- `LiDAR/Fusion/MotionUndistortion.swift`
- `LiDAR/Mesh/MeshRepair.swift`
- `LiDAR/Mesh/MeshSimplifier.swift`
- `LiDAR/NeRF/DepthExtrapolator.swift`
- `LiDAR/NeRF/GaussianSplatEngine.swift`
- `LiDAR/NeRF/GaussianTrainer.swift`
- `LiDAR/Core/CloudComparison.swift`
- `LiDAR/Core/ClutterFilter.swift`
- `LiDAR/Core/Colorization.swift`
- `LiDAR/Core/DeviceCapability.swift`
- `LiDAR/Core/LiDARPipeline.swift`
- `LiDAR/Core/NoiseRemoval.swift`
- `LiDAR/Core/PipelineBenchmark.swift`
- `LiDAR/Core/PointCloudViewer.swift`
- `LiDAR/Core/PointThinning.swift`
- `LiDAR/Core/StreamingProcessor.swift`
- `LiDAR/Core/ThermalMonitor.swift`
- `LiDAR/Core/VegetationFilter.swift`
- `LiDAR/IO/CadExporter.swift`
- `LiDAR/IO/GeotiffExporter.swift`
- `LiDAR/IO/LasHandler.swift`
- `LiDAR/Terrain/CurvatureAnalysis.swift`
- `LiDAR/Terrain/CutFillAnalysis.swift`
- `LiDAR/Terrain/DemGenerator.swift`
- `LiDAR/Terrain/HillshadeGenerator.swift`
- `LiDAR/Terrain/LandformClassification.swift`
- `LiDAR/Terrain/TerrainRoughness.swift`
- `LiDAR/Measure/AngleMeasure.swift`
- `LiDAR/Measure/AreaMeasure.swift`
- `LiDAR/Measure/CrossSection.swift`
- `LiDAR/Measure/DistanceMeasure.swift`
- `LiDAR/Detection/HazardDetector.swift`
- `LiDAR/Detection/ObjectSegmentation.swift`
- `LiDAR/Detection/PersonDetector.swift`
- `LiDAR/Detection/YOLOService.swift`
- `LiDAR/Detection/YOLOThreatDetector.swift`

### Security (35)
- `Security/Encryption/EncryptedBackup.swift`
- `Security/Encryption/EncryptedExport.swift`
- `Security/Encryption/EncryptionAudit.swift`
- `Security/Encryption/EncryptionEngine.swift`
- `Security/Encryption/FileEncryption.swift`
- `Security/Encryption/KeyManagement.swift`
- `Security/Encryption/MemoryEncryption.swift`
- `Security/Access/AccessLog.swift`
- `Security/Access/AuthManager.swift`
- `Security/Access/DataClassification.swift`
- `Security/Access/DeviceTrust.swift`
- `Security/Access/MultiFactor.swift`
- `Security/Access/NeedToKnow.swift`
- `Security/Access/RoleManager.swift`
- `Security/Access/SessionManager.swift`
- `Security/Comms/KeyExchange.swift`
- `Security/OpSec/DeviceSecurity.swift`
- `Security/OpSec/DuressSystem.swift`
- `Security/OpSec/LocationPrivacy.swift`
- `Security/OpSec/MetadataScrubber.swift`
- `Security/OpSec/NetworkIsolation.swift`
- `Security/OpSec/OpsecChecklist.swift`
- `Security/OpSec/OpsecTraining.swift`
- `Security/OpSec/ScreenPrivacy.swift`
- `Security/OpSec/SecureNotes.swift`
- `Security/OpSec/TrailCleaner.swift`
- `Security/Incident/BreachNotifier.swift`
- `Security/Incident/CompromiseAssessment.swift`
- `Security/Incident/EvidenceCollector.swift`
- `Security/Incident/ForensicExport.swift`
- `Security/Incident/IncidentDetector.swift`
- `Security/Incident/IncidentResponse.swift`
- `Security/Incident/IsolationMode.swift`
- `Security/Incident/RecoveryManager.swift`
- `Security/Incident/ThreatIntel.swift`

### AI (30)
- `AI/Tools/ActionValidator.swift`
- `AI/Tools/ToolChainExecutor.swift`
- `AI/Tools/ToolFeedback.swift`
- `AI/Tools/ToolRegistry.swift`
- `AI/Tools/ToolResultParser.swift`
- `AI/Tools/ToolSelector.swift`
- `AI/Context/AttentionManager.swift`
- `AI/Context/ContextSnapshot.swift`
- `AI/Context/ContextWindow.swift`
- `AI/Context/ConversationMemory.swift`
- `AI/Context/EntityTracker.swift`
- `AI/Context/GoalTracker.swift`
- `AI/Context/WorkingMemory.swift`
- `AI/Models/InferenceCache.swift`
- `AI/Models/ModelEnsemble.swift`
- `AI/Models/ModelSwitcher.swift`
- `AI/Models/QuantizationManager.swift`
- `AI/RAG/DocumentIndexer.swift`
- `AI/RAG/EmbeddingEngine.swift`
- `AI/RAG/FieldManualLoader.swift`
- `AI/RAG/HybridSearchIndex.swift`
- `AI/RAG/IntelCorpus.swift`
- `AI/RAG/LessonsLearnedDb.swift`
- `AI/RAG/ProtocolLibrary.swift`
- `AI/RAG/SopAssistant.swift`
- `AI/RAG/TacticalCorpus.swift`
- `AI/RAG/VectorStore.swift`
- `AI/RAG/VerifyPipeline.swift`
- `AI/Safety/OutputValidator.swift`
- `AI/Prompts/FewShotManager.swift`

### FieldOps (27)
- `FieldOps/Mission/ContingencyPlanner.swift`
- `FieldOps/Mission/MissionBriefing.swift`
- `FieldOps/Mission/MissionLog.swift`
- `FieldOps/Mission/MissionPlanner.swift`
- `FieldOps/Mission/ObjectiveManager.swift`
- `FieldOps/Mission/PhaseTracker.swift`
- `FieldOps/Mission/TimelineView.swift`
- `FieldOps/Team/AnnouncementSystem.swift`
- `FieldOps/Team/BuddySystem.swift`
- `FieldOps/Team/HandoffManager.swift`
- `FieldOps/Team/SkillTracker.swift`
- `FieldOps/Team/TeamChat.swift`
- `FieldOps/Team/TeamStatus.swift`
- `FieldOps/Data/CensusTool.swift`
- `FieldOps/Data/DataSync.swift`
- `FieldOps/Data/DataValidation.swift`
- `FieldOps/Data/FormBuilder.swift`
- `FieldOps/Data/SurveySystem.swift`
- `FieldOps/Reports/ContactReport.swift`
- `FieldOps/Reports/DamageAssessment.swift`
- `FieldOps/Reports/IncidentReport.swift`
- `FieldOps/Reports/IntelligenceReport.swift`
- `FieldOps/Reports/ObservationLog.swift`
- `FieldOps/Reports/ReportArchive.swift`
- `FieldOps/Reports/ReportTemplates.swift`
- `FieldOps/Reports/SituationReport.swift`
- `FieldOps/Reports/StatusReport.swift`

### UI (16)
- `UI/Settings/SettingsManager.swift`
- `UI/Navigation/GestureSystem.swift`
- `UI/Navigation/QuickActions.swift`
- `UI/Feedback/FeedbackCollector.swift`
- `UI/Feedback/HapticFeedback.swift`
- `UI/Feedback/TacticalHapticOverlay.swift`
- `UI/Dashboard/WidgetSystem.swift`
- `UI/Voice/VoiceCommands.swift`
- `UI/Theme/DarkModeSystem.swift`
- `UI/Accessibility/AccessibilitySuite.swift`
- `UI/Accessibility/GloveMode.swift`
- `UI/Accessibility/OneHandMode.swift`
- `UI/Notifications/NotificationCenter.swift`
- `UI/Onboarding/OnboardingFlow.swift`
- `UI/Onboarding/TutorialSystem.swift`
- `UI/Help/HelpSystem.swift`

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

### Hardware (8)
- `Hardware/Sensors/Anemometer.swift`
- `Hardware/Sensors/GasDetector.swift`
- `Hardware/Sensors/RadiationMonitor.swift`
- `Hardware/Sensors/WaterQuality.swift`
- `Hardware/Sensors/WeatherStation.swift`
- `Hardware/Satellite/InreachInterface.swift`
- `Hardware/Satellite/SosManager.swift`
- `Hardware/Satellite/SpotInterface.swift`

### CommunicationCore (7)
- `CommunicationCore/ContactReport.swift`
- `CommunicationCore/DtnBundle.swift`
- `CommunicationCore/EncryptionManager.swift`
- `CommunicationCore/FrequencyScanner.swift`
- `CommunicationCore/MeshDiagnostics.swift`
- `CommunicationCore/MessagePriority.swift`
- `CommunicationCore/PositionReport.swift`

### Coordination (2)
- `Coordination/CoordinationView.swift`
- `Coordination/IncidentStore.swift`

### Logistics (2)
- `Logistics/BatteryManager.swift`
- `Logistics/MaintenanceLogger.swift`

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

### Services (1)
- `Services/LightningPredictor.swift`

### Store (1)
- `Store/IAPManager.swift`
