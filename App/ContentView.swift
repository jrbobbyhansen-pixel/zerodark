import SwiftUI

// MARK: - Main Content View
// Routes to the full-featured CoreContentView from AppNavigation

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var isReady = false
    @State private var loadError: String?
    
    // Check if device can handle full app
    private var isLowMemoryDevice: Bool {
        ProcessInfo.processInfo.physicalMemory < 10_737_418_240 // 10GB
    }
    
    var body: some View {
        Group {
            if let error = loadError {
                // Show error state
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Unable to Load")
                        .font(.title)
                        .foregroundColor(.white)
                    
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Try Again") {
                        loadError = nil
                        isReady = false
                        startApp()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if isReady {
                CoreContentView()
                    .environmentObject(appState)
                    .preferredColorScheme(.dark)
            } else {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.cyan)
                    
                    Text("Loading ZeroDark...")
                        .foregroundColor(.white)
                    
                    if isLowMemoryDevice {
                        Text("Lite Mode (iPad)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onAppear {
                    startApp()
                }
            }
        }
    }
    
    private func startApp() {
        // Delay to let UI render first, then load components
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                isReady = true
            }
        }
    }
}

#Preview {
    ContentView()
}
