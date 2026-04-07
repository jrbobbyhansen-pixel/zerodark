import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - TreatmentAreaManager

class TreatmentAreaManager: ObservableObject {
    @Published var immediateZone: TreatmentZone
    @Published var delayedZone: TreatmentZone
    @Published var minorZone: TreatmentZone
    
    init() {
        self.immediateZone = TreatmentZone(type: .immediate)
        self.delayedZone = TreatmentZone(type: .delayed)
        self.minorZone = TreatmentZone(type: .minor)
    }
    
    func updatePatientCount(for zone: TreatmentZone, count: Int) {
        switch zone.type {
        case .immediate:
            immediateZone.patientCount = count
        case .delayed:
            delayedZone.patientCount = count
        case .minor:
            minorZone.patientCount = count
        }
    }
    
    func updateStaffing(for zone: TreatmentZone, count: Int) {
        switch zone.type {
        case .immediate:
            immediateZone.staffingCount = count
        case .delayed:
            delayedZone.staffingCount = count
        case .minor:
            minorZone.staffingCount = count
        }
    }
    
    func updateSupplies(for zone: TreatmentZone, supplies: [String: Int]) {
        switch zone.type {
        case .immediate:
            immediateZone.supplies = supplies
        case .delayed:
            delayedZone.supplies = supplies
        case .minor:
            minorZone.supplies = supplies
        }
    }
}

// MARK: - TreatmentZone

struct TreatmentZone: Identifiable {
    let id = UUID()
    let type: ZoneType
    var patientCount: Int
    var staffingCount: Int
    var supplies: [String: Int]
    
    init(type: ZoneType) {
        self.type = type
        self.patientCount = 0
        self.staffingCount = 0
        self.supplies = [:]
    }
}

// MARK: - ZoneType

enum ZoneType {
    case immediate
    case delayed
    case minor
}

// MARK: - TreatmentAreaView

struct TreatmentAreaView: View {
    @StateObject private var viewModel = TreatmentAreaManager()
    
    var body: some View {
        VStack {
            ZoneView(zone: viewModel.immediateZone, title: "Immediate Zone")
            ZoneView(zone: viewModel.delayedZone, title: "Delayed Zone")
            ZoneView(zone: viewModel.minorZone, title: "Minor Zone")
        }
        .padding()
    }
}

// MARK: - ZoneView

struct ZoneView: View {
    let zone: TreatmentZone
    let title: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
            
            HStack {
                Text("Patients: \(zone.patientCount)")
                Text("Staff: \(zone.staffingCount)")
            }
            
            Text("Supplies:")
            ForEach(zone.supplies.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                Text("\(key): \(value)")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Previews

struct TreatmentAreaView_Previews: PreviewProvider {
    static var previews: some View {
        TreatmentAreaView()
    }
}