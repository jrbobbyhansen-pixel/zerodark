import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - QuickActions

struct QuickActions: View {
    @StateObject private var viewModel = QuickActionsViewModel()
    
    var body: some View {
        VStack {
            // Quick Actions Menu
            ForEach(viewModel.actions) { action in
                Button(action: action.action) {
                    HStack {
                        Image(systemName: action.icon)
                            .font(.title3)
                        Text(action.title)
                            .font(.body)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(width: 200, height: 300)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 8)
    }
}

// MARK: - QuickActionsViewModel

class QuickActionsViewModel: ObservableObject {
    @Published var actions: [QuickAction] = [
        QuickAction(title: "Navigate", icon: "map", action: {
            // Implement navigation action
        }),
        QuickAction(title: "Record Video", icon: "video.fill", action: {
            // Implement video recording action
        }),
        QuickAction(title: "Share Location", icon: "location.fill", action: {
            // Implement location sharing action
        }),
        QuickAction(title: "AR Mode", icon: "arkit", action: {
            // Implement AR mode action
        })
    ]
}

// MARK: - QuickAction

struct QuickAction {
    let title: String
    let icon: String
    let action: () -> Void
}