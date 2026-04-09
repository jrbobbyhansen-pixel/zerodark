import SwiftUI
import ARKit

// MARK: - AngleMeasureView

struct AngleMeasureView: View {
    @StateObject private var viewModel = AngleMeasureViewModel()
    
    var body: some View {
        ARViewContainer(viewModel: viewModel)
            .edgesIgnoringSafeArea(.all)
            .overlay(AngleMeasureOverlay(viewModel: viewModel))
    }
}

// MARK: - ARViewContainer

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: AngleMeasureViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        arView.scene = SCNScene()
        arView.autoenablesDefaultLighting = true
        arView.showsStatistics = true
        arView.debugOptions = []
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Update ARSCNView if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate {
        var parent: ARViewContainer
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            // Handle new anchors
        }
        
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            // Handle updated anchors
        }
        
        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            // Handle removed anchors
        }
    }
}

// MARK: - AngleMeasureOverlay

struct AngleMeasureOverlay: View {
    @ObservedObject var viewModel: AngleMeasureViewModel
    
    var body: some View {
        VStack {
            Text("Angle: \(viewModel.angle, specifier: "%.2f")°")
                .font(.largeTitle)
                .padding()
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(10)
            
            Button(action: {
                viewModel.reset()
            }) {
                Text("Reset")
                    .font(.headline)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
        .position(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.maxY - 100)
    }
}

// MARK: - AngleMeasureViewModel

class AngleMeasureViewModel: ObservableObject {
    @Published var angle: Double = 0.0
    private var points: [SCNVector3] = []
    
    func handleTap(_ location: CGPoint, in arView: ARSCNView) {
        guard let result = arView.hitTest(location, types: .featurePoint).first else { return }
        let point = result.worldTransform.columns.3
        points.append(SCNVector3(point.x, point.y, point.z))
        
        if points.count == 3 {
            calculateAngle()
            points.removeFirst()
        }
    }
    
    private func calculateAngle() {
        let p1 = points[0]
        let p2 = points[1]
        let p3 = points[2]
        
        let v1 = p2 - p1
        let v2 = p3 - p2
        
        let dotProduct = v1.dotProduct(v2)
        let v1Length = v1.length()
        let v2Length = v2.length()
        
        let angleInRadians = acos(dotProduct / (v1Length * v2Length))
        angle = angleInRadians * 180 / .pi
    }
    
    func reset() {
        points.removeAll()
        angle = 0.0
    }
}