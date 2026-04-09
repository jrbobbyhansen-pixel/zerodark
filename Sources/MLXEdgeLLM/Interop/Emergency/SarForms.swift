import Foundation
import SwiftUI
import CoreLocation

// MARK: - Models

struct MissingPersonQuestionnaire {
    var name: String
    var age: Int
    var gender: String
    var lastSeenLocation: CLLocationCoordinate2D
    var lastSeenTime: Date
    var description: String
}

struct SearchAssignment {
    var missionID: String
    var teamMembers: [String]
    var searchArea: MKPolygon
    var startTime: Date
    var endTime: Date
    var status: String
}

struct Debriefing {
    var missionID: String
    var teamMembers: [String]
    var outcome: String
    var notes: String
}

// MARK: - View Models

class MissingPersonQuestionnaireViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var age: Int = 0
    @Published var gender: String = ""
    @Published var lastSeenLocation: CLLocationCoordinate2D?
    @Published var lastSeenTime: Date = Date()
    @Published var description: String = ""
}

class SearchAssignmentViewModel: ObservableObject {
    @Published var missionID: String = ""
    @Published var teamMembers: [String] = []
    @Published var searchArea: MKPolygon?
    @Published var startTime: Date = Date()
    @Published var endTime: Date = Date()
    @Published var status: String = ""
}

class DebriefingViewModel: ObservableObject {
    @Published var missionID: String = ""
    @Published var teamMembers: [String] = []
    @Published var outcome: String = ""
    @Published var notes: String = ""
}

// MARK: - Views

struct MissingPersonQuestionnaireView: View {
    @StateObject private var viewModel = MissingPersonQuestionnaireViewModel()
    
    var body: some View {
        Form {
            Section(header: Text("Personal Information")) {
                TextField("Name", text: $viewModel.name)
                TextField("Age", value: $viewModel.age, formatter: NumberFormatter())
                TextField("Gender", text: $viewModel.gender)
            }
            
            Section(header: Text("Last Seen")) {
                Map(coordinateRegion: .constant(MKCoordinateRegion(center: viewModel.lastSeenLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0), latitudinalMeters: 1000, longitudinalMeters: 1000)))
                    .frame(height: 300)
                DatePicker("Last Seen Time", selection: $viewModel.lastSeenTime, displayedComponents: .hourAndMinute)
            }
            
            Section(header: Text("Description")) {
                TextEditor(text: $viewModel.description)
            }
        }
        .navigationTitle("Missing Person Questionnaire")
    }
}

struct SearchAssignmentView: View {
    @StateObject private var viewModel = SearchAssignmentViewModel()
    
    var body: some View {
        Form {
            Section(header: Text("Mission Details")) {
                TextField("Mission ID", text: $viewModel.missionID)
                TextField("Team Members", text: Binding(
                    get: { viewModel.teamMembers.joined(separator: ", ") },
                    set: { viewModel.teamMembers = $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
                ))
            }
            
            Section(header: Text("Search Area")) {
                Map(coordinateRegion: .constant(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), latitudinalMeters: 1000, longitudinalMeters: 1000)))
                    .frame(height: 300)
            }
            
            Section(header: Text("Time Frame")) {
                DatePicker("Start Time", selection: $viewModel.startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $viewModel.endTime, displayedComponents: .hourAndMinute)
            }
            
            Section(header: Text("Status")) {
                TextField("Status", text: $viewModel.status)
            }
        }
        .navigationTitle("Search Assignment")
    }
}

struct DebriefingView: View {
    @StateObject private var viewModel = DebriefingViewModel()
    
    var body: some View {
        Form {
            Section(header: Text("Mission Details")) {
                TextField("Mission ID", text: $viewModel.missionID)
                TextField("Team Members", text: Binding(
                    get: { viewModel.teamMembers.joined(separator: ", ") },
                    set: { viewModel.teamMembers = $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
                ))
            }
            
            Section(header: Text("Outcome")) {
                TextField("Outcome", text: $viewModel.outcome)
            }
            
            Section(header: Text("Notes")) {
                TextEditor(text: $viewModel.notes)
            }
        }
        .navigationTitle("Debriefing")
    }
}

// MARK: - Previews

struct SarForms_Previews: PreviewProvider {
    static var previews: some View {
        MissingPersonQuestionnaireView()
        SearchAssignmentView()
        DebriefingView()
    }
}