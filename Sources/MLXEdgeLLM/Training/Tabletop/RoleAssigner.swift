import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - RoleAssigner Model

struct Role: Identifiable {
    let id = UUID()
    let name: String
    let position: String
    let responsibilities: [String]
    let contactInfo: String
}

class RoleAssigner: ObservableObject {
    @Published var roles: [Role] = []
    
    func addRole(name: String, position: String, responsibilities: [String], contactInfo: String) {
        let newRole = Role(name: name, position: position, responsibilities: responsibilities, contactInfo: contactInfo)
        roles.append(newRole)
    }
    
    func removeRole(_ role: Role) {
        if let index = roles.firstIndex(of: role) {
            roles.remove(at: index)
        }
    }
}

// MARK: - RoleAssigner View

struct RoleAssignerView: View {
    @StateObject private var viewModel = RoleAssigner()
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.roles) { role in
                    RoleCardView(role: role)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        viewModel.removeRole(viewModel.roles[index])
                    }
                }
            }
            .navigationTitle("Role Assigner")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new role logic here
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - RoleCardView

struct RoleCardView: View {
    let role: Role
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(role.name)
                .font(.headline)
            Text(role.position)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Responsibilities:")
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(role.responsibilities, id: \.self) { responsibility in
                Text("- \(responsibility)")
            }
            Text("Contact Info: \(role.contactInfo)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 5)
    }
}

// MARK: - Previews

struct RoleAssignerView_Previews: PreviewProvider {
    static var previews: some View {
        RoleAssignerView()
    }
}