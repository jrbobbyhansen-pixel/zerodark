import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - CommsSimulator

class CommsSimulator: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isInterferenceActive: Bool = false
    @Published var delay: TimeInterval = 0.5
    
    private var timer: Timer?
    
    func sendMessage(_ content: String) {
        let message = Message(content: content, isDelayed: delay > 0, isInterfered: isInterferenceActive)
        messages.append(message)
        
        if delay > 0 {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.messages.append(Message(content: content, isDelayed: true, isInterfered: self?.isInterferenceActive ?? false))
            }
        }
    }
    
    func toggleInterference() {
        isInterferenceActive.toggle()
    }
    
    func setDelay(_ newDelay: TimeInterval) {
        delay = newDelay
    }
}

// MARK: - Message

struct Message: Identifiable {
    let id = UUID()
    let content: String
    let isDelayed: Bool
    let isInterfered: Bool
}

// MARK: - CommsSimulatorView

struct CommsSimulatorView: View {
    @StateObject private var viewModel = CommsSimulator()
    
    var body: some View {
        VStack {
            HStack {
                Button("Send Message") {
                    viewModel.sendMessage("Hello, Team!")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                Toggle("Interference", isOn: $viewModel.isInterferenceActive)
                    .padding()
            }
            
            Slider(value: $viewModel.delay, in: 0...5, step: 0.1) {
                Text("Delay: \(String(format: "%.1f", viewModel.delay))s")
            }
            .padding()
            
            List(viewModel.messages) { message in
                HStack {
                    Text(message.content)
                        .foregroundColor(message.isInterfered ? .red : .black)
                    Spacer()
                    if message.isDelayed {
                        Text("Delayed")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct CommsSimulatorView_Previews: PreviewProvider {
    static var previews: some View {
        CommsSimulatorView()
    }
}