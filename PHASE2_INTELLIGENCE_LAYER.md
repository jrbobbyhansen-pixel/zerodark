# ZeroDark Phase 2: Intelligence Layer
## Implementation Spec for Claude Code

**Version:** 1.0  
**Date:** 2026-03-19  
**Estimated Effort:** 2 weeks  
**Source Patterns:** NASA Open MCT, DoD ATAK-CIV, NASA ICAROUS, Boeing SDR-Hazards

**Prerequisites:** Phase 1 complete (ActionBoundary, DTN, SafetyMonitor, MeshCrypto)

---

## Overview

This document specifies four intelligence capabilities for ZeroDark:

1. **MCT-Style Telemetry Dashboard** (NASA Open MCT pattern)
2. **Threat Classification NLP** (Boeing SDR-Hazards pattern)
3. **Tactical Map Overlays** (DoD ATAK-CIV pattern)
4. **Geofencing Safety Zones** (NASA ICAROUS pattern)

---

## 1. MCT-Style Telemetry Dashboard (NASA Open MCT Pattern)

### Source
- Repository: https://github.com/nasa/openmct (13K+ stars)
- Used by: NASA Ames for spacecraft missions and rover operations
- Key Insight: Plugin-based telemetry objects with time-series data and composable views

### Purpose
Transform the Intel tab into a mission-control-style dashboard with real-time telemetry from all ZeroDark sensors and team members.

### File Structure
```
Sources/MLXEdgeLLM/Intelligence/
├── Telemetry/
│   ├── TelemetryObject.swift           # Core data type
│   ├── TelemetryStore.swift            # Central store
│   ├── TelemetryAdapter.swift          # Data source protocol
│   ├── Adapters/
│   │   ├── LocationAdapter.swift       # GPS telemetry
│   │   ├── TeamAdapter.swift           # Team member positions
│   │   ├── SensorAdapter.swift         # Device sensors
│   │   ├── MeshAdapter.swift           # Mesh network stats
│   │   └── WeatherAdapter.swift        # Weather data
│   └── Views/
│       ├── TelemetryDashboard.swift    # Main dashboard
│       ├── TelemetryPanel.swift        # Single metric panel
│       ├── TelemetryTimeline.swift     # Time-series view
│       └── TelemetryComposer.swift     # Layout composer
```

### Implementation

#### TelemetryObject.swift
```swift
import Foundation

/// Core telemetry data type (NASA Open MCT pattern: Telemetry Object)
public struct TelemetryDatum: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let key: String              // e.g., "position.latitude"
    public let value: TelemetryValue
    public let source: String           // e.g., "gps", "team.alpha"
    public let metadata: [String: String]
    
    public init(key: String, value: TelemetryValue, source: String, metadata: [String: String] = [:]) {
        self.id = UUID()
        self.timestamp = Date()
        self.key = key
        self.value = value
        self.source = source
        self.metadata = metadata
    }
}

/// Type-safe telemetry values
public enum TelemetryValue: Codable, Equatable {
    case double(Double)
    case int(Int)
    case string(String)
    case bool(Bool)
    case coordinate(latitude: Double, longitude: Double)
    case vector3(x: Double, y: Double, z: Double)
    
    public var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }
    
    public var displayString: String {
        switch self {
        case .double(let v): return String(format: "%.2f", v)
        case .int(let v): return "\(v)"
        case .string(let v): return v
        case .bool(let v): return v ? "Yes" : "No"
        case .coordinate(let lat, let lon): return String(format: "%.4f, %.4f", lat, lon)
        case .vector3(let x, let y, let z): return String(format: "(%.2f, %.2f, %.2f)", x, y, z)
        }
    }
}

/// Telemetry object definition (MCT pattern: defines what telemetry looks like)
public struct TelemetryObjectType: Identifiable {
    public let id: String               // e.g., "position"
    public let name: String             // e.g., "GPS Position"
    public let icon: String             // SF Symbol
    public let keys: [TelemetryKey]     // Available data points
    public let refreshRate: TimeInterval
    
    public struct TelemetryKey: Identifiable {
        public let id: String           // e.g., "latitude"
        public let name: String         // e.g., "Latitude"
        public let unit: String?        // e.g., "°"
        public let format: String?      // e.g., "%.6f"
        public let range: ClosedRange<Double>?
    }
}

/// Pre-defined telemetry object types
public extension TelemetryObjectType {
    static let position = TelemetryObjectType(
        id: "position",
        name: "GPS Position",
        icon: "location.fill",
        keys: [
            .init(id: "latitude", name: "Latitude", unit: "°", format: "%.6f", range: -90...90),
            .init(id: "longitude", name: "Longitude", unit: "°", format: "%.6f", range: -180...180),
            .init(id: "altitude", name: "Altitude", unit: "m", format: "%.1f", range: -500...50000),
            .init(id: "accuracy", name: "Accuracy", unit: "m", format: "%.1f", range: 0...1000),
            .init(id: "speed", name: "Speed", unit: "m/s", format: "%.1f", range: 0...100),
            .init(id: "heading", name: "Heading", unit: "°", format: "%.0f", range: 0...360)
        ],
        refreshRate: 1.0
    )
    
    static let battery = TelemetryObjectType(
        id: "battery",
        name: "Battery",
        icon: "battery.100",
        keys: [
            .init(id: "level", name: "Level", unit: "%", format: "%.0f", range: 0...100),
            .init(id: "state", name: "State", unit: nil, format: nil, range: nil)
        ],
        refreshRate: 60.0
    )
    
    static let mesh = TelemetryObjectType(
        id: "mesh",
        name: "Mesh Network",
        icon: "network",
        keys: [
            .init(id: "peers", name: "Connected Peers", unit: nil, format: "%.0f", range: 0...20),
            .init(id: "pending_bundles", name: "Pending Messages", unit: nil, format: "%.0f", range: nil),
            .init(id: "anomaly_level", name: "Anomaly Level", unit: nil, format: nil, range: nil)
        ],
        refreshRate: 5.0
    )
    
    static let team = TelemetryObjectType(
        id: "team",
        name: "Team Status",
        icon: "person.2.fill",
        keys: [
            .init(id: "count", name: "Team Size", unit: nil, format: "%.0f", range: nil),
            .init(id: "last_checkin", name: "Last Check-in", unit: nil, format: nil, range: nil),
            .init(id: "spread", name: "Team Spread", unit: "m", format: "%.0f", range: nil)
        ],
        refreshRate: 10.0
    )
    
    static let weather = TelemetryObjectType(
        id: "weather",
        name: "Weather",
        icon: "cloud.fill",
        keys: [
            .init(id: "temperature", name: "Temperature", unit: "°F", format: "%.1f", range: -50...150),
            .init(id: "humidity", name: "Humidity", unit: "%", format: "%.0f", range: 0...100),
            .init(id: "wind_speed", name: "Wind Speed", unit: "mph", format: "%.1f", range: 0...200),
            .init(id: "conditions", name: "Conditions", unit: nil, format: nil, range: nil)
        ],
        refreshRate: 300.0
    )
    
    static let threat = TelemetryObjectType(
        id: "threat",
        name: "Threat Level",
        icon: "exclamationmark.triangle.fill",
        keys: [
            .init(id: "level", name: "Current Level", unit: nil, format: "%.0f", range: 1...5),
            .init(id: "source", name: "Source", unit: nil, format: nil, range: nil),
            .init(id: "last_update", name: "Last Update", unit: nil, format: nil, range: nil)
        ],
        refreshRate: 5.0
    )
    
    static let allTypes: [TelemetryObjectType] = [
        .position, .battery, .mesh, .team, .weather, .threat
    ]
}
```

#### TelemetryAdapter.swift
```swift
import Foundation
import Combine

/// Protocol for telemetry data sources (MCT pattern: Telemetry Provider)
public protocol TelemetryAdapter {
    var objectType: TelemetryObjectType { get }
    var isAvailable: Bool { get }
    
    /// Subscribe to real-time updates
    func subscribe() -> AnyPublisher<TelemetryDatum, Never>
    
    /// Request historical data
    func request(key: String, start: Date, end: Date) async -> [TelemetryDatum]
    
    /// Get latest value for a key
    func latest(key: String) async -> TelemetryDatum?
}

/// Base adapter with common functionality
open class BaseTelemetryAdapter: TelemetryAdapter {
    public let objectType: TelemetryObjectType
    public var isAvailable: Bool { true }
    
    internal let subject = PassthroughSubject<TelemetryDatum, Never>()
    internal var history: [String: [TelemetryDatum]] = [:]
    internal let historyLimit = 1000
    
    public init(objectType: TelemetryObjectType) {
        self.objectType = objectType
    }
    
    public func subscribe() -> AnyPublisher<TelemetryDatum, Never> {
        subject.eraseToAnyPublisher()
    }
    
    public func request(key: String, start: Date, end: Date) async -> [TelemetryDatum] {
        let fullKey = "\(objectType.id).\(key)"
        return (history[fullKey] ?? []).filter {
            $0.timestamp >= start && $0.timestamp <= end
        }
    }
    
    public func latest(key: String) async -> TelemetryDatum? {
        let fullKey = "\(objectType.id).\(key)"
        return history[fullKey]?.last
    }
    
    internal func emit(_ datum: TelemetryDatum) {
        // Store in history
        var keyHistory = history[datum.key] ?? []
        keyHistory.append(datum)
        if keyHistory.count > historyLimit {
            keyHistory.removeFirst(keyHistory.count - historyLimit)
        }
        history[datum.key] = keyHistory
        
        // Emit to subscribers
        subject.send(datum)
    }
}
```

#### Adapters/LocationAdapter.swift
```swift
import Foundation
import CoreLocation
import Combine

/// GPS telemetry adapter
public class LocationTelemetryAdapter: BaseTelemetryAdapter, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    
    public override var isAvailable: Bool {
        CLLocationManager.locationServicesEnabled()
    }
    
    public init() {
        super.init(objectType: .position)
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        emit(TelemetryDatum(
            key: "position.latitude",
            value: .double(location.coordinate.latitude),
            source: "gps"
        ))
        
        emit(TelemetryDatum(
            key: "position.longitude",
            value: .double(location.coordinate.longitude),
            source: "gps"
        ))
        
        emit(TelemetryDatum(
            key: "position.altitude",
            value: .double(location.altitude),
            source: "gps"
        ))
        
        emit(TelemetryDatum(
            key: "position.accuracy",
            value: .double(location.horizontalAccuracy),
            source: "gps"
        ))
        
        emit(TelemetryDatum(
            key: "position.speed",
            value: .double(max(0, location.speed)),
            source: "gps"
        ))
        
        emit(TelemetryDatum(
            key: "position.coordinate",
            value: .coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            source: "gps"
        ))
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        emit(TelemetryDatum(
            key: "position.heading",
            value: .double(newHeading.trueHeading),
            source: "gps"
        ))
    }
}
```

#### Adapters/MeshAdapter.swift
```swift
import Foundation
import Combine

/// Mesh network telemetry adapter
public class MeshTelemetryAdapter: BaseTelemetryAdapter {
    private var timer: Timer?
    
    public init() {
        super.init(objectType: .mesh)
        startPolling()
    }
    
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: objectType.refreshRate, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll() // Initial poll
    }
    
    private func poll() {
        // Integration point: HapticComms
        // let peers = HapticComms.shared.connectedPeers.count
        let peers = 0 // Placeholder
        
        emit(TelemetryDatum(
            key: "mesh.peers",
            value: .int(peers),
            source: "mesh"
        ))
        
        // Integration point: DTNBuffer
        Task { @MainActor in
            let pending = DTNBuffer.shared.pendingCount
            self.emit(TelemetryDatum(
                key: "mesh.pending_bundles",
                value: .int(pending),
                source: "dtn"
            ))
        }
        
        // Integration point: MeshAnomalyDetector
        // let anomaly = MeshAnomalyDetector.shared.currentLevel
        emit(TelemetryDatum(
            key: "mesh.anomaly_level",
            value: .string("none"),
            source: "mesh"
        ))
    }
    
    deinit {
        timer?.invalidate()
    }
}
```

#### Adapters/TeamAdapter.swift
```swift
import Foundation
import Combine
import CoreLocation

/// Team member telemetry adapter
public class TeamTelemetryAdapter: BaseTelemetryAdapter {
    private var timer: Timer?
    
    public init() {
        super.init(objectType: .team)
        startPolling()
    }
    
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: objectType.refreshRate, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }
    
    private func poll() {
        // Integration point: HapticComms peer tracking
        // let members = HapticComms.shared.teamMembers
        
        emit(TelemetryDatum(
            key: "team.count",
            value: .int(0),  // Placeholder
            source: "mesh"
        ))
        
        emit(TelemetryDatum(
            key: "team.last_checkin",
            value: .string(ISO8601DateFormatter().string(from: Date())),
            source: "mesh"
        ))
        
        // Calculate team spread (max distance between any two members)
        // let spread = calculateTeamSpread(members)
        emit(TelemetryDatum(
            key: "team.spread",
            value: .double(0),  // Placeholder
            source: "calculated"
        ))
    }
    
    deinit {
        timer?.invalidate()
    }
}
```

#### Adapters/WeatherAdapter.swift
```swift
import Foundation
import Combine
import CoreLocation

/// Weather telemetry adapter (Open-Meteo API)
public class WeatherTelemetryAdapter: BaseTelemetryAdapter {
    private var timer: Timer?
    private var lastLocation: CLLocationCoordinate2D?
    
    public init() {
        super.init(objectType: .weather)
        startPolling()
    }
    
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: objectType.refreshRate, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchWeather()
            }
        }
        Task {
            await fetchWeather()
        }
    }
    
    private func fetchWeather() async {
        // Get current location
        // Integration point: LocationManager
        let lat = 29.4241  // Placeholder: San Antonio
        let lon = -98.4936
        
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code&temperature_unit=fahrenheit&wind_speed_unit=mph"
        
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            
            if let current = response.current {
                emit(TelemetryDatum(
                    key: "weather.temperature",
                    value: .double(current.temperature_2m ?? 0),
                    source: "open-meteo"
                ))
                
                emit(TelemetryDatum(
                    key: "weather.humidity",
                    value: .double(Double(current.relative_humidity_2m ?? 0)),
                    source: "open-meteo"
                ))
                
                emit(TelemetryDatum(
                    key: "weather.wind_speed",
                    value: .double(current.wind_speed_10m ?? 0),
                    source: "open-meteo"
                ))
                
                let conditions = weatherCodeToString(current.weather_code ?? 0)
                emit(TelemetryDatum(
                    key: "weather.conditions",
                    value: .string(conditions),
                    source: "open-meteo"
                ))
            }
        } catch {
            print("[WeatherAdapter] Error: \(error)")
        }
    }
    
    private func weatherCodeToString(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2, 3: return "Partly Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 61, 63, 65: return "Rain"
        case 71, 73, 75: return "Snow"
        case 80, 81, 82: return "Showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Unknown"
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

struct OpenMeteoResponse: Codable {
    let current: CurrentWeather?
    
    struct CurrentWeather: Codable {
        let temperature_2m: Double?
        let relative_humidity_2m: Int?
        let wind_speed_10m: Double?
        let weather_code: Int?
    }
}
```

#### TelemetryStore.swift
```swift
import Foundation
import Combine

/// Central telemetry store (MCT pattern: Telemetry Collection)
@MainActor
public class TelemetryStore: ObservableObject {
    public static let shared = TelemetryStore()
    
    @Published public private(set) var latestValues: [String: TelemetryDatum] = [:]
    @Published public private(set) var adapters: [String: any TelemetryAdapter] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        registerDefaultAdapters()
    }
    
    private func registerDefaultAdapters() {
        register(LocationTelemetryAdapter())
        register(MeshTelemetryAdapter())
        register(TeamTelemetryAdapter())
        register(WeatherTelemetryAdapter())
        register(BatteryTelemetryAdapter())
    }
    
    /// Register a telemetry adapter
    public func register(_ adapter: any TelemetryAdapter) {
        adapters[adapter.objectType.id] = adapter
        
        // Subscribe to updates
        adapter.subscribe()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] datum in
                self?.latestValues[datum.key] = datum
            }
            .store(in: &cancellables)
        
        print("[TelemetryStore] Registered adapter: \(adapter.objectType.name)")
    }
    
    /// Get latest value for a key
    public func getValue(_ key: String) -> TelemetryDatum? {
        latestValues[key]
    }
    
    /// Get all values for an object type
    public func getValues(for objectType: TelemetryObjectType) -> [String: TelemetryDatum] {
        latestValues.filter { $0.key.hasPrefix("\(objectType.id).") }
    }
    
    /// Request historical data
    public func history(key: String, duration: TimeInterval) async -> [TelemetryDatum] {
        let objectTypeId = key.components(separatedBy: ".").first ?? ""
        guard let adapter = adapters[objectTypeId] else { return [] }
        
        let end = Date()
        let start = end.addingTimeInterval(-duration)
        let keyPart = key.components(separatedBy: ".").dropFirst().joined(separator: ".")
        
        return await adapter.request(key: keyPart, start: start, end: end)
    }
}

/// Battery telemetry adapter
public class BatteryTelemetryAdapter: BaseTelemetryAdapter {
    private var timer: Timer?
    
    public init() {
        super.init(objectType: .battery)
        UIDevice.current.isBatteryMonitoringEnabled = true
        startPolling()
    }
    
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: objectType.refreshRate, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }
    
    private func poll() {
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        
        emit(TelemetryDatum(
            key: "battery.level",
            value: .double(Double(level * 100)),
            source: "device"
        ))
        
        let stateString: String
        switch state {
        case .charging: stateString = "Charging"
        case .full: stateString = "Full"
        case .unplugged: stateString = "Unplugged"
        default: stateString = "Unknown"
        }
        
        emit(TelemetryDatum(
            key: "battery.state",
            value: .string(stateString),
            source: "device"
        ))
    }
    
    deinit {
        timer?.invalidate()
    }
}
```

#### Views/TelemetryDashboard.swift
```swift
import SwiftUI

/// Main telemetry dashboard view (MCT pattern: Dashboard Layout)
public struct TelemetryDashboard: View {
    @StateObject private var store = TelemetryStore.shared
    @State private var selectedPanel: String?
    
    // Configurable layout
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(TelemetryObjectType.allTypes, id: \.id) { objectType in
                    TelemetryPanel(objectType: objectType)
                        .onTapGesture {
                            selectedPanel = objectType.id
                        }
                }
            }
            .padding()
        }
        .background(ZDDesign.darkBackground)
        .sheet(item: $selectedPanel) { panelId in
            if let objectType = TelemetryObjectType.allTypes.first(where: { $0.id == panelId }) {
                TelemetryDetailView(objectType: objectType)
            }
        }
    }
}

extension String: Identifiable {
    public var id: String { self }
}

/// Single telemetry panel
public struct TelemetryPanel: View {
    let objectType: TelemetryObjectType
    @StateObject private var store = TelemetryStore.shared
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: objectType.icon)
                    .foregroundColor(ZDDesign.cyanAccent)
                Text(objectType.name)
                    .font(.headline)
                Spacer()
            }
            
            // Key values
            ForEach(objectType.keys.prefix(3)) { key in
                HStack {
                    Text(key.name)
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                    Spacer()
                    if let datum = store.getValue("\(objectType.id).\(key.id)") {
                        Text(formatValue(datum.value, key: key))
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text("--")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }
    
    private func formatValue(_ value: TelemetryValue, key: TelemetryObjectType.TelemetryKey) -> String {
        var str = value.displayString
        if let unit = key.unit {
            str += " \(unit)"
        }
        return str
    }
}

/// Detailed telemetry view with timeline
public struct TelemetryDetailView: View {
    let objectType: TelemetryObjectType
    @StateObject private var store = TelemetryStore.shared
    @State private var selectedKey: String?
    @State private var historyData: [TelemetryDatum] = []
    
    public var body: some View {
        NavigationView {
            VStack {
                // Key selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(objectType.keys) { key in
                            Button(key.name) {
                                selectedKey = key.id
                                loadHistory(key: key.id)
                            }
                            .buttonStyle(.bordered)
                            .tint(selectedKey == key.id ? ZDDesign.cyanAccent : .gray)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Current value
                if let key = selectedKey,
                   let datum = store.getValue("\(objectType.id).\(key)") {
                    VStack {
                        Text(datum.value.displayString)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                        Text("Current Value")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                    .padding()
                }
                
                // Timeline chart (simplified)
                if !historyData.isEmpty {
                    TelemetryTimelineChart(data: historyData)
                        .frame(height: 200)
                        .padding()
                }
                
                Spacer()
            }
            .navigationTitle(objectType.name)
            .navigationBarTitleDisplayMode(.inline)
            .background(ZDDesign.darkBackground)
        }
        .onAppear {
            if selectedKey == nil {
                selectedKey = objectType.keys.first?.id
                if let key = selectedKey {
                    loadHistory(key: key)
                }
            }
        }
    }
    
    private func loadHistory(key: String) {
        Task {
            historyData = await store.history(key: "\(objectType.id).\(key)", duration: 3600)
        }
    }
}

/// Simple timeline chart for telemetry data
public struct TelemetryTimelineChart: View {
    let data: [TelemetryDatum]
    
    public var body: some View {
        GeometryReader { geometry in
            let values = data.compactMap { $0.value.doubleValue }
            guard !values.isEmpty else {
                return AnyView(Text("No data").foregroundColor(ZDDesign.mediumGray))
            }
            
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 1
            let range = maxVal - minVal == 0 ? 1 : maxVal - minVal
            
            return AnyView(
                Path { path in
                    for (index, datum) in data.enumerated() {
                        guard let value = datum.value.doubleValue else { continue }
                        
                        let x = geometry.size.width * CGFloat(index) / CGFloat(max(1, data.count - 1))
                        let y = geometry.size.height * (1 - CGFloat((value - minVal) / range))
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(ZDDesign.cyanAccent, lineWidth: 2)
            )
        }
    }
}
```

---

## 2. Threat Classification NLP (Boeing SDR-Hazards Pattern)

### Source
- Repository: https://github.com/Boeing/sdr-hazards-classification
- Key Insight: ML models trained on unstructured text classify safety hazards despite typos, abbreviations, and domain jargon

### Purpose
Use Phi-3.5 to classify tactical reports and radio chatter into threat categories for the Intel dashboard.

### File Structure
```
Sources/MLXEdgeLLM/Intelligence/
├── ThreatClassifier/
│   ├── ThreatClassifier.swift       # Main classifier
│   ├── ThreatCategory.swift         # Category definitions
│   └── ThreatReport.swift           # Report data model
```

### Implementation

#### ThreatCategory.swift
```swift
import Foundation
import SwiftUI

/// Threat categories (inspired by Boeing SDR classification)
public enum ThreatCategory: String, Codable, CaseIterable, Identifiable {
    case hostileContact = "HOSTILE_CONTACT"
    case environmentalHazard = "ENVIRONMENTAL_HAZARD"
    case medicalEmergency = "MEDICAL_EMERGENCY"
    case equipmentFailure = "EQUIPMENT_FAILURE"
    case communicationsLoss = "COMMUNICATIONS_LOSS"
    case navigationError = "NAVIGATION_ERROR"
    case securityBreach = "SECURITY_BREACH"
    case resourceShortage = "RESOURCE_SHORTAGE"
    case none = "NONE"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .hostileContact: return "Hostile Contact"
        case .environmentalHazard: return "Environmental Hazard"
        case .medicalEmergency: return "Medical Emergency"
        case .equipmentFailure: return "Equipment Failure"
        case .communicationsLoss: return "Communications Loss"
        case .navigationError: return "Navigation Error"
        case .securityBreach: return "Security Breach"
        case .resourceShortage: return "Resource Shortage"
        case .none: return "No Threat"
        }
    }
    
    public var icon: String {
        switch self {
        case .hostileContact: return "exclamationmark.triangle.fill"
        case .environmentalHazard: return "cloud.bolt.fill"
        case .medicalEmergency: return "cross.fill"
        case .equipmentFailure: return "wrench.fill"
        case .communicationsLoss: return "antenna.radiowaves.left.and.right.slash"
        case .navigationError: return "location.slash.fill"
        case .securityBreach: return "lock.open.fill"
        case .resourceShortage: return "gauge.with.dots.needle.0percent"
        case .none: return "checkmark.shield.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .hostileContact: return .red
        case .environmentalHazard: return .orange
        case .medicalEmergency: return .pink
        case .equipmentFailure: return .yellow
        case .communicationsLoss: return .purple
        case .navigationError: return .blue
        case .securityBreach: return .red
        case .resourceShortage: return .orange
        case .none: return .green
        }
    }
    
    public var priority: Int {
        switch self {
        case .hostileContact: return 10
        case .medicalEmergency: return 9
        case .securityBreach: return 8
        case .environmentalHazard: return 7
        case .communicationsLoss: return 6
        case .equipmentFailure: return 5
        case .navigationError: return 4
        case .resourceShortage: return 3
        case .none: return 0
        }
    }
}
```

#### ThreatReport.swift
```swift
import Foundation
import CoreLocation

/// Classified threat report
public struct ThreatReport: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let rawText: String
    public let category: ThreatCategory
    public let confidence: Double
    public let reasoning: String
    public let source: String           // Who reported (peer ID or "self")
    public let location: CodableCoordinate?
    public var acknowledged: Bool
    public var resolvedAt: Date?
    
    public init(
        rawText: String,
        category: ThreatCategory,
        confidence: Double,
        reasoning: String,
        source: String,
        location: CLLocationCoordinate2D? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.rawText = rawText
        self.category = category
        self.confidence = confidence
        self.reasoning = reasoning
        self.source = source
        self.location = location.map { CodableCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        self.acknowledged = false
        self.resolvedAt = nil
    }
}

struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
```

#### ThreatClassifier.swift
```swift
import Foundation

/// Threat classification using Phi-3.5 (Boeing SDR pattern)
@MainActor
public class ThreatClassifier: ObservableObject {
    public static let shared = ThreatClassifier()
    
    @Published public private(set) var activeThreats: [ThreatReport] = []
    @Published public private(set) var isClassifying = false
    
    private let engine = LocalInferenceEngine.shared
    
    private init() {}
    
    /// Classify a text report into threat category
    public func classify(
        text: String,
        source: String,
        location: CLLocationCoordinate2D? = nil
    ) async -> ThreatReport {
        isClassifying = true
        defer { isClassifying = false }
        
        let prompt = buildClassificationPrompt(text: text)
        
        var response = ""
        
        await engine.generate(prompt: prompt, maxTokens: 200) { token in
            response += token
        } onComplete: {}
        
        // Parse response
        let (category, confidence, reasoning) = parseClassificationResponse(response)
        
        let report = ThreatReport(
            rawText: text,
            category: category,
            confidence: confidence,
            reasoning: reasoning,
            source: source,
            location: location
        )
        
        // Add to active threats if significant
        if category != .none && confidence > 0.5 {
            activeThreats.append(report)
            activeThreats.sort { $0.category.priority > $1.category.priority }
        }
        
        return report
    }
    
    /// Classify incoming mesh message
    public func classifyIncoming(message: String, from peerID: String) async {
        // Skip very short messages
        guard message.count > 10 else { return }
        
        // Don't classify obvious non-threat messages
        let lowercased = message.lowercased()
        let skipPhrases = ["check in", "all clear", "roger", "copy", "affirmative"]
        if skipPhrases.contains(where: { lowercased.contains($0) }) {
            return
        }
        
        let _ = await classify(text: message, source: peerID)
    }
    
    /// Build classification prompt (Boeing SDR pattern: structured prompt)
    private func buildClassificationPrompt(text: String) -> String {
        let categories = ThreatCategory.allCases
            .filter { $0 != .none }
            .map { "- \($0.rawValue): \($0.displayName)" }
            .joined(separator: "\n")
        
        return """
        You are a tactical threat classifier. Analyze the following report and classify it into exactly one threat category.
        
        THREAT CATEGORIES:
        \(categories)
        - NONE: No threat detected
        
        REPORT TEXT:
        "\(text)"
        
        Classify this report. Handle typos, abbreviations, and informal language.
        
        Respond with ONLY a JSON object in this exact format:
        {"category": "<CATEGORY>", "confidence": <0.0-1.0>, "reasoning": "<one sentence>"}
        """
    }
    
    /// Parse Phi-3.5 response into structured data
    private func parseClassificationResponse(_ response: String) -> (ThreatCategory, Double, String) {
        // Extract JSON from response
        guard let jsonStart = response.firstIndex(of: "{"),
              let jsonEnd = response.lastIndex(of: "}") else {
            return (.none, 0.0, "Failed to parse response")
        }
        
        let jsonString = String(response[jsonStart...jsonEnd])
        
        guard let data = jsonString.data(using: .utf8) else {
            return (.none, 0.0, "Invalid JSON encoding")
        }
        
        struct ClassificationResult: Codable {
            let category: String
            let confidence: Double
            let reasoning: String
        }
        
        do {
            let result = try JSONDecoder().decode(ClassificationResult.self, from: data)
            let category = ThreatCategory(rawValue: result.category) ?? .none
            return (category, result.confidence, result.reasoning)
        } catch {
            return (.none, 0.0, "JSON decode error: \(error.localizedDescription)")
        }
    }
    
    /// Acknowledge a threat
    public func acknowledge(_ reportID: UUID) {
        if let index = activeThreats.firstIndex(where: { $0.id == reportID }) {
            activeThreats[index].acknowledged = true
        }
    }
    
    /// Resolve a threat
    public func resolve(_ reportID: UUID) {
        if let index = activeThreats.firstIndex(where: { $0.id == reportID }) {
            activeThreats[index].resolvedAt = Date()
        }
    }
    
    /// Get unacknowledged threats sorted by priority
    public var unacknowledgedThreats: [ThreatReport] {
        activeThreats
            .filter { !$0.acknowledged && $0.resolvedAt == nil }
            .sorted { $0.category.priority > $1.category.priority }
    }
    
    /// Clear resolved threats older than specified duration
    public func pruneResolved(olderThan age: TimeInterval = 3600) {
        let cutoff = Date().addingTimeInterval(-age)
        activeThreats.removeAll {
            guard let resolved = $0.resolvedAt else { return false }
            return resolved < cutoff
        }
    }
}
```

#### ThreatFeedView.swift
```swift
import SwiftUI

/// Threat feed view for Intel tab
public struct ThreatFeedView: View {
    @StateObject private var classifier = ThreatClassifier.shared
    @State private var reportText = ""
    @State private var isSubmitting = false
    
    public var body: some View {
        VStack(spacing: 0) {
            // Active threats list
            if classifier.activeThreats.isEmpty {
                VStack {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("No Active Threats")
                        .font(.headline)
                        .padding(.top)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(classifier.activeThreats) { threat in
                        ThreatRow(threat: threat)
                    }
                }
                .listStyle(.plain)
            }
            
            // Manual report input
            VStack(spacing: 12) {
                TextField("Report threat or observation...", text: $reportText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3)
                
                Button {
                    submitReport()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Label("Classify Report", systemImage: "exclamationmark.bubble.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(reportText.isEmpty || isSubmitting)
            }
            .padding()
            .background(ZDDesign.darkCard)
        }
    }
    
    private func submitReport() {
        isSubmitting = true
        Task {
            let _ = await classifier.classify(
                text: reportText,
                source: "self"
            )
            reportText = ""
            isSubmitting = false
        }
    }
}

struct ThreatRow: View {
    let threat: ThreatReport
    @StateObject private var classifier = ThreatClassifier.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: threat.category.icon)
                .foregroundColor(threat.category.color)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(threat.category.displayName)
                        .font(.headline)
                    Spacer()
                    Text("\(Int(threat.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                }
                
                Text(threat.rawText)
                    .font(.subheadline)
                    .lineLimit(2)
                
                Text(threat.reasoning)
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                
                HStack {
                    Text(threat.source)
                        .font(.caption2)
                    Text("•")
                    Text(threat.timestamp, style: .relative)
                        .font(.caption2)
                    
                    Spacer()
                    
                    if !threat.acknowledged {
                        Button("ACK") {
                            classifier.acknowledge(threat.id)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                    
                    if threat.resolvedAt == nil {
                        Button("Resolve") {
                            classifier.resolve(threat.id)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .opacity(threat.resolvedAt != nil ? 0.5 : 1.0)
    }
}
```

---

## 3. Tactical Map Overlays (DoD ATAK-CIV Pattern)

### Source
- Repository: https://github.com/deptofdefense/AndroidTacticalAssaultKit-CIV (417 stars)
- Used by: US Military for situational awareness
- Key Insight: Standardized tactical overlays (threat zones, team positions, waypoints) on map

### Purpose
Add military-style tactical overlays to the Map tab showing team positions, threat zones, routes, and points of interest.

### File Structure
```
Sources/MLXEdgeLLM/Mapping/
├── Overlays/
│   ├── TacticalOverlay.swift         # Base overlay protocol
│   ├── TeamPositionOverlay.swift     # Team member positions
│   ├── ThreatZoneOverlay.swift       # Threat area circles
│   ├── RouteOverlay.swift            # Navigation routes
│   ├── WaypointOverlay.swift         # Tactical waypoints
│   └── GeofenceOverlay.swift         # Safety zone boundaries
```

### Implementation

#### TacticalOverlay.swift
```swift
import Foundation
import MapKit
import SwiftUI

/// Protocol for tactical map overlays (ATAK pattern)
public protocol TacticalOverlay: MKOverlay {
    var overlayType: TacticalOverlayType { get }
    var createdAt: Date { get }
    var expiresAt: Date? { get }
    var metadata: [String: String] { get }
}

public enum TacticalOverlayType: String {
    case teamPosition
    case threatZone
    case route
    case waypoint
    case geofence
    case searchArea
    case rallyPoint
}

/// Overlay manager for the map
@MainActor
public class TacticalOverlayManager: ObservableObject {
    public static let shared = TacticalOverlayManager()
    
    @Published public private(set) var overlays: [any TacticalOverlay] = []
    @Published public private(set) var annotations: [MKAnnotation] = []
    
    private init() {}
    
    public func add(_ overlay: any TacticalOverlay) {
        overlays.append(overlay)
    }
    
    public func add(_ annotation: MKAnnotation) {
        annotations.append(annotation)
    }
    
    public func remove(ofType type: TacticalOverlayType) {
        overlays.removeAll { $0.overlayType == type }
    }
    
    public func removeExpired() {
        let now = Date()
        overlays.removeAll {
            if let expires = $0.expiresAt {
                return expires < now
            }
            return false
        }
    }
    
    public func clear() {
        overlays.removeAll()
        annotations.removeAll()
    }
}
```

#### TeamPositionOverlay.swift
```swift
import Foundation
import MapKit

/// Team member position annotation (ATAK pattern: Friendly Force Tracking)
public class TeamMemberAnnotation: NSObject, MKAnnotation {
    public let peerID: String
    public let callsign: String
    public dynamic var coordinate: CLLocationCoordinate2D
    public let lastUpdate: Date
    public let heading: Double?
    public let speed: Double?
    public let status: TeamMemberStatus
    
    public var title: String? { callsign }
    public var subtitle: String? {
        let age = Date().timeIntervalSince(lastUpdate)
        if age < 60 {
            return "Active"
        } else if age < 300 {
            return "\(Int(age / 60))m ago"
        } else {
            return "Stale"
        }
    }
    
    public enum TeamMemberStatus: String {
        case active
        case moving
        case stationary
        case alert
        case offline
    }
    
    public init(
        peerID: String,
        callsign: String,
        coordinate: CLLocationCoordinate2D,
        heading: Double? = nil,
        speed: Double? = nil,
        status: TeamMemberStatus = .active
    ) {
        self.peerID = peerID
        self.callsign = callsign
        self.coordinate = coordinate
        self.lastUpdate = Date()
        self.heading = heading
        self.speed = speed
        self.status = status
        super.init()
    }
}

/// Custom annotation view for team members
public class TeamMemberAnnotationView: MKAnnotationView {
    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func setupView() {
        canShowCallout = true
        
        // Create custom view
        let size: CGFloat = 36
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        
        let circle = CAShapeLayer()
        circle.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4)).cgPath
        circle.fillColor = UIColor.systemBlue.cgColor
        circle.strokeColor = UIColor.white.cgColor
        circle.lineWidth = 2
        layer.addSublayer(circle)
        
        // Add direction indicator if heading available
        if let teamAnnotation = annotation as? TeamMemberAnnotation,
           let heading = teamAnnotation.heading {
            addHeadingIndicator(heading: heading)
        }
    }
    
    private func addHeadingIndicator(heading: Double) {
        let indicator = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: bounds.midX, y: 4))
        path.addLine(to: CGPoint(x: bounds.midX - 6, y: 14))
        path.addLine(to: CGPoint(x: bounds.midX + 6, y: 14))
        path.close()
        
        indicator.path = path.cgPath
        indicator.fillColor = UIColor.systemBlue.cgColor
        
        // Rotate to heading
        let radians = heading * .pi / 180
        indicator.transform = CATransform3DMakeRotation(CGFloat(radians), 0, 0, 1)
        
        layer.addSublayer(indicator)
    }
}
```

#### ThreatZoneOverlay.swift
```swift
import Foundation
import MapKit

/// Threat zone circle overlay (ATAK pattern: Hostile Area)
public class ThreatZoneOverlay: MKCircle, TacticalOverlay {
    public let overlayType: TacticalOverlayType = .threatZone
    public let createdAt: Date
    public let expiresAt: Date?
    public let metadata: [String: String]
    
    public let threatLevel: Int  // 1-5
    public let threatType: String
    public let reportedBy: String
    
    public static func create(
        center: CLLocationCoordinate2D,
        radiusMeters: Double,
        threatLevel: Int,
        threatType: String,
        reportedBy: String,
        expiresIn: TimeInterval? = 3600
    ) -> ThreatZoneOverlay {
        let overlay = ThreatZoneOverlay(center: center, radius: radiusMeters)
        overlay.threatLevel = threatLevel
        overlay.threatType = threatType
        overlay.reportedBy = reportedBy
        overlay.createdAt = Date()
        overlay.expiresAt = expiresIn.map { Date().addingTimeInterval($0) }
        overlay.metadata = [
            "threatLevel": "\(threatLevel)",
            "threatType": threatType,
            "reportedBy": reportedBy
        ]
        return overlay
    }
    
    private override init(center coord: CLLocationCoordinate2D, radius: CLLocationDistance) {
        self.createdAt = Date()
        self.expiresAt = nil
        self.metadata = [:]
        self.threatLevel = 1
        self.threatType = ""
        self.reportedBy = ""
        super.init()
    }
}

/// Renderer for threat zones
public class ThreatZoneRenderer: MKCircleRenderer {
    public init(threatZone: ThreatZoneOverlay) {
        super.init(circle: threatZone)
        
        // Color based on threat level
        let alpha: CGFloat = 0.3
        switch threatZone.threatLevel {
        case 5:
            fillColor = UIColor.red.withAlphaComponent(alpha)
            strokeColor = .red
        case 4:
            fillColor = UIColor.orange.withAlphaComponent(alpha)
            strokeColor = .orange
        case 3:
            fillColor = UIColor.yellow.withAlphaComponent(alpha)
            strokeColor = .yellow
        case 2:
            fillColor = UIColor.blue.withAlphaComponent(alpha)
            strokeColor = .blue
        default:
            fillColor = UIColor.gray.withAlphaComponent(alpha)
            strokeColor = .gray
        }
        
        lineWidth = 2
        lineDashPattern = [10, 5]  // Dashed border
    }
}
```

#### RouteOverlay.swift
```swift
import Foundation
import MapKit

/// Tactical route overlay (ATAK pattern: Route/Path)
public class TacticalRouteOverlay: MKPolyline, TacticalOverlay {
    public let overlayType: TacticalOverlayType = .route
    public let createdAt: Date
    public let expiresAt: Date?
    public let metadata: [String: String]
    
    public let routeType: RouteType
    public let routeName: String
    
    public enum RouteType: String {
        case primary       // Main route
        case alternate     // Backup route
        case emergency     // Emergency egress
        case patrol        // Patrol pattern
    }
    
    public static func create(
        coordinates: [CLLocationCoordinate2D],
        routeType: RouteType,
        name: String
    ) -> TacticalRouteOverlay {
        let overlay = TacticalRouteOverlay(coordinates: coordinates, count: coordinates.count)
        overlay.routeType = routeType
        overlay.routeName = name
        overlay.createdAt = Date()
        return overlay
    }
    
    private override init() {
        self.createdAt = Date()
        self.expiresAt = nil
        self.metadata = [:]
        self.routeType = .primary
        self.routeName = ""
        super.init()
    }
}

/// Renderer for tactical routes
public class TacticalRouteRenderer: MKPolylineRenderer {
    public init(route: TacticalRouteOverlay) {
        super.init(polyline: route)
        
        switch route.routeType {
        case .primary:
            strokeColor = .systemBlue
            lineWidth = 4
        case .alternate:
            strokeColor = .systemGreen
            lineWidth = 3
            lineDashPattern = [15, 10]
        case .emergency:
            strokeColor = .systemRed
            lineWidth = 4
            lineDashPattern = [5, 5]
        case .patrol:
            strokeColor = .systemOrange
            lineWidth = 3
            lineDashPattern = [20, 10, 5, 10]
        }
    }
}
```

#### WaypointOverlay.swift
```swift
import Foundation
import MapKit

/// Tactical waypoint annotation (ATAK pattern: Point of Interest)
public class TacticalWaypointAnnotation: NSObject, MKAnnotation {
    public let id: UUID
    public let coordinate: CLLocationCoordinate2D
    public let waypointType: WaypointType
    public let name: String
    public let notes: String?
    public let createdAt: Date
    public let createdBy: String
    
    public var title: String? { name }
    public var subtitle: String? { waypointType.displayName }
    
    public enum WaypointType: String, CaseIterable {
        case objective       // Mission objective
        case rallyPoint     // Team rally point
        case checkpoint     // Route checkpoint
        case observation    // Observation post
        case hazard         // Hazard marker
        case cache          // Supply cache
        case extraction     // Extraction point
        case interest       // Point of interest
        
        var displayName: String {
            switch self {
            case .objective: return "Objective"
            case .rallyPoint: return "Rally Point"
            case .checkpoint: return "Checkpoint"
            case .observation: return "Observation Post"
            case .hazard: return "Hazard"
            case .cache: return "Supply Cache"
            case .extraction: return "Extraction Point"
            case .interest: return "Point of Interest"
            }
        }
        
        var icon: String {
            switch self {
            case .objective: return "star.fill"
            case .rallyPoint: return "flag.fill"
            case .checkpoint: return "mappin.circle.fill"
            case .observation: return "eye.fill"
            case .hazard: return "exclamationmark.triangle.fill"
            case .cache: return "shippingbox.fill"
            case .extraction: return "arrow.up.circle.fill"
            case .interest: return "mappin"
            }
        }
        
        var color: UIColor {
            switch self {
            case .objective: return .systemYellow
            case .rallyPoint: return .systemGreen
            case .checkpoint: return .systemBlue
            case .observation: return .systemPurple
            case .hazard: return .systemRed
            case .cache: return .systemOrange
            case .extraction: return .systemTeal
            case .interest: return .systemGray
            }
        }
    }
    
    public init(
        coordinate: CLLocationCoordinate2D,
        type: WaypointType,
        name: String,
        notes: String? = nil,
        createdBy: String = "self"
    ) {
        self.id = UUID()
        self.coordinate = coordinate
        self.waypointType = type
        self.name = name
        self.notes = notes
        self.createdAt = Date()
        self.createdBy = createdBy
        super.init()
    }
}

/// Custom annotation view for waypoints
public class TacticalWaypointView: MKAnnotationView {
    private let iconView = UIImageView()
    
    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func setupView() {
        canShowCallout = true
        
        frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        
        iconView.frame = bounds
        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
        
        updateAppearance()
    }
    
    public override var annotation: MKAnnotation? {
        didSet {
            updateAppearance()
        }
    }
    
    private func updateAppearance() {
        guard let waypoint = annotation as? TacticalWaypointAnnotation else { return }
        
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)
        let image = UIImage(systemName: waypoint.waypointType.icon, withConfiguration: config)?
            .withTintColor(waypoint.waypointType.color, renderingMode: .alwaysOriginal)
        iconView.image = image
        
        // Add background circle
        backgroundColor = waypoint.waypointType.color.withAlphaComponent(0.2)
        layer.cornerRadius = 16
    }
}
```

#### TacticalMapView.swift (Updated)
```swift
import SwiftUI
import MapKit

/// Tactical map view with overlays (ATAK pattern)
public struct TacticalMapView: UIViewRepresentable {
    @StateObject private var overlayManager = TacticalOverlayManager.shared
    @Binding var region: MKCoordinateRegion
    
    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .hybrid  // Satellite with labels
        mapView.setRegion(region, animated: false)
        
        // Register annotation views
        mapView.register(TeamMemberAnnotationView.self, forAnnotationViewWithReuseIdentifier: "TeamMember")
        mapView.register(TacticalWaypointView.self, forAnnotationViewWithReuseIdentifier: "Waypoint")
        
        return mapView
    }
    
    public func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update overlays
        mapView.removeOverlays(mapView.overlays)
        for overlay in overlayManager.overlays {
            mapView.addOverlay(overlay as! MKOverlay)
        }
        
        // Update annotations (except user location)
        let currentAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(currentAnnotations)
        mapView.addAnnotations(overlayManager.annotations)
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TacticalMapView
        
        init(_ parent: TacticalMapView) {
            self.parent = parent
        }
        
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let threatZone = overlay as? ThreatZoneOverlay {
                return ThreatZoneRenderer(threatZone: threatZone)
            }
            if let route = overlay as? TacticalRouteOverlay {
                return TacticalRouteRenderer(route: route)
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.blue.withAlphaComponent(0.1)
                renderer.strokeColor = .blue
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil  // Use default
            }
            
            if let teamMember = annotation as? TeamMemberAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: "TeamMember", for: teamMember)
            }
            
            if let waypoint = annotation as? TacticalWaypointAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: "Waypoint", for: waypoint)
            }
            
            return nil
        }
    }
}
```

---

## 4. Geofencing Safety Zones (NASA ICAROUS Pattern)

### Source
- Repository: https://github.com/nasa/icarous (174 stars)
- Contains: DAIDALUS (Detect and Avoid) + PolyCARP (Polygon Containment)
- Key Insight: Formally verified geofencing algorithms for safety-critical applications

### Purpose
Define operational boundaries and alert when user approaches or exits safety zones.

### File Structure
```
Sources/MLXEdgeLLM/SecurityLayer/
├── Geofencing/
│   ├── Geofence.swift               # Geofence data model
│   ├── GeofenceManager.swift        # Core logic
│   ├── GeofenceMonitor.swift        # Background monitoring
│   └── GeofenceAlertView.swift      # UI alerts
```

### Implementation

#### Geofence.swift
```swift
import Foundation
import CoreLocation
import MapKit

/// Geofence definition (ICAROUS PolyCARP pattern)
public struct Geofence: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let type: GeofenceType
    public let geometry: GeofenceGeometry
    public let behavior: GeofenceBehavior
    public let isActive: Bool
    public let createdAt: Date
    public let metadata: [String: String]
    
    public enum GeofenceType: String, Codable {
        case keepIn      // Must stay inside (ICAROUS: inclusion zone)
        case keepOut     // Must stay outside (ICAROUS: exclusion zone)
        case alert       // Alert when crossing (no restriction)
    }
    
    public enum GeofenceBehavior: String, Codable {
        case hard        // Strict boundary - immediate alert
        case soft        // Warning zone - buffer alert
        case advisory    // Information only
    }
    
    public init(
        name: String,
        type: GeofenceType,
        geometry: GeofenceGeometry,
        behavior: GeofenceBehavior = .hard,
        metadata: [String: String] = [:]
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.geometry = geometry
        self.behavior = behavior
        self.isActive = true
        self.createdAt = Date()
        self.metadata = metadata
    }
}

/// Geofence geometry types
public enum GeofenceGeometry: Codable {
    case circle(center: CodableCoordinate, radiusMeters: Double)
    case polygon(vertices: [CodableCoordinate])
    case corridor(path: [CodableCoordinate], widthMeters: Double)
    
    /// Check if a point is inside the geometry
    public func contains(_ point: CLLocationCoordinate2D) -> Bool {
        switch self {
        case .circle(let center, let radius):
            let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let pointLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
            return pointLoc.distance(from: centerLoc) <= radius
            
        case .polygon(let vertices):
            return pointInPolygon(point, vertices: vertices.map { $0.clLocation })
            
        case .corridor(let path, let width):
            return pointInCorridor(point, path: path.map { $0.clLocation }, width: width)
        }
    }
    
    /// Get distance to boundary (negative if inside, positive if outside)
    public func distanceToBoundary(_ point: CLLocationCoordinate2D) -> Double {
        switch self {
        case .circle(let center, let radius):
            let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let pointLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
            return pointLoc.distance(from: centerLoc) - radius
            
        case .polygon(let vertices):
            return distanceToPolygonBoundary(point, vertices: vertices.map { $0.clLocation })
            
        case .corridor(let path, let width):
            return distanceToCorridorBoundary(point, path: path.map { $0.clLocation }, width: width)
        }
    }
    
    // MARK: - Geometry Helpers (PolyCARP inspired)
    
    private func pointInPolygon(_ point: CLLocationCoordinate2D, vertices: [CLLocationCoordinate2D]) -> Bool {
        // Ray casting algorithm
        var inside = false
        var j = vertices.count - 1
        
        for i in 0..<vertices.count {
            let vi = vertices[i]
            let vj = vertices[j]
            
            if ((vi.longitude > point.longitude) != (vj.longitude > point.longitude)) &&
                (point.latitude < (vj.latitude - vi.latitude) * (point.longitude - vi.longitude) / (vj.longitude - vi.longitude) + vi.latitude) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }
    
    private func distanceToPolygonBoundary(_ point: CLLocationCoordinate2D, vertices: [CLLocationCoordinate2D]) -> Double {
        var minDistance = Double.infinity
        let pointLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
        
        for i in 0..<vertices.count {
            let j = (i + 1) % vertices.count
            let segmentDist = distanceToLineSegment(
                point: pointLoc,
                start: CLLocation(latitude: vertices[i].latitude, longitude: vertices[i].longitude),
                end: CLLocation(latitude: vertices[j].latitude, longitude: vertices[j].longitude)
            )
            minDistance = min(minDistance, segmentDist)
        }
        
        let isInside = pointInPolygon(point, vertices: vertices)
        return isInside ? -minDistance : minDistance
    }
    
    private func distanceToLineSegment(point: CLLocation, start: CLLocation, end: CLLocation) -> Double {
        let px = point.coordinate.latitude
        let py = point.coordinate.longitude
        let ax = start.coordinate.latitude
        let ay = start.coordinate.longitude
        let bx = end.coordinate.latitude
        let by = end.coordinate.longitude
        
        let dx = bx - ax
        let dy = by - ay
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        
        let nearestLat = ax + t * dx
        let nearestLon = ay + t * dy
        let nearest = CLLocation(latitude: nearestLat, longitude: nearestLon)
        
        return point.distance(from: nearest)
    }
    
    private func pointInCorridor(_ point: CLLocationCoordinate2D, path: [CLLocationCoordinate2D], width: Double) -> Bool {
        let pointLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let halfWidth = width / 2
        
        for i in 0..<(path.count - 1) {
            let segmentDist = distanceToLineSegment(
                point: pointLoc,
                start: CLLocation(latitude: path[i].latitude, longitude: path[i].longitude),
                end: CLLocation(latitude: path[i+1].latitude, longitude: path[i+1].longitude)
            )
            if segmentDist <= halfWidth {
                return true
            }
        }
        
        return false
    }
    
    private func distanceToCorridorBoundary(_ point: CLLocationCoordinate2D, path: [CLLocationCoordinate2D], width: Double) -> Double {
        let pointLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let halfWidth = width / 2
        var minDistToPath = Double.infinity
        
        for i in 0..<(path.count - 1) {
            let segmentDist = distanceToLineSegment(
                point: pointLoc,
                start: CLLocation(latitude: path[i].latitude, longitude: path[i].longitude),
                end: CLLocation(latitude: path[i+1].latitude, longitude: path[i+1].longitude)
            )
            minDistToPath = min(minDistToPath, segmentDist)
        }
        
        return minDistToPath - halfWidth
    }
}
```

#### GeofenceManager.swift
```swift
import Foundation
import CoreLocation
import Combine

/// Geofence manager (ICAROUS pattern)
@MainActor
public class GeofenceManager: ObservableObject {
    public static let shared = GeofenceManager()
    
    @Published public private(set) var geofences: [Geofence] = []
    @Published public private(set) var violations: [GeofenceViolation] = []
    @Published public private(set) var currentStatus: GeofenceStatus = .safe
    
    private let storage = GeofenceStorage()
    
    public enum GeofenceStatus: String {
        case safe           // Within all keepIn zones, outside all keepOut zones
        case warning        // Approaching boundary
        case violation      // Outside keepIn or inside keepOut
    }
    
    private init() {
        loadGeofences()
    }
    
    // MARK: - CRUD Operations
    
    public func add(_ geofence: Geofence) {
        geofences.append(geofence)
        saveGeofences()
    }
    
    public func remove(_ geofenceID: UUID) {
        geofences.removeAll { $0.id == geofenceID }
        saveGeofences()
    }
    
    public func update(_ geofence: Geofence) {
        if let index = geofences.firstIndex(where: { $0.id == geofence.id }) {
            geofences[index] = geofence
            saveGeofences()
        }
    }
    
    // MARK: - Status Checking
    
    /// Check current position against all geofences
    public func checkPosition(_ position: CLLocationCoordinate2D) -> [GeofenceViolation] {
        var newViolations: [GeofenceViolation] = []
        var overallStatus: GeofenceStatus = .safe
        
        for geofence in geofences where geofence.isActive {
            let isInside = geofence.geometry.contains(position)
            let distanceToBoundary = geofence.geometry.distanceToBoundary(position)
            
            // Check for violations based on geofence type
            var violationType: GeofenceViolation.ViolationType?
            
            switch geofence.type {
            case .keepIn:
                if !isInside {
                    violationType = .exitedKeepIn
                    overallStatus = .violation
                } else if distanceToBoundary > -100 {  // Within 100m of boundary
                    overallStatus = max(overallStatus, .warning)
                }
                
            case .keepOut:
                if isInside {
                    violationType = .enteredKeepOut
                    overallStatus = .violation
                } else if distanceToBoundary < 100 {  // Within 100m of boundary
                    overallStatus = max(overallStatus, .warning)
                }
                
            case .alert:
                // Just notify on crossing, no violation
                break
            }
            
            if let type = violationType {
                let violation = GeofenceViolation(
                    geofenceID: geofence.id,
                    geofenceName: geofence.name,
                    type: type,
                    position: position,
                    distanceToBoundary: distanceToBoundary
                )
                newViolations.append(violation)
            }
        }
        
        violations = newViolations
        currentStatus = overallStatus
        
        return newViolations
    }
    
    /// Get nearest boundary distance (for UI display)
    public func nearestBoundaryDistance(_ position: CLLocationCoordinate2D) -> (Geofence, Double)? {
        var nearest: (Geofence, Double)?
        
        for geofence in geofences where geofence.isActive {
            let distance = abs(geofence.geometry.distanceToBoundary(position))
            if nearest == nil || distance < abs(nearest!.1) {
                nearest = (geofence, geofence.geometry.distanceToBoundary(position))
            }
        }
        
        return nearest
    }
    
    // MARK: - Persistence
    
    private func loadGeofences() {
        geofences = storage.load()
    }
    
    private func saveGeofences() {
        storage.save(geofences)
    }
}

// Helper for status comparison
extension GeofenceManager.GeofenceStatus: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.safe, .warning, .violation]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Geofence violation record
public struct GeofenceViolation: Identifiable {
    public let id = UUID()
    public let geofenceID: UUID
    public let geofenceName: String
    public let type: ViolationType
    public let position: CLLocationCoordinate2D
    public let distanceToBoundary: Double
    public let timestamp = Date()
    
    public enum ViolationType: String {
        case exitedKeepIn = "Exited safe zone"
        case enteredKeepOut = "Entered restricted zone"
        case approachingBoundary = "Approaching boundary"
    }
}

/// Storage for geofences
class GeofenceStorage {
    private let fileURL: URL
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("geofences.json")
    }
    
    func load() -> [Geofence] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Geofence].self, from: data)) ?? []
    }
    
    func save(_ geofences: [Geofence]) {
        guard let data = try? JSONEncoder().encode(geofences) else { return }
        try? data.write(to: fileURL)
    }
}
```

#### GeofenceMonitor.swift
```swift
import Foundation
import CoreLocation
import Combine

/// Background geofence monitoring (ICAROUS DAIDALUS pattern)
@MainActor
public class GeofenceMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = GeofenceMonitor()
    
    @Published public private(set) var isMonitoring = false
    @Published public private(set) var lastCheck: Date?
    @Published public private(set) var lastViolations: [GeofenceViolation] = []
    
    private let locationManager = CLLocationManager()
    private let geofenceManager = GeofenceManager.shared
    private var warningThreshold: Double = 100  // Meters
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    public func start() {
        guard !isMonitoring else { return }
        
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        isMonitoring = true
        
        print("[GeofenceMonitor] Started monitoring")
    }
    
    public func stop() {
        locationManager.stopUpdatingLocation()
        isMonitoring = false
        print("[GeofenceMonitor] Stopped monitoring")
    }
    
    public func setWarningThreshold(_ meters: Double) {
        warningThreshold = meters
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        lastCheck = Date()
        lastViolations = geofenceManager.checkPosition(location.coordinate)
        
        // Trigger alerts for violations
        for violation in lastViolations {
            handleViolation(violation)
        }
        
        // Check for warnings (approaching boundary)
        if let (fence, distance) = geofenceManager.nearestBoundaryDistance(location.coordinate) {
            if abs(distance) < warningThreshold && abs(distance) > 0 {
                handleWarning(fence: fence, distance: distance)
            }
        }
    }
    
    private func handleViolation(_ violation: GeofenceViolation) {
        // Integration point: HapticComms alert
        // HapticComms.shared.send(.danger, to: "all")
        
        // Integration point: RuntimeSafetyMonitor
        // This will be picked up by the withinGeofence property check
        
        print("[GeofenceMonitor] VIOLATION: \(violation.geofenceName) - \(violation.type.rawValue)")
        
        // Trigger haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    private func handleWarning(fence: Geofence, distance: Double) {
        print("[GeofenceMonitor] WARNING: \(Int(abs(distance)))m from \(fence.name) boundary")
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
}
```

#### GeofenceEditorView.swift
```swift
import SwiftUI
import MapKit

/// Geofence editor view
public struct GeofenceEditorView: View {
    @StateObject private var manager = GeofenceManager.shared
    @State private var showingAddSheet = false
    @State private var selectedGeofence: Geofence?
    
    public var body: some View {
        List {
            Section {
                ForEach(manager.geofences) { geofence in
                    GeofenceRow(geofence: geofence)
                        .onTapGesture {
                            selectedGeofence = geofence
                        }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        manager.remove(manager.geofences[index].id)
                    }
                }
            } header: {
                HStack {
                    Text("Geofences")
                    Spacer()
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            
            Section {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(manager.currentStatus == .safe ? .green : 
                                        manager.currentStatus == .warning ? .yellow : .red)
                    Text("Status: \(manager.currentStatus.rawValue.capitalized)")
                }
                
                if !manager.violations.isEmpty {
                    ForEach(manager.violations) { violation in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text(violation.geofenceName)
                                    .font(.headline)
                                Text(violation.type.rawValue)
                                    .font(.caption)
                            }
                        }
                    }
                }
            } header: {
                Text("Current Status")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddGeofenceView()
        }
    }
}

struct GeofenceRow: View {
    let geofence: Geofence
    
    var body: some View {
        HStack {
            Image(systemName: geofence.type == .keepIn ? "checkmark.circle.fill" : 
                             geofence.type == .keepOut ? "xmark.circle.fill" : "bell.circle.fill")
                .foregroundColor(geofence.type == .keepIn ? .green : 
                                geofence.type == .keepOut ? .red : .orange)
            
            VStack(alignment: .leading) {
                Text(geofence.name)
                    .font(.headline)
                Text(geofence.type.rawValue.replacingOccurrences(of: "keep", with: "Keep ").capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if geofence.isActive {
                Image(systemName: "checkmark")
                    .foregroundColor(.green)
            }
        }
    }
}

struct AddGeofenceView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = GeofenceManager.shared
    
    @State private var name = ""
    @State private var type: Geofence.GeofenceType = .keepIn
    @State private var radiusMeters: Double = 500
    @State private var centerCoordinate = CLLocationCoordinate2D(latitude: 29.4241, longitude: -98.4936)
    
    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    
                    Picker("Type", selection: $type) {
                        Text("Keep In (Safe Zone)").tag(Geofence.GeofenceType.keepIn)
                        Text("Keep Out (Restricted)").tag(Geofence.GeofenceType.keepOut)
                        Text("Alert Only").tag(Geofence.GeofenceType.alert)
                    }
                }
                
                Section("Geometry") {
                    HStack {
                        Text("Radius")
                        Spacer()
                        Text("\(Int(radiusMeters))m")
                    }
                    Slider(value: $radiusMeters, in: 50...5000, step: 50)
                }
                
                Section("Center Point") {
                    Text("Lat: \(String(format: "%.6f", centerCoordinate.latitude))")
                    Text("Lon: \(String(format: "%.6f", centerCoordinate.longitude))")
                    
                    Button("Use Current Location") {
                        // Integration point: LocationManager
                        // centerCoordinate = LocationManager.shared.current
                    }
                }
            }
            .navigationTitle("Add Geofence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let geometry = GeofenceGeometry.circle(
                            center: CodableCoordinate(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude),
                            radiusMeters: radiusMeters
                        )
                        let geofence = Geofence(name: name, type: type, geometry: geometry)
                        manager.add(geofence)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
```

---

## Integration

### Updated Intel Tab

Replace `IntelTabView.swift` content:

```swift
import SwiftUI

public struct IntelTabView: View {
    @State private var selectedSection: IntelSection = .dashboard
    
    enum IntelSection: String, CaseIterable {
        case dashboard = "Dashboard"
        case threats = "Threats"
        case telemetry = "Telemetry"
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Section picker
                Picker("Section", selection: $selectedSection) {
                    ForEach(IntelSection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                switch selectedSection {
                case .dashboard:
                    TelemetryDashboard()
                case .threats:
                    ThreatFeedView()
                case .telemetry:
                    TelemetryDetailList()
                }
            }
            .navigationTitle("Intel")
            .background(ZDDesign.darkBackground)
        }
    }
}

struct TelemetryDetailList: View {
    var body: some View {
        List(TelemetryObjectType.allTypes, id: \.id) { objectType in
            NavigationLink {
                TelemetryDetailView(objectType: objectType)
            } label: {
                Label(objectType.name, systemImage: objectType.icon)
            }
        }
        .listStyle(.plain)
    }
}
```

### App Startup

Add to `ContentView.swift` task:

```swift
.task {
    // Existing...
    
    // Phase 2: Start telemetry and monitoring
    TelemetryStore.shared  // Initialize adapters
    GeofenceMonitor.shared.start()
}
```

---

## Testing

```swift
// TelemetryTests.swift
import XCTest
@testable import MLXEdgeLLM

final class TelemetryTests: XCTestCase {
    func testTelemetryStore() async {
        let store = TelemetryStore.shared
        
        // Wait for initial data
        try? await Task.sleep(for: .seconds(2))
        
        // Should have battery data
        XCTAssertNotNil(store.getValue("battery.level"))
    }
}

// ThreatClassifierTests.swift
final class ThreatClassifierTests: XCTestCase {
    func testClassification() async {
        let classifier = ThreatClassifier.shared
        
        let report = await classifier.classify(
            text: "Spotted unknown vehicle approaching from the north, looks hostile",
            source: "test"
        )
        
        XCTAssertEqual(report.category, .hostileContact)
        XCTAssertGreaterThan(report.confidence, 0.5)
    }
}

// GeofenceTests.swift
final class GeofenceTests: XCTestCase {
    func testPointInCircle() {
        let geometry = GeofenceGeometry.circle(
            center: CodableCoordinate(latitude: 29.4241, longitude: -98.4936),
            radiusMeters: 1000
        )
        
        // Point at center should be inside
        let inside = geometry.contains(CLLocationCoordinate2D(latitude: 29.4241, longitude: -98.4936))
        XCTAssertTrue(inside)
        
        // Point far away should be outside
        let outside = geometry.contains(CLLocationCoordinate2D(latitude: 30.0, longitude: -98.0))
        XCTAssertFalse(outside)
    }
    
    func testDistanceToBoundary() {
        let geometry = GeofenceGeometry.circle(
            center: CodableCoordinate(latitude: 29.4241, longitude: -98.4936),
            radiusMeters: 1000
        )
        
        // Point at center should have negative distance (inside)
        let centerDistance = geometry.distanceToBoundary(CLLocationCoordinate2D(latitude: 29.4241, longitude: -98.4936))
        XCTAssertLessThan(centerDistance, 0)
        XCTAssertEqual(centerDistance, -1000, accuracy: 1)
    }
}
```

---

## Summary

Phase 2 adds four intelligence capabilities:

| System | Source | New Files | Lines |
|--------|--------|-----------|-------|
| Telemetry Dashboard | NASA Open MCT | 12 | ~800 |
| Threat Classification | Boeing SDR | 4 | ~400 |
| Tactical Overlays | DoD ATAK | 6 | ~600 |
| Geofencing | NASA ICAROUS | 5 | ~500 |
| **Total** | | **27** | **~2,300** |

**Dependencies:** None (uses MapKit, CoreLocation, UIKit)

All patterns copied from production NASA, DoD, and Boeing systems.
