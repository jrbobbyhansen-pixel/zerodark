import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Threat Model

struct Threat: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let type: ThreatType
    let lastObserved: Date
    let confidence: Double
}

enum ThreatType: String, Codable {
    case hostile
    case neutral
    case unknown
}

// MARK: - ThreatTracker Service

class ThreatTracker: ObservableObject {
    @Published private(set) var threats: [Threat] = []
    @Published private(set) var proximityAlerts: [Threat] = []
    
    private let locationManager = CLLocationManager()
    private let audioPlayer = AVAudioPlayer()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        do {
            let audioURL = Bundle.main.url(forResource: "alert", withExtension: "mp3")!
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer.prepareToPlay()
        } catch {
            print("Failed to load audio player: \(error)")
        }
    }
    
    func addThreat(location: CLLocationCoordinate2D, type: ThreatType, confidence: Double) {
        let threat = Threat(location: location, type: type, lastObserved: Date(), confidence: confidence)
        threats.append(threat)
        checkProximity(threat)
    }
    
    private func checkProximity(_ threat: Threat) {
        guard let userLocation = locationManager.location?.coordinate else { return }
        let distance = threat.location.distance(from: userLocation)
        
        if distance < 100 { // 100 meters threshold
            proximityAlerts.append(threat)
            audioPlayer.play()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension ThreatTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Update proximity checks if needed
    }
}

// MARK: - ThreatTrackerView

struct ThreatTrackerView: View {
    @StateObject private var viewModel = ThreatTracker()
    
    var body: some View {
        VStack {
            $name(threats: viewModel.threats)
                .edgesIgnoringSafeArea(.all)
            
            List(viewModel.proximityAlerts) { threat in
                ThreatRow(threat: threat)
            }
            .listStyle(PlainListStyle())
        }
        .onAppear {
            // Load known threats from database or API
        }
    }
}

// MARK: - MapView

struct ThreatMapSnippet: UIViewRepresentable {
    let threats: [Threat]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        uiView.addAnnotations(threats.map { ThreatAnnotation(threat: $0) })
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let threatAnnotation = annotation as? ThreatAnnotation else { return nil }
            let view = MKPinAnnotationView(annotation: annotation, reuseIdentifier: "threatPin")
            view.canShowCallout = true
            view.calloutOffset = CGPoint(x: 0, y: 5)
            view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            return view
        }
    }
}

// MARK: - ThreatAnnotation

class ThreatAnnotation: NSObject, MKAnnotation {
    let threat: Threat
    let coordinate: CLLocationCoordinate2D
    
    init(threat: Threat) {
        self.threat = threat
        self.coordinate = threat.location
    }
}

// MARK: - ThreatRow

struct ThreatRow: View {
    let threat: Threat
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Type: \(threat.type.rawValue)")
                    .font(.headline)
                Text("Last Observed: \(threat.lastObserved, style: .date)")
                    .font(.subheadline)
                Text("Confidence: \(threat.confidence, specifier: "%.2f")")
                    .font(.subheadline)
            }
            Spacer()
            Image(systemName: threat.type == .hostile ? "exclamationmark.circle.fill" : "info.circle.fill")
                .foregroundColor(threat.type == .hostile ? .red : .blue)
        }
    }
}