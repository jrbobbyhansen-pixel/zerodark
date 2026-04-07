import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - NetworkMapper

class NetworkMapper: ObservableObject {
    @Published var entities: [Entity] = []
    @Published var connections: [Connection] = []
    @Published var keyNodes: [Entity] = []

    func addEntity(_ entity: Entity) {
        entities.append(entity)
        updateConnections()
    }

    func removeEntity(_ entity: Entity) {
        entities.removeAll { $0.id == entity.id }
        updateConnections()
    }

    func updateConnections() {
        connections = entities.flatMap { entity in
            entities.filter { $0.id != entity.id }.map { Connection(from: entity, to: $0) }
        }
        identifyKeyNodes()
    }

    private func identifyKeyNodes() {
        // Simple heuristic: key nodes are those with the most connections
        let connectionCount = Dictionary(grouping: connections, by: \.from)
            .mapValues { $0.count }
        let maxConnections = connectionCount.values.max() ?? 0
        keyNodes = connectionCount.filter { $0.value == maxConnections }
            .map { $0.key }
    }
}

// MARK: - Entity

struct Entity: Identifiable {
    let id: UUID
    let name: String
    let location: CLLocationCoordinate2D
}

// MARK: - Connection

struct Connection {
    let from: Entity
    let to: Entity
}

// MARK: - NetworkMapView

struct NetworkMapView: View {
    @StateObject private var mapper = NetworkMapper()

    var body: some View {
        VStack {
            $name(entities: mapper.entities, connections: mapper.connections)
                .edgesIgnoringSafeArea(.all)
            KeyNodesView(keyNodes: mapper.keyNodes)
        }
        .onAppear {
            // Simulate adding entities
            mapper.addEntity(Entity(id: UUID(), name: "Entity 1", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)))
            mapper.addEntity(Entity(id: UUID(), name: "Entity 2", location: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195)))
            mapper.addEntity(Entity(id: UUID(), name: "Entity 3", location: CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4196)))
        }
    }
}

// MARK: - MapView

struct NetworkMapSnippet: UIViewRepresentable {
    let entities: [Entity]
    let connections: [Connection]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        uiView.removeOverlays(uiView.overlays)

        entities.forEach { entity in
            let annotation = MKPointAnnotation()
            annotation.coordinate = entity.location
            annotation.title = entity.name
            uiView.addAnnotation(annotation)
        }

        connections.forEach { connection in
            let overlay = MKPolyline(coordinates: [connection.from.location, connection.to.location], count: 2)
            uiView.addOverlay(overlay)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - KeyNodesView

struct KeyNodesView: View {
    let keyNodes: [Entity]

    var body: some View {
        VStack {
            Text("Key Nodes")
                .font(.headline)
            List(keyNodes) { node in
                Text(node.name)
            }
        }
        .padding()
    }
}