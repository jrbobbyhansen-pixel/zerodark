import SwiftUI
import CoreLocation

// MARK: - TeamStatusViewModel

class TeamStatusViewModel: ObservableObject {
    @Published var teamMembers: [TeamMember] = []
    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""
    
    private let locationManager = CLLocationManager()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func checkForIssues() {
        for member in teamMembers {
            if member.healthStatus == .critical {
                showAlert = true
                alertMessage = "\(member.name) is in critical health!"
                return
            }
        }
    }
}

// MARK: - TeamMember

struct TeamMember: Identifiable {
    let id = UUID()
    let name: String
    let location: CLLocationCoordinate2D
    let activity: String
    let healthStatus: HealthStatus
}

// MARK: - HealthStatus

enum HealthStatus: String {
    case healthy
    case injured
    case critical
}

// MARK: - TeamStatusView

struct TeamStatusView: View {
    @StateObject private var viewModel = TeamStatusViewModel()
    
    var body: some View {
        VStack {
            $name(teamMembers: viewModel.teamMembers)
                .edgesIgnoringSafeArea(.all)
            
            List(viewModel.teamMembers) { member in
                TeamMemberRow(member: member)
            }
            .listStyle(PlainListStyle())
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(title: Text("Alert"), message: Text(viewModel.alertMessage), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            viewModel.checkForIssues()
        }
    }
}

// MARK: - TeamMemberRow

struct TeamMemberRow: View {
    let member: TeamMember
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(member.name)
                    .font(.headline)
                Text(member.activity)
                    .font(.subheadline)
                Text(member.healthStatus.rawValue)
                    .font(.caption)
                    .foregroundColor(member.healthStatus.color)
            }
            Spacer()
            Image(systemName: "location.circle.fill")
                .foregroundColor(.blue)
        }
    }
}

// MARK: - MapView

struct TeamStatusMapSnippet: UIViewRepresentable {
    let teamMembers: [TeamMember]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        for member in teamMembers {
            let annotation = MKPointAnnotation()
            annotation.coordinate = member.location
            annotation.title = member.name
            uiView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension TeamStatusViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Update team member location if needed
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - HealthStatus+Color

extension HealthStatus {
    var color: Color {
        switch self {
        case .healthy: return .green
        case .injured: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Preview

struct TeamStatusView_Previews: PreviewProvider {
    static var previews: some View {
        TeamStatusView()
    }
}