import SwiftUI
import CoreLocation

// MARK: - OneHandModeView

struct OneHandModeView: View {
    @StateObject private var viewModel = OneHandModeViewModel()
    
    var body: some View {
        VStack {
            // Top content
            $name()
                .frame(height: 300)
            
            // Bottom-aligned controls
            HStack {
                Button(action: viewModel.toggleOneHandMode) {
                    Text(viewModel.isOneHandModeEnabled ? "Disable One-Hand Mode" : "Enable One-Hand Mode")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
        }
        .edgesIgnoringSafeArea(.bottom)
        .swipeNavigation(viewModel: viewModel)
    }
}

// MARK: - OneHandModeViewModel

class OneHandModeViewModel: ObservableObject {
    @Published var isOneHandModeEnabled = false
    
    func toggleOneHandMode() {
        isOneHandModeEnabled.toggle()
    }
}

// MARK: - MapView

struct OneHandMapSnippet: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Update the map view if needed
    }
}

// MARK: - SwipeNavigation

extension View {
    func swipeNavigation(viewModel: OneHandModeViewModel) -> some View {
        self
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.width > 100 {
                            viewModel.isOneHandModeEnabled = true
                        } else if value.translation.width < -100 {
                            viewModel.isOneHandModeEnabled = false
                        }
                    }
            )
    }
}