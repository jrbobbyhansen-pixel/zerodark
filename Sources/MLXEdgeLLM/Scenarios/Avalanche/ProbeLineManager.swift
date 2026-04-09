import Foundation
import SwiftUI
import CoreLocation

// MARK: - ProbeLineManager

class ProbeLineManager: ObservableObject {
    @Published var lines: [ProbeLine] = []
    @Published var activeLineIndex: Int? = nil
    @Published var strikeLocations: [CLLocationCoordinate2D] = []
    
    func addLine(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) {
        let newLine = ProbeLine(start: start, end: end)
        lines.append(newLine)
        activeLineIndex = lines.count - 1
    }
    
    func markStrike(at location: CLLocationCoordinate2D) {
        strikeLocations.append(location)
    }
    
    func removeLine(at index: Int) {
        lines.remove(at: index)
        if activeLineIndex == index {
            activeLineIndex = nil
        } else if activeLineIndex! > index {
            activeLineIndex! -= 1
        }
    }
    
    func activateLine(at index: Int) {
        activeLineIndex = index
    }
}

// MARK: - ProbeLine

struct ProbeLine {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    var progress: Double = 0.0
    
    mutating func updateProgress(to newProgress: Double) {
        progress = min(max(newProgress, 0.0), 1.0)
    }
}

// MARK: - ProbeLineView

struct ProbeLineView: View {
    @ObservedObject var manager: ProbeLineManager
    @State private var isAddingLine = false
    @State private var startLocation: CLLocationCoordinate2D?
    @State private var endLocation: CLLocationCoordinate2D?
    
    var body: some View {
        VStack {
            $name(manager: manager)
                .edgesIgnoringSafeArea(.all)
            
            HStack {
                Button(action: {
                    isAddingLine = true
                }) {
                    Text("Add Line")
                }
                
                Button(action: {
                    if let index = manager.activeLineIndex {
                        manager.lines[index].updateProgress(to: manager.lines[index].progress + 0.1)
                    }
                }) {
                    Text("Advance Progress")
                }
            }
            
            if isAddingLine {
                HStack {
                    Button(action: {
                        startLocation = nil
                        endLocation = nil
                        isAddingLine = false
                    }) {
                        Text("Cancel")
                    }
                    
                    Button(action: {
                        if let start = startLocation, let end = endLocation {
                            manager.addLine(start: start, end: end)
                            startLocation = nil
                            endLocation = nil
                            isAddingLine = false
                        }
                    }) {
                        Text("Done")
                    }
                }
            }
        }
    }
}

// MARK: - MapView

struct ProbeLineMapSnippet: UIViewRepresentable {
    @ObservedObject var manager: ProbeLineManager
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        
        for line in manager.lines {
            let overlay = MKPolyline(coordinates: [line.start, line.end], count: 2)
            uiView.addOverlay(overlay)
        }
        
        for strike in manager.strikeLocations {
            let annotation = MKPointAnnotation()
            annotation.coordinate = strike
            uiView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation as? MKPointAnnotation {
                parent.manager.markStrike(at: annotation.coordinate)
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}