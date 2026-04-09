import SwiftUI
import Foundation
import CoreLocation

// MARK: - BurnoverProtocolViewModel

class BurnoverProtocolViewModel: ObservableObject {
    @Published var selectedDeploymentZone: CLLocationCoordinate2D?
    @Published var timerRemaining: TimeInterval = 600 // 10 minutes
    @Published var isTimerRunning = false
    @Published var fireShelterDeployed = false
    @Published var postBurnoverProceduresCompleted = false

    private var timer: Timer?

    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timerRemaining > 0 {
                self.timerRemaining -= 1
            } else {
                self.stopTimer()
            }
        }
        isTimerRunning = true
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
    }

    func deployFireShelter() {
        fireShelterDeployed = true
    }

    func completePostBurnoverProcedures() {
        postBurnoverProceduresCompleted = true
    }
}

// MARK: - BurnoverProtocolView

struct BurnoverProtocolView: View {
    @StateObject private var viewModel = BurnoverProtocolViewModel()

    var body: some View {
        VStack {
            HStack {
                Text("Deployment Zone:")
                $name(selectedLocation: $viewModel.selectedDeploymentZone)
                    .frame(height: 200)
            }

            Button(action: viewModel.startTimer) {
                Text("Start Timer")
            }
            .disabled(viewModel.isTimerRunning)

            Button(action: viewModel.stopTimer) {
                Text("Stop Timer")
            }
            .disabled(!viewModel.isTimerRunning)

            Text("Time Remaining: \(Int(viewModel.timerRemaining)) seconds")

            Button(action: viewModel.deployFireShelter) {
                Text("Deploy Fire Shelter")
            }
            .disabled(viewModel.fireShelterDeployed)

            Button(action: viewModel.completePostBurnoverProcedures) {
                Text("Complete Post-Burnover Procedures")
            }
            .disabled(viewModel.postBurnoverProceduresCompleted)
        }
        .padding()
    }
}

// MARK: - MapView

struct BurnoverMapSnippet: UIViewRepresentable {
    @Binding var selectedLocation: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let selectedLocation = selectedLocation {
            let region = MKCoordinateRegion(center: selectedLocation, latitudinalMeters: 1000, longitudinalMeters: 1000)
            uiView.setRegion(region, animated: true)
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

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let coordinate = view.annotation?.coordinate {
                parent.selectedLocation = coordinate
            }
        }
    }
}

// MARK: - Previews

struct BurnoverProtocolView_Previews: PreviewProvider {
    static var previews: some View {
        BurnoverProtocolView()
    }
}