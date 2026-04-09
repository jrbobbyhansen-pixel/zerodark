import Foundation
import SwiftUI
import CoreLocation
import ARKit

// MARK: - LoraSignalMapper

class LoraSignalMapper: ObservableObject {
    @Published var rssiValues: [CLLocationCoordinate2D: Double] = [:]
    @Published var snrValues: [CLLocationCoordinate2D: Double] = [:]
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var isRecording: Bool = false
    
    private let locationManager = CLLocationManager()
    private let arSession = ARSession()
    
    init() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        
        arSession.delegate = self
    }
    
    func startRecording() {
        isRecording = true
        locationManager.startUpdatingLocation()
        arSession.run()
    }
    
    func stopRecording() {
        isRecording = false
        locationManager.stopUpdatingLocation()
        arSession.pause()
    }
}

// MARK: - CLLocationManagerDelegate

extension LoraSignalMapper: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
    }
}

// MARK: - ARSessionDelegate

extension LoraSignalMapper: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRecording, let currentLocation = currentLocation else { return }
        
        // Simulate RSSI and SNR values
        let rssi = Double.random(in: -100...0)
        let snr = Double.random(in: 0...10)
        
        rssiValues[currentLocation] = rssi
        snrValues[currentLocation] = snr
    }
}

// MARK: - LoraSignalMapView

struct LoraSignalMapView: View {
    @StateObject private var viewModel = LoraSignalMapper()
    
    var body: some View {
        VStack {
            $name(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            Button(action: {
                viewModel.isRecording ? viewModel.stopRecording() : viewModel.startRecording()
            }) {
                Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }
}

// MARK: - MapView

struct LoraMapSnippet: UIViewRepresentable {
    @ObservedObject var viewModel: LoraSignalMapper
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        
        viewModel.rssiValues.forEach { (coordinate, rssi) in
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = "RSSI: \(rssi)"
            uiView.addAnnotation(annotation)
        }
        
        viewModel.snrValues.forEach { (coordinate, snr) in
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = "SNR: \(snr)"
            uiView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
    }
}

// MARK: - Preview

struct LoraSignalLoraMapSnippet_Previews: PreviewProvider {
    static var previews: some View {
        LoraSignal$name()
    }
}