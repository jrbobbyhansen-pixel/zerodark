import Foundation
import SwiftUI

// MARK: - NetworkIsolationManager

class NetworkIsolationManager: ObservableObject {
    @Published private(set) var isNetworkIsolated: Bool = false
    @Published private(set) var allowedConnectivityWindows: [DateInterval] = []
    
    private var connectivityTimer: Timer?
    
    func enableNetworkIsolation() {
        isNetworkIsolated = true
        scheduleConnectivityWindows()
    }
    
    func disableNetworkIsolation() {
        isNetworkIsolated = false
        connectivityTimer?.invalidate()
        connectivityTimer = nil
    }
    
    private func scheduleConnectivityWindows() {
        // Example: Allow connectivity every 30 minutes for 5 minutes
        let interval: TimeInterval = 30 * 60
        let duration: TimeInterval = 5 * 60
        
        connectivityTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.allowConnectivity(for: duration)
        }
    }
    
    private func allowConnectivity(for duration: TimeInterval) {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(duration)
        allowedConnectivityWindows.append(DateInterval(start: startDate, end: endDate))
    }
}

// MARK: - NetworkIsolationView

struct NetworkIsolationView: View {
    @StateObject private var viewModel = NetworkIsolationManager()
    
    var body: some View {
        VStack {
            Toggle("Enable Network Isolation", isOn: $viewModel.isNetworkIsolated)
                .onChange(of: viewModel.isNetworkIsolated) { isEnabled in
                    if isEnabled {
                        viewModel.enableNetworkIsolation()
                    } else {
                        viewModel.disableNetworkIsolation()
                    }
                }
            
            if viewModel.isNetworkIsolated {
                List(viewModel.allowedConnectivityWindows, id: \.self) { window in
                    Text("Connectivity from \(window.start, formatter: dateFormatter) to \(window.end, formatter: dateFormatter)")
                }
                .listStyle(PlainListStyle())
            }
        }
        .padding()
        .navigationTitle("Network Isolation")
    }
}

// MARK: - DateFormatter

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
}()