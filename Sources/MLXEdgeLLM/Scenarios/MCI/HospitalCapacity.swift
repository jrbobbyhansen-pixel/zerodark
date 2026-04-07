import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Models

struct HospitalCapacity: Identifiable {
    let id: UUID
    let name: String
    let location: CLLocationCoordinate2D
    var traumaBeds: Int
    var burnBeds: Int
    var pedsBeds: Int
}

// MARK: - View Models

class HospitalCapacityViewModel: ObservableObject {
    @Published var hospitals: [HospitalCapacity] = []
    @Published var selectedHospital: HospitalCapacity?
    
    func updateCapacity(for hospital: HospitalCapacity, trauma: Int, burn: Int, peds: Int) {
        if let index = hospitals.firstIndex(where: { $0.id == hospital.id }) {
            hospitals[index].traumaBeds = trauma
            hospitals[index].burnBeds = burn
            hospitals[index].pedsBeds = peds
        }
    }
    
    func divertRecommendations() -> [String] {
        // Placeholder logic for divert recommendations
        return hospitals.filter { $0.traumaBeds > 0 || $0.burnBeds > 0 || $0.pedsBeds > 0 }
            .map { "Divert to \(hospital.name)" }
    }
}

// MARK: - Views

struct HospitalCapacityView: View {
    @StateObject private var viewModel = HospitalCapacityViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.hospitals) { hospital in
                NavigationLink(value: hospital) {
                    HospitalRow(hospital: hospital)
                }
            }
            .navigationDestination(for: HospitalCapacity.self) { hospital in
                HospitalDetailView(hospital: hospital, viewModel: viewModel)
            }
            .navigationTitle("Hospital Capacity")
        }
    }
}

struct HospitalRow: View {
    let hospital: HospitalCapacity
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(hospital.name)
                .font(.headline)
            Text("Trauma: \(hospital.traumaBeds), Burn: \(hospital.burnBeds), Peds: \(hospital.pedsBeds)")
                .font(.subheadline)
        }
    }
}

struct HospitalDetailView: View {
    let hospital: HospitalCapacity
    @ObservedObject var viewModel: HospitalCapacityViewModel
    
    var body: some View {
        VStack {
            Text(hospital.name)
                .font(.largeTitle)
                .padding()
            
            HStack {
                Text("Trauma Beds")
                Spacer()
                TextField("0", value: Binding(
                    get: { hospital.traumaBeds },
                    set: { viewModel.updateCapacity(for: hospital, trauma: $0, burn: hospital.burnBeds, peds: hospital.pedsBeds) }
                ), format: .number)
                .keyboardType(.numberPad)
            }
            .padding()
            
            HStack {
                Text("Burn Beds")
                Spacer()
                TextField("0", value: Binding(
                    get: { hospital.burnBeds },
                    set: { viewModel.updateCapacity(for: hospital, trauma: hospital.traumaBeds, burn: $0, peds: hospital.pedsBeds) }
                ), format: .number)
                .keyboardType(.numberPad)
            }
            .padding()
            
            HStack {
                Text("Peds Beds")
                Spacer()
                TextField("0", value: Binding(
                    get: { hospital.pedsBeds },
                    set: { viewModel.updateCapacity(for: hospital, trauma: hospital.traumaBeds, burn: hospital.burnBeds, peds: $0) }
                ), format: .number)
                .keyboardType(.numberPad)
            }
            .padding()
            
            Button(action: {
                let recommendations = viewModel.divertRecommendations()
                print("Divert Recommendations: \(recommendations)")
            }) {
                Text("Get Divert Recommendations")
            }
            .padding()
        }
        .navigationTitle("Edit Capacity")
    }
}

// MARK: - Previews

struct HospitalCapacityView_Previews: PreviewProvider {
    static var previews: some View {
        HospitalCapacityView()
    }
}