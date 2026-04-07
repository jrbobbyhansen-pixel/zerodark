import SwiftUI
import Foundation

struct GloveModeView: View {
    @StateObject private var viewModel = GloveModeViewModel()
    
    var body: some View {
        VStack(spacing: 50) {
            Text("Glove Mode")
                .font(.largeTitle)
                .accessibilityLabel("Glove Mode Enabled")
            
            Button(action: {
                viewModel.performAction()
            }) {
                Text("Primary Action")
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .accessibilityLabel("Primary Action Button")
            .accessibilityHint("Double tap to perform primary action")
            
            Button(action: {
                viewModel.showConfirmationDialog = true
            }) {
                Text("Secondary Action")
                    .font(.title)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .accessibilityLabel("Secondary Action Button")
            .accessibilityHint("Double tap to show confirmation dialog")
            
            Spacer()
        }
        .padding()
        .alert(isPresented: $viewModel.showConfirmationDialog) {
            Alert(
                title: Text("Confirm Action"),
                message: Text("Are you sure you want to perform this action?"),
                primaryButton: .cancel(Text("Cancel")),
                secondaryButton: .default(Text("Confirm"), action: {
                    viewModel.confirmAction()
                })
            )
        }
    }
}

class GloveModeViewModel: ObservableObject {
    @Published var showConfirmationDialog = false
    
    func performAction() {
        // Implementation for primary action
        print("Primary action performed")
    }
    
    func confirmAction() {
        // Implementation for secondary action
        print("Secondary action confirmed")
    }
}

struct GloveModeView_Previews: PreviewProvider {
    static var previews: some View {
        GloveModeView()
    }
}