import Foundation
import SwiftUI
import CoreLocation

// MARK: - ContactReport

struct ContactReport: Identifiable {
    let id = UUID()
    var contactName: String
    var contactID: String
    var conversationNotes: String
    var photo: UIImage?
    var location: CLLocationCoordinate2D?
    var followUpDate: Date?
}

// MARK: - ContactReportViewModel

class ContactReportViewModel: ObservableObject {
    @Published var contactName: String = ""
    @Published var contactID: String = ""
    @Published var conversationNotes: String = ""
    @Published var photo: UIImage? = nil
    @Published var location: CLLocationCoordinate2D? = nil
    @Published var followUpDate: Date? = nil
    
    func saveReport() {
        // Logic to save the contact report
    }
    
    func capturePhoto() {
        // Logic to capture a photo
    }
    
    func updateLocation(_ newLocation: CLLocationCoordinate2D) {
        location = newLocation
    }
    
    func setFollowUpDate(_ date: Date) {
        followUpDate = date
    }
}

// MARK: - ContactReportView

struct ContactReportView: View {
    @StateObject private var viewModel = ContactReportViewModel()
    
    var body: some View {
        VStack {
            TextField("Contact Name", text: $viewModel.contactName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            TextField("Contact ID", text: $viewModel.contactID)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            TextEditor(text: $viewModel.conversationNotes)
                .frame(height: 100)
                .padding()
            
            Button(action: viewModel.capturePhoto) {
                Text("Capture Photo")
            }
            .padding()
            
            if let photo = viewModel.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .padding()
            }
            
            $name(location: $viewModel.location)
                .frame(height: 300)
                .padding()
            
            DatePicker("Follow Up Date", selection: $viewModel.followUpDate, displayedComponents: .date)
                .padding()
            
            Button(action: viewModel.saveReport) {
                Text("Save Report")
            }
            .padding()
        }
        .navigationTitle("Contact Report")
    }
}

// MARK: - MapView

struct ContactReportMapSnippet: UIViewRepresentable {
    @Binding var location: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let location = location {
            let region = MKCoordinateRegion(center: location, latitudinalMeters: 1000, longitudinalMeters: 1000)
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
        
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            parent.location = userLocation.coordinate
        }
    }
}

// MARK: - Preview

struct ContactReportView_Previews: PreviewProvider {
    static var previews: some View {
        ContactReportView()
    }
}