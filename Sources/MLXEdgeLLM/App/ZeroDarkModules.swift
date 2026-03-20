//
//  ZeroDarkModules.swift
//  ZeroDark
//
//  Tactical Navigation & Sensing Modules
//

import SwiftUI
import CoreLocation
import MapKit
import Charts
import Combine

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: MODULE 1: OFFLINE NAVIGATION & RECONNAISSANCE
// MARK: Navigate and gather spatial intelligence without detection
// MARK: ═══════════════════════════════════════════════════════════════════

public struct NavigationModule: View {
    @StateObject private var viewModel = NavigationViewModel()
    @StateObject private var locationManager = NavigationLocationManager()
    @State private var showingReconMode = false
    @State private var showDownloadSheet = false
    @State private var showTeamMap = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showElevationProfile = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                // Offline-capable MapKit view with MBTiles/PMTiles support
                OfflineMapView(
                    region: Binding.constant(mapRegion),
                    showsUserLocation: true,
                    waypoints: viewModel.waypoints
                )
                
                // Status indicator (top-left)
                VStack {
                    HStack {
                        MapStatusOverlay()
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }

                // Bottom controls
                VStack(alignment: .trailing, spacing: 12) {
                    Spacer()
                    controlsOverlay
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Navigation")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Download Region", systemImage: "arrow.down.circle") {
                            showDownloadSheet = true
                        }
                        Button("Manage Maps", systemImage: "map") {
                            viewModel.showStoredRegions()
                        }
                        Button("Elevation Profile", systemImage: "chart.line.uptrend.xyaxis") {
                            showElevationProfile = true
                        }
                        Divider()
                        Button("TAK Team Overlay", systemImage: "person.2.circle.fill") {
                            showTeamMap = true
                        }
                        Divider()
                        Button("Silent Recon Mode", systemImage: "eye.slash") {
                            showingReconMode = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.cyan)
                    }
                }
            }
            .sheet(isPresented: $showDownloadSheet) {
                DownloadMapSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showElevationProfile) {
                ElevationProfileView(viewModel: viewModel)
            }
            .sheet(isPresented: $showTeamMap) {
                TeamMapView()
            }
            .sheet(isPresented: $showingReconMode) {
                ReconModeView()
            }
        }
        .onAppear {
            locationManager.requestLocationAccess()
        }
    }

    private var mapRegion: MKCoordinateRegion? {
        if let location = locationManager.currentLocation {
            return MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        return nil
    }

    private var placeholderMapView: some View {
        ZStack {
            Color(white: 0.1)

            VStack(spacing: 16) {
                Image(systemName: "map")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)

                Text("Offline Maps")
                    .font(.title2)
                    .foregroundColor(.white)

                Text("Waiting for location...")
                    .font(.caption)
                    .foregroundColor(.gray)

                Button {
                    showDownloadSheet = true
                } label: {
                    Label("Download Region", systemImage: "arrow.down.circle")
                        .padding()
                        .background(Color.cyan.opacity(0.2))
                        .foregroundColor(.cyan)
                        .cornerRadius(12)
                }
            }
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 12) {
            // Waypoint button
            Button {
                viewModel.markWaypoint(at: locationManager.currentLocation?.coordinate)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title2)
                    Text("Waypoint")
                        .font(.caption2)
                }
                .foregroundColor(.cyan)
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
            }
            .disabled(locationManager.currentLocation == nil)

            // LiDAR Scan button
            Button {
                viewModel.startLiDARScan()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "viewfinder")
                        .font(.title2)
                    Text("3D Scan")
                        .font(.caption2)
                }
                .foregroundColor(.green)
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
            }

            // Perimeter button
            Button {
                viewModel.scanPerimeter()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "circle.dashed")
                        .font(.title2)
                    Text("Perimeter")
                        .font(.caption2)
                }
                .foregroundColor(.orange)
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
            }
        }
    }
}

@MainActor
class NavigationViewModel: ObservableObject {
    @Published var waypoints: [Waypoint] = []
    @Published var isScanning = false
    @Published var downloadProgress: Double = 0
    @Published var mapOverlay: OfflineMBTilesOverlay?
    @Published var storedRegions: [MapRegion] = []
    @Published var elevationProfile: [ElevationPoint] = []
    @Published var selectedRegion: String = "default"

    private let mapEngine = MBTilesStore.shared
    private let terrainEngine = TerrainEngine.shared

    func downloadRegion(boundingBox: MKCoordinateRegion, maxZoom: Int) {
        Task {
            do {
                try await mapEngine.downloadRegion(
                    boundingBox: boundingBox,
                    maxZoom: maxZoom,
                    regionName: selectedRegion,
                    progress: { progress in
                        DispatchQueue.main.async {
                            self.downloadProgress = progress
                        }
                    }
                )
                mapOverlay = OfflineMBTilesOverlay(regionName: selectedRegion)
                loadStoredRegions()
            } catch {
                print("Download error: \(error)")
            }
        }
    }

    func markWaypoint(at coordinate: CLLocationCoordinate2D?) {
        guard let coordinate = coordinate else { return }

        let waypoint = Waypoint(
            name: "Waypoint \(waypoints.count + 1)",
            coordinate: coordinate,
            altitude: 0,
            timestamp: Date(),
            lidarFingerprint: nil
        )
        waypoints.append(waypoint)
    }

    func startLiDARScan() {
        guard LiDARCaptureEngine.shared.isLiDARAvailable else {
            isScanning = false
            print("[Navigation] LiDAR not available on this device")
            return
        }
        isScanning = true
        Task {
            do {
                try await LiDARCaptureEngine.shared.startScan()
                isScanning = false
            } catch {
                isScanning = false
                print("[Navigation] LiDAR scan error: \(error)")
            }
        }
    }

    func scanPerimeter() {
        // Use LiDAR for perimeter mapping
        print("Scanning perimeter...")
    }

    func calculateElevationProfile(route: [CLLocationCoordinate2D]) {
        elevationProfile = terrainEngine.elevationProfile(route: route)
    }

    func loadStoredRegions() {
        storedRegions = mapEngine.storedRegions()
    }

    func showStoredRegions() {
        loadStoredRegions()
    }
}

struct Waypoint: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let altitude: Double
    let timestamp: Date
    let lidarFingerprint: Data? // 3D spatial fingerprint
}

struct DownloadMapSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: NavigationViewModel
    @State private var selectedZoom = 15
    @State private var isDownloading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Region Name") {
                    TextField("e.g., Downtown", text: $viewModel.selectedRegion)
                }

                Section("Zoom Level") {
                    Slider(value: Binding(get: { Double(selectedZoom) }, set: { selectedZoom = Int($0) }), in: 10...18, step: 1)
                    Text("Level \(selectedZoom) - \(zoomDescription)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Section {
                    if isDownloading {
                        ProgressView(value: viewModel.downloadProgress)
                        Text("\(Int(viewModel.downloadProgress * 100))%")
                            .font(.caption)
                    } else {
                        Button("Download Current Region") {
                            isDownloading = true
                            let region = MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                            )
                            viewModel.downloadRegion(boundingBox: region, maxZoom: selectedZoom)
                        }
                        .disabled(viewModel.selectedRegion.isEmpty)
                    }
                }
            }
            .navigationTitle("Download Map")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var zoomDescription: String {
        switch selectedZoom {
        case 10...12: return "City/Region"
        case 13...15: return "Area/Neighborhood"
        case 16...17: return "Street level"
        default: return "Detailed"
        }
    }
}

struct ElevationProfileView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: NavigationViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.elevationProfile.isEmpty {
                    VStack {
                        Text("No elevation data")
                            .foregroundColor(.gray)
                    }
                } else {
                    Chart(viewModel.elevationProfile) { point in
                        AreaMark(
                            x: .value("Distance", point.distance),
                            y: .value("Elevation", point.elevation)
                        )
                        .foregroundStyle(Color.cyan.opacity(0.3))

                        LineMark(
                            x: .value("Distance", point.distance),
                            y: .value("Elevation", point.elevation)
                        )
                        .foregroundStyle(.cyan)
                    }
                    .padding()
                }
            }
            .navigationTitle("Elevation Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

@MainActor
final class NavigationLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NavigationLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse {
                self.startUpdatingLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}

struct ReconModeView: View {
    @Environment(\.dismiss) var dismiss
    @State private var isActive = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Status
                VStack(spacing: 8) {
                    Image(systemName: isActive ? "eye.slash.fill" : "eye.slash")
                        .font(.system(size: 60))
                        .foregroundColor(isActive ? .green : .gray)

                    Text(isActive ? "RECON ACTIVE" : "RECON STANDBY")
                        .font(.headline)
                        .foregroundColor(isActive ? .green : .gray)
                }
                .padding(.top, 40)

                // Stats
                if isActive {
                    reconStats
                }

                Spacer()

                // Controls
                Button {
                    isActive.toggle()
                } label: {
                    Text(isActive ? "Stop Recon" : "Start Silent Recon")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isActive ? Color.red : Color.cyan)
                        .cornerRadius(12)
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Silent Recon")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var reconStats: some View {
        VStack(spacing: 16) {
            HStack {
                ReconStatBox(title: "Scans", value: "15", color: .cyan)
                ReconStatBox(title: "Structures", value: "3", color: .orange)
                ReconStatBox(title: "Contacts", value: "0", color: .green)
            }

            HStack {
                ReconStatBox(title: "Concealment", value: "97%", color: .purple)
                ReconStatBox(title: "Emissions", value: "ZERO", color: .green)
            }
        }
        .padding()
    }
}

struct ReconStatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: MODULE 2: SENSING & COMMUNICATIONS
// MARK: Advanced environmental intelligence + tactical communications
// MARK: ═══════════════════════════════════════════════════════════════════

public struct SensingModule: View {
    @StateObject private var viewModel = SensingViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Environmental Status
                    environmentalStatus

                    // Resource Detection
                    resourceDetection

                    // Communications
                    communicationsSection
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Sensing")
        }
    }

    private var environmentalStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Environment")
                .font(.headline)
                .foregroundColor(.white)

            HStack(spacing: 12) {
                EnvironmentCard(
                    icon: "thermometer",
                    title: "Temp",
                    value: "\(viewModel.temperature)°F",
                    color: .orange
                )
                EnvironmentCard(
                    icon: "humidity.fill",
                    title: "Humidity",
                    value: "\(viewModel.humidity)%",
                    color: .blue
                )
                EnvironmentCard(
                    icon: "barometer",
                    title: "Pressure",
                    value: "\(viewModel.pressure)",
                    color: .purple
                )
            }

            // Weather Prediction
            HStack {
                Image(systemName: viewModel.weatherIcon)
                    .foregroundColor(.cyan)
                Text(viewModel.weatherPrediction)
                    .foregroundColor(.white)
                Spacer()
                Text("Next 6h")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private var resourceDetection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nearby Resources")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(viewModel.detectedResources) { resource in
                ResourceRow(resource: resource)
            }

            Button {
                viewModel.scanForResources()
            } label: {
                Label("Scan Area", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan.opacity(0.2))
                    .foregroundColor(.cyan)
                    .cornerRadius(12)
            }
        }
    }

    private var communicationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Communications")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.loraConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.loraConnected ? "LoRa" : "No LoRa")
                            .font(.caption2)
                            .foregroundColor(viewModel.loraConnected ? .green : .red)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.takConnected ? Color.blue : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(viewModel.takConnected ? "TAK" : "TAK")
                            .font(.caption2)
                            .foregroundColor(viewModel.takConnected ? .blue : .gray)
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.sendEmergencyBeacon()
                } label: {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                        Text("Emergency")
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(12)
                }

                Button {
                    viewModel.sendLocation()
                } label: {
                    VStack {
                        Image(systemName: "location.fill")
                            .font(.title2)
                        Text("Share Location")
                            .font(.caption)
                    }
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan.opacity(0.2))
                    .cornerRadius(12)
                }
            }
        }
    }
}

struct EnvironmentCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

struct DetectedResource: Identifiable {
    let id = UUID()
    let type: ResourceType
    let distance: Int // meters
    let direction: String
    let confidence: Double

    enum ResourceType: String {
        case water = "Water Source"
        case shelter = "Shelter Site"
        case wood = "Firewood"
        case trail = "Game Trail"
    }

    var icon: String {
        switch type {
        case .water: return "drop.fill"
        case .shelter: return "tent.fill"
        case .wood: return "tree.fill"
        case .trail: return "pawprint.fill"
        }
    }

    var color: Color {
        switch type {
        case .water: return .blue
        case .shelter: return .brown
        case .wood: return .orange
        case .trail: return .green
        }
    }
}

struct ResourceRow: View {
    let resource: DetectedResource

    var body: some View {
        HStack {
            Image(systemName: resource.icon)
                .foregroundColor(resource.color)
                .frame(width: 30)

            VStack(alignment: .leading) {
                Text(resource.type.rawValue)
                    .foregroundColor(.white)
                Text("\(resource.distance)m \(resource.direction)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            Text("\(Int(resource.confidence * 100))%")
                .font(.caption)
                .foregroundColor(.cyan)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

@MainActor
class SensingViewModel: ObservableObject {
    @Published var temperature: Int = 72
    @Published var humidity: Int = 45
    @Published var pressure: String = "30.1"
    @Published var weatherIcon: String = "sun.max.fill"
    @Published var weatherPrediction: String = "Clear skies expected"
    @Published var loraConnected: Bool = false
    @Published var takConnected = false
    @Published var detectedResources: [DetectedResource] = [
        DetectedResource(type: .water, distance: 200, direction: "NE", confidence: 0.87),
        DetectedResource(type: .shelter, distance: 450, direction: "S", confidence: 0.72),
    ]

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to TAK connection status
        FreeTAKConnector.shared.$isConnected
            .assign(to: &$takConnected)

        // Subscribe to mesh peers for LoRa connectivity status
        MeshService.shared.$peers
            .map { !$0.isEmpty }
            .assign(to: &$loraConnected)
        
        // Fetch real weather on init
        fetchWeather()
    }
    
    /// Fetch real weather from wttr.in using device location
    func fetchWeather() {
        // Get location from NavigationLocationManager
        let locMgr = NavigationLocationManager.shared
        guard let loc = locMgr.currentLocation else {
            weatherPrediction = "Waiting for GPS..."
            return
        }
        let coord = loc.coordinate
        
        // wttr.in format: ?format=j1 for JSON
        let urlStr = "https://wttr.in/\(coord.latitude),\(coord.longitude)?format=j1"
        guard let url = URL(string: urlStr) else { return }
        
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("ZeroDark/1.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.weatherPrediction = "Weather unavailable"
                }
                return
            }
            
            // Parse wttr.in JSON response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let current = (json["current_condition"] as? [[String: Any]])?.first {
                    
                    let tempF = current["temp_F"] as? String ?? "--"
                    let humidity = current["humidity"] as? String ?? "--"
                    let desc = (current["weatherDesc"] as? [[String: String]])?.first?["value"] ?? "Unknown"
                    let windMph = current["windspeedMiles"] as? String ?? "0"
                    let windDir = current["winddir16Point"] as? String ?? ""
                    
                    // Map weather code to SF Symbol
                    let code = current["weatherCode"] as? String ?? "113"
                    let icon = self?.weatherCodeToIcon(code) ?? "sun.max.fill"
                    
                    DispatchQueue.main.async {
                        self?.temperature = Int(tempF) ?? 72
                        self?.humidity = Int(humidity) ?? 50
                        self?.weatherIcon = icon
                        self?.weatherPrediction = "\(desc), \(windMph)mph \(windDir)"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.weatherPrediction = "Parse error"
                }
            }
        }.resume()
    }
    
    /// Map wttr.in weather code to SF Symbol
    private func weatherCodeToIcon(_ code: String) -> String {
        switch code {
        case "113": return "sun.max.fill"                    // Clear/Sunny
        case "116": return "cloud.sun.fill"                   // Partly cloudy
        case "119", "122": return "cloud.fill"                // Cloudy/Overcast
        case "143", "248", "260": return "cloud.fog.fill"     // Fog/Mist
        case "176", "263", "266", "293", "296": return "cloud.drizzle.fill"  // Light rain
        case "299", "302", "305", "308": return "cloud.rain.fill"            // Rain
        case "311", "314": return "cloud.sleet.fill"          // Freezing rain
        case "317", "320", "323", "326": return "cloud.snow.fill"            // Snow
        case "329", "332", "335", "338": return "cloud.snow.fill"            // Heavy snow
        case "350", "377": return "cloud.hail.fill"           // Ice/Hail
        case "353", "356", "359": return "cloud.heavyrain.fill"              // Showers
        case "362", "365", "368", "371", "374": return "cloud.sleet.fill"    // Sleet
        case "386", "389", "392", "395": return "cloud.bolt.rain.fill"       // Thunder
        default: return "cloud.fill"
        }
    }

    func scanForResources() {
        // Will integrate with LiDAR environmental scanning
        print("Scanning for resources...")
    }

    func sendEmergencyBeacon() {
        // Send SOS via TAK
        if takConnected, let location = MeshService.shared.peers.first?.location {
            FreeTAKConnector.shared.sendSOS(
                coordinate: location,
                callsign: UIDevice.current.name
            )
        }

        // Send SOS via Mesh
        Task {
            await MeshService.shared.broadcastSOS()
        }
    }

    func sendLocation() {
        // Get current location from NavigationLocationManager if available
        let defaultLocation = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        // Send presence to TAK
        if takConnected {
            FreeTAKConnector.shared.sendPresence(
                coordinate: defaultLocation,
                callsign: UIDevice.current.name,
                battery: getBatteryLevel()
            )
        }

        // Also share on mesh
        MeshService.shared.shareLocation(defaultLocation)
    }

    private func getBatteryLevel() -> Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return Int(level * 100)
    }
}

#Preview("Navigation") {
    NavigationModule()
        .preferredColorScheme(.dark)
}

#Preview("Sensing") {
    SensingModule()
        .preferredColorScheme(.dark)
}
