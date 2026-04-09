import Foundation
import SwiftUI
import CoreLocation

// MARK: - EDXL Message Handler

class EdxlHandler: ObservableObject {
    @Published var situationReports: [SituationReport] = []
    @Published var hospitalAvailabilities: [HospitalAvailability] = []
    
    func handleEdxlMessage(_ message: EDXLDistribution) {
        switch message.type {
        case .situationReport:
            if let report = message.content as? SituationReport {
                situationReports.append(report)
            }
        case .hospitalAvailability:
            if let availability = message.content as? HospitalAvailability {
                hospitalAvailabilities.append(availability)
            }
        default:
            break
        }
    }
}

// MARK: - EDXL Distribution

struct EDXLDistribution {
    let type: EDXLType
    let content: Any
}

enum EDXLType {
    case situationReport
    case hospitalAvailability
    // Add more types as needed
}

// MARK: - Situation Report

struct SituationReport {
    let id: UUID
    let location: CLLocationCoordinate2D
    let description: String
    let timestamp: Date
}

// MARK: - Hospital Availability

struct HospitalAvailability {
    let id: UUID
    let name: String
    let location: CLLocationCoordinate2D
    let bedsAvailable: Int
    let lastUpdated: Date
}

// MARK: - SwiftUI View

struct EmergencyView: View {
    @StateObject private var handler = EdxlHandler()
    
    var body: some View {
        VStack {
            List(handler.situationReports) { report in
                VStack(alignment: .leading) {
                    Text("Report ID: \(report.id.uuidString)")
                    Text("Location: \(report.location.description)")
                    Text("Description: \(report.description)")
                    Text("Timestamp: \(report.timestamp, style: .date)")
                }
            }
            
            List(handler.hospitalAvailabilities) { availability in
                VStack(alignment: .leading) {
                    Text("Hospital ID: \(availability.id.uuidString)")
                    Text("Name: \(availability.name)")
                    Text("Location: \(availability.location.description)")
                    Text("Beds Available: \(availability.bedsAvailable)")
                    Text("Last Updated: \(availability.lastUpdated, style: .date)")
                }
            }
        }
        .navigationTitle("Emergency Information")
    }
}

// MARK: - Preview

struct EmergencyView_Previews: PreviewProvider {
    static var previews: some View {
        EmergencyView()
    }
}