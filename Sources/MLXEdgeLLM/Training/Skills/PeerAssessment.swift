import Foundation
import SwiftUI
import CoreLocation

// MARK: - Models

struct Assessment {
    let id: UUID
    let skill: String
    let rating: Int
    let comments: String
    let isAnonymous: Bool
}

struct Peer {
    let id: UUID
    let name: String
    let location: CLLocationCoordinate2D
}

// MARK: - View Models

class AssessmentViewModel: ObservableObject {
    @Published var assessments: [Assessment] = []
    @Published var selectedPeer: Peer?
    @Published var isAnonymous: Bool = false
    @Published var skill: String = ""
    @Published var rating: Int = 0
    @Published var comments: String = ""
    
    func addAssessment() {
        guard let selectedPeer = selectedPeer, !skill.isEmpty else { return }
        let newAssessment = Assessment(
            id: UUID(),
            skill: skill,
            rating: rating,
            comments: comments,
            isAnonymous: isAnonymous
        )
        assessments.append(newAssessment)
        clearForm()
    }
    
    func clearForm() {
        skill = ""
        rating = 0
        comments = ""
    }
}

// MARK: - Views

struct PeerAssessmentView: View {
    @StateObject private var viewModel = AssessmentViewModel()
    @EnvironmentObject private var locationManager: LocationManager
    
    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Peer Selection")) {
                        Picker("Select Peer", selection: $viewModel.selectedPeer) {
                            ForEach(locationManager.peers, id: \.id) { peer in
                                Text(peer.name)
                            }
                        }
                    }
                    
                    Section(header: Text("Assessment Details")) {
                        TextField("Skill", text: $viewModel.skill)
                        Picker("Rating", selection: $viewModel.rating) {
                            ForEach(1...5, id: \.self) { rating in
                                Text("\(rating)")
                            }
                        }
                        Toggle("Anonymous", isOn: $viewModel.isAnonymous)
                        TextEditor(text: $viewModel.comments)
                            .frame(height: 100)
                    }
                }
                
                Button(action: viewModel.addAssessment) {
                    Text("Submit Assessment")
                }
                .padding()
                .disabled(viewModel.selectedPeer == nil || viewModel.skill.isEmpty)
            }
            .navigationTitle("Peer Assessment")
        }
    }
}

// MARK: - Services

class LocationManager: ObservableObject {
    @Published var peers: [Peer] = []
    
    init() {
        // Simulate fetching peers from a location-based service
        peers = [
            Peer(id: UUID(), name: "Alice", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
            Peer(id: UUID(), name: "Bob", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
        ]
    }
}

// MARK: - Previews

struct PeerAssessmentView_Previews: PreviewProvider {
    static var previews: some View {
        PeerAssessmentView()
            .environmentObject(LocationManager())
    }
}