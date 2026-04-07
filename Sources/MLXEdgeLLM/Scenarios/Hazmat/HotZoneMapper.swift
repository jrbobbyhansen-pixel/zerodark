import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Zone Types

enum ZoneType: String, Codable {
    case hot
    case warm
    case cold
}

// MARK: - Zone

struct Zone: Identifiable, Codable {
    let id = UUID()
    let type: ZoneType
    let coordinates: [CLLocationCoordinate2D]
}

// MARK: - Person

struct Person: Identifiable, Codable {
    let id = UUID()
    let name: String
    let zone: ZoneType
    let entryTime: Date
    let exitTime: Date?
}

// MARK: - ZoneManager

class ZoneManager: ObservableObject {
    @Published var zones: [Zone] = []
    @Published var people: [Person] = []
    
    func addZone(_ zone: Zone) {
        zones.append(zone)
    }
    
    func addPerson(_ person: Person) {
        people.append(person)
    }
    
    func updatePersonZone(_ personID: UUID, newZone: ZoneType) {
        if let index = people.firstIndex(where: { $0.id == personID }) {
            people[index].zone = newZone
        }
    }
    
    func logPersonEntry(_ person: Person) {
        people.append(person)
    }
    
    func logPersonExit(_ personID: UUID) {
        if let index = people.firstIndex(where: { $0.id == personID }) {
            people[index].exitTime = Date()
        }
    }
}

// MARK: - HotZoneMapperView

struct HotZoneMapperView: View {
    @StateObject private var viewModel = ZoneManager()
    
    var body: some View {
        VStack {
            $name(zones: $viewModel.zones, people: $viewModel.people)
                .edgesIgnoringSafeArea(.all)
            
            Button("Add Hot Zone") {
                let newZone = Zone(type: .hot, coordinates: [])
                viewModel.addZone(newZone)
            }
            .padding()
        }
    }
}

// MARK: - MapView

struct HotZoneMapSnippet: UIViewRepresentable {
    @Binding var zones: [Zone]
    @Binding var people: [Person]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        uiView.removeOverlays(uiView.overlays)
        
        for zone in zones {
            let polygon = MKPolygon(coordinates: zone.coordinates, count: zone.coordinates.count)
            uiView.addOverlay(polygon)
        }
        
        for person in people {
            let annotation = MKPointAnnotation()
            annotation.title = person.name
            annotation.subtitle = "Zone: \(person.zone.rawValue)"
            uiView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation as? MKPointAnnotation {
                print("Selected person: \(annotation.title ?? "")")
            }
        }
    }
}

// MARK: - Preview

struct HotZoneMapperView_Previews: PreviewProvider {
    static var previews: some View {
        HotZoneMapperView()
    }
}