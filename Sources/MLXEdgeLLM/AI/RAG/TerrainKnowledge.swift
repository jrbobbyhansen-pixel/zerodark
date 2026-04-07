import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Terrain Knowledge Base

struct TerrainKnowledgeBase {
    var hazards: [Hazard]
    var routes: [Route]
    var waterSources: [WaterSource]
    var shelterLocations: [ShelterLocation]
}

// MARK: - Hazard

struct Hazard: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let description: String
}

// MARK: - Route

struct Route: Identifiable {
    let id = UUID()
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let description: String
}

// MARK: - WaterSource

struct WaterSource: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let description: String
}

// MARK: - ShelterLocation

struct ShelterLocation: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let description: String
}

// MARK: - TerrainKnowledgeService

class TerrainKnowledgeService: ObservableObject {
    @Published private(set) var knowledgeBase: TerrainKnowledgeBase = TerrainKnowledgeBase(hazards: [], routes: [], waterSources: [], shelterLocations: [])
    
    func addHazard(_ hazard: Hazard) {
        knowledgeBase.hazards.append(hazard)
    }
    
    func addRoute(_ route: Route) {
        knowledgeBase.routes.append(route)
    }
    
    func addWaterSource(_ waterSource: WaterSource) {
        knowledgeBase.waterSources.append(waterSource)
    }
    
    func addShelterLocation(_ shelterLocation: ShelterLocation) {
        knowledgeBase.shelterLocations.append(shelterLocation)
    }
    
    func syncWithCommunity() async {
        // Placeholder for mesh-sync logic
    }
}

// MARK: - TerrainKnowledgeView

struct TerrainKnowledgeView: View {
    @StateObject private var viewModel = TerrainKnowledgeService()
    
    var body: some View {
        VStack {
            $name(knowledgeBase: viewModel.knowledgeBase)
                .edgesIgnoringSafeArea(.all)
            
            Button(action: {
                // Add new hazard, route, water source, or shelter location
            }) {
                Text("Add New")
            }
        }
        .onAppear {
            Task {
                await viewModel.syncWithCommunity()
            }
        }
    }
}

// MARK: - MapView

struct TerrainKnowledgeMapSnippet: UIViewRepresentable {
    let knowledgeBase: TerrainKnowledgeBase
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        uiView.addAnnotations(knowledgeBase.hazards.map { HazardAnnotation(hazard: $0) })
        uiView.addAnnotations(knowledgeBase.routes.map { RouteAnnotation(route: $0) })
        uiView.addAnnotations(knowledgeBase.waterSources.map { WaterSourceAnnotation(waterSource: $0) })
        uiView.addAnnotations(knowledgeBase.shelterLocations.map { ShelterLocationAnnotation(shelterLocation: $0) })
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let hazardAnnotation = annotation as? HazardAnnotation {
                let view = MKPinAnnotationView(annotation: hazardAnnotation, reuseIdentifier: "Hazard")
                view.pinTintColor = .red
                return view
            } else if let routeAnnotation = annotation as? RouteAnnotation {
                let view = MKPolylineRenderer(overlay: routeAnnotation.polyline)
                view.strokeColor = .blue
                view.lineWidth = 3
                return view
            } else if let waterSourceAnnotation = annotation as? WaterSourceAnnotation {
                let view = MKPinAnnotationView(annotation: waterSourceAnnotation, reuseIdentifier: "WaterSource")
                view.pinTintColor = .blue
                return view
            } else if let shelterLocationAnnotation = annotation as? ShelterLocationAnnotation {
                let view = MKPinAnnotationView(annotation: shelterLocationAnnotation, reuseIdentifier: "ShelterLocation")
                view.pinTintColor = .green
                return view
            }
            return nil
        }
    }
}

// MARK: - HazardAnnotation

class HazardAnnotation: NSObject, MKAnnotation {
    let hazard: Hazard
    
    var coordinate: CLLocationCoordinate2D {
        return hazard.location
    }
    
    var title: String? {
        return hazard.description
    }
    
    init(hazard: Hazard) {
        self.hazard = hazard
    }
}

// MARK: - RouteAnnotation

class RouteAnnotation: NSObject, MKAnnotation {
    let route: Route
    let polyline: MKPolyline
    
    var coordinate: CLLocationCoordinate2D {
        return route.start
    }
    
    var title: String? {
        return route.description
    }
    
    init(route: Route) {
        self.route = route
        self.polyline = MKPolyline(coordinates: [route.start, route.end], count: 2)
    }
}

// MARK: - WaterSourceAnnotation

class WaterSourceAnnotation: NSObject, MKAnnotation {
    let waterSource: WaterSource
    
    var coordinate: CLLocationCoordinate2D {
        return waterSource.location
    }
    
    var title: String? {
        return waterSource.description
    }
    
    init(waterSource: WaterSource) {
        self.waterSource = waterSource
    }
}

// MARK: - ShelterLocationAnnotation

class ShelterLocationAnnotation: NSObject, MKAnnotation {
    let shelterLocation: ShelterLocation
    
    var coordinate: CLLocationCoordinate2D {
        return shelterLocation.location
    }
    
    var title: String? {
        return shelterLocation.description
    }
    
    init(shelterLocation: ShelterLocation) {
        self.shelterLocation = shelterLocation
    }
}