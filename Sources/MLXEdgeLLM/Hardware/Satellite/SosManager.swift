import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

class SosManager: ObservableObject {
    @Published var isSosActive: Bool = false
    @Published var alertConfirmed: Bool = false
    @Published var statusMessage: String = ""
    @Published var location: CLLocationCoordinate2D?
    @Published var rescueConfirmed: Bool = false
    
    private let locationManager = CLLocationManager()
    private let audioPlayer = AVAudioPlayer()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        do {
            let audioURL = Bundle.main.url(forResource: "sos_alert", withExtension: "mp3")!
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer.numberOfLoops = -1
        } catch {
            print("Failed to load audio: \(error)")
        }
    }
    
    func requestSos() {
        isSosActive = true
        locationManager.startUpdatingLocation()
        audioPlayer.play()
        statusMessage = "SOS Alert Activated"
    }
    
    func confirmAlert() {
        alertConfirmed = true
        statusMessage = "Alert Confirmed"
    }
    
    func cancelSos() {
        isSosActive = false
        locationManager.stopUpdatingLocation()
        audioPlayer.stop()
        statusMessage = "SOS Alert Cancelled"
    }
    
    func confirmRescue() {
        rescueConfirmed = true
        statusMessage = "Rescue Confirmed"
    }
}

extension SosManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
}

struct SosView: View {
    @StateObject private var sosManager = SosManager()
    
    var body: some View {
        VStack {
            Text(sosManager.statusMessage)
                .font(.headline)
                .padding()
            
            if sosManager.isSosActive {
                Button("Confirm Alert") {
                    sosManager.confirmAlert()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!sosManager.alertConfirmed)
                
                Button("Cancel SOS") {
                    sosManager.cancelSos()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Request SOS") {
                    sosManager.requestSos()
                }
                .buttonStyle(.borderedProminent)
            }
            
            if sosManager.alertConfirmed {
                Button("Confirm Rescue") {
                    sosManager.confirmRescue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!sosManager.rescueConfirmed)
            }
        }
        .padding()
    }
}

struct SosView_Previews: PreviewProvider {
    static var previews: some View {
        SosView()
    }
}