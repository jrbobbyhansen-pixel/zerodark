import SwiftUI

// MARK: - Main Content View
// Routes to the full-featured CoreContentView from AppNavigation

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    
    var body: some View {
        CoreContentView()
            .environmentObject(appState)
            .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
