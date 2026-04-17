// AppNavigation.swift — Tactical nav shell + cross-tab state
import SwiftUI
import MapKit
import CoreLocation
import Combine

/// Active tactical tab
public enum AppTab: String, CaseIterable {
    case map   = "Map"
    case nav   = "Nav"
    case lidar = "LiDAR"
    case intel = "Intel"
    case ops = "Ops"

    public var icon: String {
        switch self {
        case .map: return "map.fill"
        case .nav: return "location.north.fill"
        case .lidar: return "cube.fill"
        case .intel: return "brain"
        case .ops: return "shield.checkered"
        }
    }
}

// MARK: - LLM Status

public enum LLMStatus: String {
    case idle
    case loading
    case ready
    case error
}

// MARK: - Map Layer Configuration

public struct MapLayerConfig: Equatable {
    public var showMGRS: Bool = false
    public var showRangeRings: Bool = false
    public var showContours: Bool = false
    public var showCameras: Bool = false
    public var showThreatPins: Bool = true
    public var useSatellite: Bool = false
    public var tacticalMode: Bool = false
    public var nightMode: Bool = false
    public var showBreadcrumbs: Bool = true
    public var showMeshPeers: Bool = true
    public var showGISOverlays: Bool = true

    public static let `default` = MapLayerConfig()
}

// MARK: - Map Events (cross-tab pub/sub)

public enum MapEvent {
    case centerOnCoordinate(CLLocationCoordinate2D)
    case highlightWaypoint(UUID)
    case showLOS(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)
    case zoomToRegion(MKCoordinateRegion)
    case refreshPeers
}

// MARK: - Intel Events (v6 cross-tab)

public enum IntelEvent {
    case newSearchResult(query: String, resultCount: Int)
    case photoAnalyzed(photoId: UUID, summary: String)
    case lessonAdded(scenario: String)
    case corpusReindexed(documentCount: Int)
}

// MARK: - Threat Events (v6 cross-tab)

public enum ThreatEvent {
    case scoreChanged(old: Double, new: Double)
    case threatDetected(category: String, level: String, description: String)
    case threatResolved(id: UUID)
    case alertRaised(message: String)
}

// MARK: - Root App State

@MainActor
public class AppState: ObservableObject {
    public static let shared = AppState()

    // Tab
    @Published public var selectedTab: AppTab = .map

    // Cross-tab shared state
    @Published public var currentLocation: CLLocationCoordinate2D?
    @Published public var mapRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
    )
    @Published public var llmStatus: LLMStatus = .idle
    @Published public var meshPeerCount: Int = 0
    @Published public var mapLayerConfig: MapLayerConfig = .default
    @Published public var selectedWaypointId: UUID?

    // Intel/Threat state (v6 — synced from ThreatAnalyzer)
    @Published public var currentThreatScore: Double = 0.0
    @Published var currentThreatLevel: ThreatLevel = .none
    @Published public var activeThreatCount: Int = 0
    @Published public var latestIntelSummary: String = ""
    @Published public var intelUpdateCount: Int = 0

    // LiDAR SceneTag (v6 — set from LiDARCaptureEngine after scan)
    @Published public var latestSceneTag: Any?

    // Navigation state (v6.1 — fused from BreadcrumbEngine, DR, Celestial, Battery)
    @Published var navState: NavState = NavState()

    // Pub/sub event buses for cross-tab coordination
    public let mapEventBus = PassthroughSubject<MapEvent, Never>()
    public let intelEventBus = PassthroughSubject<IntelEvent, Never>()
    public let threatEventBus = PassthroughSubject<ThreatEvent, Never>()
    let navEventBus = PassthroughSubject<NavEvent, Never>()

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Threat Sync (v6)

    public func setupThreatSync() {
        let analyzer = ThreatAnalyzer.shared

        // Sync threat score
        analyzer.threatScorePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newScore in
                guard let self else { return }
                let old = self.currentThreatScore
                self.currentThreatScore = newScore
                if abs(old - newScore) > 0.5 {
                    self.threatEventBus.send(.scoreChanged(old: old, new: newScore))
                }
            }
            .store(in: &cancellables)

        // Sync threat level
        analyzer.threatLevelPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentThreatLevel)

        // Sync active threat count
        analyzer.activeThreatsPublisher
            .receive(on: DispatchQueue.main)
            .map(\.count)
            .assign(to: &$activeThreatCount)

        // Forward alert messages as threat events
        analyzer.$alertMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.threatEventBus.send(.alertRaised(message: message))
            }
            .store(in: &cancellables)
    }

    // MARK: - Intel Updates (v6)

    public func postIntelEvent(_ event: IntelEvent) {
        intelUpdateCount += 1
        intelEventBus.send(event)
    }

    public func updateIntelSummary(_ summary: String) {
        latestIntelSummary = summary
    }

    // MARK: - Navigation Sync (v6.1)

    private var navSyncSetup = false

    public func setupNavSync() {
        guard !navSyncSetup else { return }
        navSyncSetup = true

        let bc = BreadcrumbEngine.shared

        // Fuse BreadcrumbEngine EKF outputs into navState
        bc.$currentPosition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pos in
                self?.navState.position = pos
                if let pos {
                    self?.navEventBus.send(.positionUpdated(pos))
                }
            }
            .store(in: &cancellables)

        bc.$heading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hdg in
                self?.navState.heading = hdg
            }
            .store(in: &cancellables)

        bc.$speedMps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spd in
                self?.navState.speed = spd
            }
            .store(in: &cancellables)

        bc.$positionUncertaintyMeters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unc in
                self?.navState.ekfUncertainty = unc
            }
            .store(in: &cancellables)

        bc.$canopyDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canopy in
                self?.navState.canopyDetected = canopy
            }
            .store(in: &cancellables)

        // Wire battery data into NavState
        let battery = BatteryProxy.shared
        battery.$drainRatePerHour
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.navState.batteryTrend = rate
            }
            .store(in: &cancellables)

        battery.$estimatedMinutesRemaining
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mins in
                self?.navState.batteryMinutesRemaining = mins
            }
            .store(in: &cancellables)
    }
}

extension AppTab {
    public var label: String { rawValue }
}
