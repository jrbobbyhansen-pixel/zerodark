import Foundation
import SwiftUI

// MARK: - CommunicationDrill

struct CommunicationDrill: View {
    @StateObject private var viewModel = CommunicationDrillViewModel()
    
    var body: some View {
        VStack {
            Text("Communication Drill")
                .font(.largeTitle)
                .padding()
            
            HStack {
                Text("Message: \(viewModel.message)")
                    .font(.title2)
                
                Button(action: viewModel.sendMessage) {
                    Text("Send")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
            
            Text("Errors: \(viewModel.errors.count)")
                .font(.title2)
                .foregroundColor(viewModel.errors.isEmpty ? .green : .red)
                .padding()
            
            List(viewModel.errors, id: \.self) { error in
                Text(error)
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - CommunicationDrillViewModel

class CommunicationDrillViewModel: ObservableObject {
    @Published var message: String = "Emergency evacuation"
    @Published var errors: [String] = []
    
    func sendMessage() {
        // Simulate message transmission
        let transmissionSuccess = simulateMessageTransmission()
        
        if !transmissionSuccess {
            errors.append("Message transmission failed")
        }
    }
    
    private func simulateMessageTransmission() -> Bool {
        // Simulate a 10% chance of transmission failure
        return Bool.random(probability: 0.9)
    }
}

// MARK: - Extensions

extension Bool {
    init(probability: Double) {
        self = probability > Double.random(in: 0...1)
    }
}