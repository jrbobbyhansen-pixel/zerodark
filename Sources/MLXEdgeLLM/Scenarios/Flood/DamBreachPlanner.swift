import Foundation
import SwiftUI
import CoreLocation

// MARK: - Models

struct InundationZone {
    let name: String
    let coordinates: [CLLocationCoordinate2D]
}

struct EvacuationRoute {
    let name: String
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
}

struct AssemblyPoint {
    let name: String
    let location: CLLocationCoordinate2D
}

struct TimeToImpact {
    let location: CLLocationCoordinate2D
    let time: TimeInterval
}

// MARK: - ViewModel

class DamBreachPlannerViewModel: ObservableObject {
    @Published var inundationZones: [InundationZone] = []
    @Published var evacuationRoutes: [EvacuationRoute] = []
    @Published var assemblyPoints: [AssemblyPoint] = []
    @Published var timeToImpact: [TimeToImpact] = []
    
    func loadScenario() {
        // Simulate loading data from a service or file
        inundationZones = [
            InundationZone(name: "Zone A", coordinates: [
                CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195),
                CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4196)
            ]),
            InundationZone(name: "Zone B", coordinates: [
                CLLocationCoordinate2D(latitude: 37.7760, longitude: -122.4204),
                CLLocationCoordinate2D(latitude: 37.7761, longitude: -122.4205),
                CLLocationCoordinate2D(latitude: 37.7762, longitude: -122.4206)
            ])
        ]
        
        evacuationRoutes = [
            EvacuationRoute(name: "Route 1", start: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), end: CLLocationCoordinate2D(latitude: 37.7760, longitude: -122.4204)),
            EvacuationRoute(name: "Route 2", start: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195), end: CLLocationCoordinate2D(latitude: 37.7761, longitude: -122.4205))
        ]
        
        assemblyPoints = [
            AssemblyPoint(name: "Point A", location: CLLocationCoordinate2D(latitude: 37.7755, longitude: -122.4200)),
            AssemblyPoint(name: "Point B", location: CLLocationCoordinate2D(latitude: 37.7756, longitude: -122.4201))
        ]
        
        timeToImpact = [
            TimeToImpact(location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), time: 300), // 5 minutes
            TimeToImpact(location: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195), time: 600)  // 10 minutes
        ]
    }
}

// MARK: - Views

struct DamBreachPlannerView: View {
    @StateObject private var viewModel = DamBreachPlannerViewModel()
    
    var body: some View {
        VStack {
            Text("Dam Breach Response Planner")
                .font(.largeTitle)
                .padding()
            
            List {
                Section(header: Text("Inundation Zones")) {
                    ForEach(viewModel.inundationZones) { zone in
                        Text(zone.name)
                    }
                }
                
                Section(header: Text("Evacuation Routes")) {
                    ForEach(viewModel.evacuationRoutes) { route in
                        Text("\(route.name): \(route.start.description) to \(route.end.description)")
                    }
                }
                
                Section(header: Text("Assembly Points")) {
                    ForEach(viewModel.assemblyPoints) { point in
                        Text("\(point.name): \(point.location.description)")
                    }
                }
                
                Section(header: Text("Time to Impact")) {
                    ForEach(viewModel.timeToImpact) { impact in
                        Text("\(impact.location.description): \(impact.time) seconds")
                    }
                }
            }
            .onAppear {
                viewModel.loadScenario()
            }
        }
    }
}

// MARK: - Preview

struct DamBreachPlannerView_Previews: PreviewProvider {
    static var previews: some View {
        DamBreachPlannerView()
    }
}