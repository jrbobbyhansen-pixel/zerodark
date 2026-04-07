import Foundation
import CoreLocation
import Combine

// MARK: - DgpsInterface

class DgpsInterface: ObservableObject {
    @Published var location: CLLocation? = nil
    @Published var error: Error? = nil
    
    private var cancellables = Set<AnyCancellable>()
    private let locationManager = CLLocationManager()
    private let ntripClient = NtripClient()
    
    init() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        
        ntripClient.delegate = self
    }
    
    func start() {
        locationManager.startUpdatingLocation()
        ntripClient.connect()
    }
    
    func stop() {
        locationManager.stopUpdatingLocation()
        ntripClient.disconnect()
    }
}

// MARK: - CLLocationManagerDelegate

extension DgpsInterface: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = error
    }
}

// MARK: - NtripClient

class NtripClient: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var error: Error? = nil
    
    private var socket: NWConnection?
    private var delegate: NtripClientDelegate?
    
    func connect() {
        guard let url = URL(string: "http://example.com/ntrip") else { return }
        socket = NWConnection(to: url, using: .tcp)
        socket?.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                self?.isConnected = true
                self?.delegate?.ntripClientDidConnect(self!)
            case .failed(let error):
                self?.isConnected = false
                self?.error = error
                self?.delegate?.ntripClientDidFail(self!, with: error)
            default:
                break
            }
        }
        socket?.start(queue: .main)
    }
    
    func disconnect() {
        socket?.cancel()
        socket = nil
        isConnected = false
    }
}

// MARK: - NtripClientDelegate

protocol NtripClientDelegate: AnyObject {
    func ntripClientDidConnect(_ client: NtripClient)
    func ntripClientDidFail(_ client: NtripClient, with error: Error)
}