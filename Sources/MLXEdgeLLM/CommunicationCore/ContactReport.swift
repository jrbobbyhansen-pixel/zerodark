import Foundation
import SwiftUI
import CoreLocation

// MARK: - ContactReport

struct ContactReport: Identifiable {
    let id = UUID()
    var time: Date
    var location: CLLocationCoordinate2D
    var situation: String
    var activity: String
    var locationDetails: String
    var equipment: String
    var timeOfContact: String
    var photos: [UIImage]
}

// MARK: - ContactReportBuilder

class ContactReportBuilder: ObservableObject {
    @Published var report = ContactReport(time: Date(), location: CLLocationCoordinate2D(), situation: "", activity: "", locationDetails: "", equipment: "", timeOfContact: "", photos: [])
    
    func buildReport() -> ContactReport {
        return report
    }
    
    func addPhoto(_ photo: UIImage) {
        report.photos.append(photo)
    }
    
    func updateLocation(_ location: CLLocationCoordinate2D) {
        report.location = location
    }
    
    func updateSituation(_ situation: String) {
        report.situation = situation
    }
    
    func updateActivity(_ activity: String) {
        report.activity = activity
    }
    
    func updateLocationDetails(_ locationDetails: String) {
        report.locationDetails = locationDetails
    }
    
    func updateEquipment(_ equipment: String) {
        report.equipment = equipment
    }
    
    func updateTimeOfContact(_ timeOfContact: String) {
        report.timeOfContact = timeOfContact
    }
}

// MARK: - ContactReportView

struct ContactReportView: View {
    @StateObject private var builder = ContactReportBuilder()
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Time and Location")) {
                    Text("Time: \(builder.report.time, formatter: DateFormatter())")
                    Text("Location: \(builder.report.location.latitude), \(builder.report.location.longitude)")
                }
                
                Section(header: Text("SALUTE")) {
                    TextField("Situation", text: $builder.report.situation)
                    TextField("Activity", text: $builder.report.activity)
                    TextField("Location Details", text: $builder.report.locationDetails)
                    TextField("Equipment", text: $builder.report.equipment)
                    TextField("Time of Contact", text: $builder.report.timeOfContact)
                }
                
                Section(header: Text("Photos")) {
                    ForEach(builder.report.photos, id: \.self) { photo in
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                    }
                }
            }
            
            Button(action: {
                // Add photo functionality
            }) {
                Text("Add Photo")
            }
            
            Button(action: {
                // Transmit report functionality
            }) {
                Text("Transmit Report")
            }
        }
        .navigationTitle("Contact Report")
    }
}

// MARK: - Preview

struct ContactReportView_Previews: PreviewProvider {
    static var previews: some View {
        ContactReportView()
    }
}