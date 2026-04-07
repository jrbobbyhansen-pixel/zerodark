import SwiftUI
import CoreLocation
import ARKit

// MARK: - Models

struct TeamMember: Identifiable {
    let id: UUID
    let name: String
    let location: CLLocationCoordinate2D
    let lastUpdateTime: Date
    let batteryLevel: Double
    let status: Status
}

enum Status: String, CaseIterable {
    case OK
    case Moving
    case Emergency
}

// MARK: - View Models

class TeamStatusViewModel: ObservableObject {
    @Published var teamMembers: [TeamMember] = []
    @Published var sortOption: SortOption = .distance
    
    enum SortOption: String, CaseIterable {
        case distance
        case status
    }
    
    func sortTeamMembers() {
        switch sortOption {
        case .distance:
            teamMembers.sort { $0.location.distance(from: CLLocation(latitude: 0, longitude: 0)) < $1.location.distance(from: CLLocation(latitude: 0, longitude: 0)) }
        case .status:
            teamMembers.sort { $0.status.rawValue < $1.status.rawValue }
        }
    }
}

// MARK: - Views

struct StatusBoardView: View {
    @StateObject private var viewModel = TeamStatusViewModel()
    
    var body: some View {
        VStack {
            Picker("Sort By", selection: $viewModel.sortOption) {
                ForEach(TeamStatusViewModel.SortOption.allCases, id: \.self) { option in
                    Text(option.rawValue.capitalized)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: viewModel.sortOption) { _ in
                viewModel.sortTeamMembers()
            }
            
            List(viewModel.teamMembers) { member in
                TeamMemberRow(member: member)
            }
        }
        .onAppear {
            // Simulate fetching team members
            viewModel.teamMembers = [
                TeamMember(id: UUID(), name: "Alice", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), lastUpdateTime: Date(), batteryLevel: 85.0, status: .OK),
                TeamMember(id: UUID(), name: "Bob", location: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195), lastUpdateTime: Date().addingTimeInterval(-300), batteryLevel: 70.0, status: .Moving),
                TeamMember(id: UUID(), name: "Charlie", location: CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4196), lastUpdateTime: Date().addingTimeInterval(-600), batteryLevel: 50.0, status: .Emergency)
            ]
            viewModel.sortTeamMembers()
        }
    }
}

struct TeamMemberRow: View {
    let member: TeamMember
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(member.name)
                    .font(.headline)
                Text("Location: \(member.location.latitude), \(member.location.longitude)")
                    .font(.subheadline)
                Text("Last Update: \(member.lastUpdateTime, style: .relative)")
                    .font(.subheadline)
                Text("Battery: \(Int(member.batteryLevel))%")
                    .font(.subheadline)
            }
            Spacer()
            Text(member.status.rawValue)
                .font(.subheadline)
                .padding(5)
                .background(member.status == .Emergency ? Color.red : member.status == .Moving ? Color.yellow : Color.green)
                .foregroundColor(.white)
                .cornerRadius(5)
        }
    }
}

// MARK: - Preview

struct StatusBoardView_Previews: PreviewProvider {
    static var previews: some View {
        StatusBoardView()
    }
}