// HospitalCapacity.swift — MCI hospital capacity tracker + divert logic.
//
// Real divert-recommendation math (previous impl had a scope bug using
// `hospital.name` outside the map-closure and returned all hospitals
// undifferentiated). The model + logic now produce a ranked list per
// patient-category with a combined capacity × inverse-distance score.

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Patient category

enum HospitalPatientCategory: String, CaseIterable, Codable {
    case trauma, burn, peds

    var label: String {
        switch self {
        case .trauma: return "Trauma"
        case .burn:   return "Burn"
        case .peds:   return "Pediatric"
        }
    }
}

// MARK: - Model

struct HospitalCapacity: Identifiable, Hashable {
    let id: UUID
    let name: String
    let location: CLLocationCoordinate2D
    var traumaBeds: Int
    var burnBeds: Int
    var pedsBeds: Int

    func availableBeds(for cat: HospitalPatientCategory) -> Int {
        switch cat {
        case .trauma: return traumaBeds
        case .burn:   return burnBeds
        case .peds:   return pedsBeds
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (a: HospitalCapacity, b: HospitalCapacity) -> Bool { a.id == b.id }
}

// MARK: - Divert recommendation

struct DivertRecommendation: Identifiable {
    let id = UUID()
    let hospital: HospitalCapacity
    let category: HospitalPatientCategory
    let distanceKm: Double
    let score: Double
    let availableBeds: Int
}

// MARK: - ViewModel

@MainActor
final class HospitalCapacityViewModel: ObservableObject {
    @Published var hospitals: [HospitalCapacity] = []
    @Published var selectedHospital: HospitalCapacity?
    @Published var patientLocation: CLLocationCoordinate2D?

    /// Updates bed counts for the given hospital. Silent no-op if not found.
    func updateCapacity(for hospital: HospitalCapacity, trauma: Int, burn: Int, peds: Int) {
        guard let index = hospitals.firstIndex(where: { $0.id == hospital.id }) else { return }
        hospitals[index].traumaBeds = max(0, trauma)
        hospitals[index].burnBeds   = max(0, burn)
        hospitals[index].pedsBeds   = max(0, peds)
    }

    /// Ranked divert list for a patient of `category`, from `origin` if provided
    /// (else `patientLocation`). Scoring: availableBeds × (1 / (1 + distanceKm)).
    /// Hospitals with zero beds in the category are excluded.
    func divertRecommendations(
        for category: HospitalPatientCategory,
        from origin: CLLocationCoordinate2D? = nil
    ) -> [DivertRecommendation] {
        let from = origin ?? patientLocation

        return hospitals
            .filter { $0.availableBeds(for: category) > 0 }
            .map { h -> DivertRecommendation in
                let beds = h.availableBeds(for: category)
                let km: Double
                if let from {
                    km = from.distance(to: h.location) / 1000.0
                } else {
                    km = 0   // unknown distance, treat as co-located
                }
                let score = Double(beds) * (1.0 / (1.0 + km))
                return DivertRecommendation(
                    hospital: h,
                    category: category,
                    distanceKm: km,
                    score: score,
                    availableBeds: beds
                )
            }
            .sorted { $0.score > $1.score }
    }
}

// MARK: - Views

struct HospitalCapacityView: View {
    @StateObject private var viewModel = HospitalCapacityViewModel()
    @State private var selectedCategory: HospitalPatientCategory = .trauma

    var body: some View {
        NavigationStack {
            List {
                Section("Hospitals") {
                    if viewModel.hospitals.isEmpty {
                        Text("No hospitals registered.").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(viewModel.hospitals) { hospital in
                            NavigationLink(value: hospital) { HospitalRow(hospital: hospital) }
                        }
                    }
                }
                Section("Divert (\(selectedCategory.label))") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(HospitalPatientCategory.allCases, id: \.self) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                    let recs = viewModel.divertRecommendations(for: selectedCategory)
                    if recs.isEmpty {
                        Text("No hospitals with available \(selectedCategory.label.lowercased()) beds.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(recs) { rec in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(rec.hospital.name).font(.subheadline.bold())
                                    Spacer()
                                    Text("\(rec.availableBeds) beds")
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.green)
                                }
                                Text(String(format: "%.1f km · score %.2f", rec.distanceKm, rec.score))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: HospitalCapacity.self) { hospital in
                HospitalDetailView(hospital: hospital, viewModel: viewModel)
            }
            .navigationTitle("Hospital Capacity")
        }
    }
}

private struct HospitalRow: View {
    let hospital: HospitalCapacity
    var body: some View {
        VStack(alignment: .leading) {
            Text(hospital.name).font(.headline)
            Text("Trauma: \(hospital.traumaBeds) · Burn: \(hospital.burnBeds) · Peds: \(hospital.pedsBeds)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

private struct HospitalDetailView: View {
    let hospital: HospitalCapacity
    @ObservedObject var viewModel: HospitalCapacityViewModel
    @State private var trauma: Int
    @State private var burn: Int
    @State private var peds: Int

    init(hospital: HospitalCapacity, viewModel: HospitalCapacityViewModel) {
        self.hospital = hospital
        self.viewModel = viewModel
        _trauma = State(initialValue: hospital.traumaBeds)
        _burn   = State(initialValue: hospital.burnBeds)
        _peds   = State(initialValue: hospital.pedsBeds)
    }

    var body: some View {
        Form {
            Section("Capacity") {
                Stepper("Trauma Beds: \(trauma)", value: $trauma, in: 0...200)
                Stepper("Burn Beds: \(burn)",     value: $burn,   in: 0...200)
                Stepper("Peds Beds: \(peds)",     value: $peds,   in: 0...200)
            }
            Section {
                Button("Save") {
                    viewModel.updateCapacity(for: hospital, trauma: trauma, burn: burn, peds: peds)
                }
            }
        }
        .navigationTitle(hospital.name)
    }
}

// MARK: - Previews

struct HospitalCapacityView_Previews: PreviewProvider {
    static var previews: some View { HospitalCapacityView() }
}
