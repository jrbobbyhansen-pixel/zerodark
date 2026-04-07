import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - AreaCalculator

class AreaCalculator: ObservableObject {
    @Published var polygons: [[CLLocationCoordinate2D]] = []
    @Published var totalArea: CLLocationDistance = 0

    func addPolygon(_ polygon: [CLLocationCoordinate2D]) {
        polygons.append(polygon)
        calculateTotalArea()
    }

    func removePolygon(at index: Int) {
        polygons.remove(at: index)
        calculateTotalArea()
    }

    private func calculateTotalArea() {
        totalArea = polygons.reduce(0) { $0 + polygonArea($1) }
    }

    private func polygonArea(_ polygon: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard polygon.count > 2 else { return 0 }
        var area: CLLocationDistance = 0
        let n = polygon.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += polygon[i].longitude * polygon[j].latitude
            area -= polygon[j].longitude * polygon[i].latitude
        }
        return abs(area) / 2
    }
}

// MARK: - PolygonView

struct PolygonView: View {
    @StateObject private var viewModel = AreaCalculator()

    var body: some View {
        Map(coordinateRegion: .constant(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), latitudinalMeters: 10000, longitudinalMeters: 10000)), annotationItems: viewModel.polygons) { polygon in
            MapPolyline(coordinates: polygon, count: polygon.count)
                .stroke(Color.blue, lineWidth: 3)
        }
        .onTapGesture { location in
            let coordinate = location.coordinate
            if let lastPolygon = viewModel.polygons.last {
                viewModel.polygons[viewModel.polygons.count - 1].append(coordinate)
            } else {
                viewModel.addPolygon([coordinate])
            }
        }
        .overlay(
            VStack {
                Text("Total Area: \(viewModel.totalArea, specifier: "%.2f") sq meters")
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                Button(action: {
                    viewModel.addPolygon([])
                }) {
                    Text("Start New Polygon")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
            .position(x: 20, y: 20)
        )
    }
}

// MARK: - Preview

struct PolygonView_Previews: PreviewProvider {
    static var previews: some View {
        PolygonView()
    }
}