import Foundation
import SwiftUI
import CoreLocation

// MARK: - NIMS/ICS Forms

struct NIMSForm201: Codable {
    var incidentNumber: String
    var incidentDate: Date
    var incidentTime: Date
    var incidentLocation: CLLocationCoordinate2D
    var incidentDescription: String
}

struct NIMSForm202: Codable {
    var incidentNumber: String
    var resourceType: String
    var resourceQuantity: Int
    var resourceLocation: CLLocationCoordinate2D
}

struct NIMSForm203: Codable {
    var incidentNumber: String
    var personnelName: String
    var personnelRole: String
    var personnelLocation: CLLocationCoordinate2D
}

struct NIMSForm204: Codable {
    var incidentNumber: String
    var communicationType: String
    var communicationDetails: String
}

struct NIMSForm205: Codable {
    var incidentNumber: String
    var safetyPrecautions: String
}

struct NIMSForm214: Codable {
    var incidentNumber: String
    var logisticsDetails: String
}

struct NIMSForm215: Codable {
    var incidentNumber: String
    var medicalDetails: String
}

// MARK: - ViewModel

class NimsFormsViewModel: ObservableObject {
    @Published var form201: NIMSForm201 = NIMSForm201(incidentNumber: "", incidentDate: Date(), incidentTime: Date(), incidentLocation: CLLocationCoordinate2D(), incidentDescription: "")
    @Published var form202: NIMSForm202 = NIMSForm202(incidentNumber: "", resourceType: "", resourceQuantity: 0, resourceLocation: CLLocationCoordinate2D())
    @Published var form203: NIMSForm203 = NIMSForm203(incidentNumber: "", personnelName: "", personnelRole: "", personnelLocation: CLLocationCoordinate2D())
    @Published var form204: NIMSForm204 = NIMSForm204(incidentNumber: "", communicationType: "", communicationDetails: "")
    @Published var form205: NIMSForm205 = NIMSForm205(incidentNumber: "", safetyPrecautions: "")
    @Published var form214: NIMSForm214 = NIMSForm214(incidentNumber: "", logisticsDetails: "")
    @Published var form215: NIMSForm215 = NIMSForm215(incidentNumber: "", medicalDetails: "")

    func validateForm201() -> Bool {
        // Add validation logic for form 201
        return !form201.incidentNumber.isEmpty && !form201.incidentDescription.isEmpty
    }

    func validateForm202() -> Bool {
        // Add validation logic for form 202
        return !form202.incidentNumber.isEmpty && !form202.resourceType.isEmpty && form202.resourceQuantity > 0
    }

    func validateForm203() -> Bool {
        // Add validation logic for form 203
        return !form203.incidentNumber.isEmpty && !form203.personnelName.isEmpty && !form203.personnelRole.isEmpty
    }

    func validateForm204() -> Bool {
        // Add validation logic for form 204
        return !form204.incidentNumber.isEmpty && !form204.communicationType.isEmpty && !form204.communicationDetails.isEmpty
    }

    func validateForm205() -> Bool {
        // Add validation logic for form 205
        return !form205.incidentNumber.isEmpty && !form205.safetyPrecautions.isEmpty
    }

    func validateForm214() -> Bool {
        // Add validation logic for form 214
        return !form214.incidentNumber.isEmpty && !form214.logisticsDetails.isEmpty
    }

    func validateForm215() -> Bool {
        // Add validation logic for form 215
        return !form215.incidentNumber.isEmpty && !form215.medicalDetails.isEmpty
    }

    func exportForm(_ form: Codable) -> Data? {
        return try? JSONEncoder().encode(form)
    }

    func shareViaMesh(_ data: Data) {
        // Implement mesh sharing logic
    }
}

// MARK: - SwiftUI Views

struct NIMSForm201View: View {
    @StateObject private var viewModel = NimsFormsViewModel()

    var body: some View {
        Form {
            TextField("Incident Number", text: $viewModel.form201.incidentNumber)
            DatePicker("Incident Date", selection: $viewModel.form201.incidentDate)
            DatePicker("Incident Time", selection: $viewModel.form201.incidentTime)
            Map(coordinateRegion: .constant(MKCoordinateRegion(center: viewModel.form201.incidentLocation, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))))
            TextField("Incident Description", text: $viewModel.form201.incidentDescription)
            Button("Submit") {
                if viewModel.validateForm201() {
                    if let data = viewModel.exportForm(viewModel.form201) {
                        viewModel.shareViaMesh(data)
                    }
                }
            }
        }
        .navigationTitle("NIMS Form 201")
    }
}

struct NIMSForm202View: View {
    @StateObject private var viewModel = NimsFormsViewModel()

    var body: some View {
        Form {
            TextField("Incident Number", text: $viewModel.form202.incidentNumber)
            TextField("Resource Type", text: $viewModel.form202.resourceType)
            Stepper("Resource Quantity: \(viewModel.form202.resourceQuantity)", value: $viewModel.form202.resourceQuantity, in: 1...)
            Map(coordinateRegion: .constant(MKCoordinateRegion(center: viewModel.form202.resourceLocation, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))))
            Button("Submit") {
                if viewModel.validateForm202() {
                    if let data = viewModel.exportForm(viewModel.form202) {
                        viewModel.shareViaMesh(data)
                    }
                }
            }
        }
        .navigationTitle("NIMS Form 202")
    }
}

struct NIMSForm203View: View {
    @StateObject private var viewModel = NimsFormsViewModel()

    var body: some View {
        Form {
            TextField("Incident Number", text: $viewModel.form203.incidentNumber)
            TextField("Personnel Name", text: $viewModel.form203.personnelName)
            TextField("Personnel Role", text: $viewModel.form203.personnelRole)
            Map(coordinateRegion: .constant(MKCoordinateRegion(center: viewModel.form203.personnelLocation, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))))
            Button("Submit") {
                if viewModel.validateForm203() {
                    if let data = viewModel.exportForm(viewModel.form203) {
                        viewModel.shareViaMesh(data)
                    }
                }
            }
        }
        .navigationTitle("NIMS Form 203")
    }
}

struct NIMSForm204View: View {
    @StateObject private var viewModel = NimsFormsViewModel()

    var body: some View {
        Form {
            TextField("Incident Number", text: $viewModel.form204.incidentNumber)
            TextField("Communication Type", text: $viewModel.form204.communicationType)
            TextField("Communication Details", text: $viewModel.form204.communicationDetails)
            Button("Submit") {
                if viewModel.validateForm204() {
                    if let data = viewModel.exportForm(viewModel.form204) {
                        viewModel.shareViaMesh(data)
                    }
                }
            }
        }
        .navigationTitle("NIMS Form 204")
    }
}

struct NIMSForm205View: View {
    @StateObject private var viewModel = NimsFormsViewModel()

    var body: some View {
        Form {
            TextField("Incident Number", text: $viewModel.form205.incidentNumber)
            TextField("Safety Precautions", text: $viewModel.form205.safetyPrecautions)
            Button("Submit") {
                if viewModel.validateForm205() {
                    if let data = viewModel.exportForm(viewModel.form205) {
                        viewModel.shareViaMesh(data)
                    }
                }
            }
        }
        .navigationTitle("NIMS Form 205")
    }
}

struct NIMSForm214View: View {
    @StateObject private var viewModel = NimsFormsViewModel()

    var body: some View {
        Form {
            TextField("Incident Number", text: $viewModel.form214.incidentNumber)
            TextField("Logistics Details", text: $viewModel.form214.logisticsDetails)
            Button("Submit") {
                if viewModel.validateForm214() {
                    if let data = viewModel.exportForm(viewModel.form214) {
                        viewModel.shareViaMesh(data)
                    }
                }
            }
        }
        .navigationTitle("NIMS Form 214")
    }
}

struct NIMSForm215View: View {
    @StateObject private var viewModel = NimsFormsViewModel()

    var body: some View {
        Form {
            TextField("Incident Number", text: $viewModel.form215.incidentNumber)
            TextField("Medical Details", text: $viewModel.form215.medicalDetails)
            Button("Submit") {
                if viewModel.validateForm215() {
                    if let data = viewModel.exportForm(viewModel.form215) {
                        viewModel.shareViaMesh(data)
                    }
                }
            }
        }
        .navigationTitle("NIMS Form 215")
    }
}

// MARK: - Preview

struct NIMSForm201View_Previews: PreviewProvider {
    static var previews: some View {
        NIMSForm201View()
    }
}

struct NIMSForm202View_Previews: PreviewProvider {
    static var previews: some View {
        NIMSForm202View()
    }
}

struct NIMSForm203View_Previews: PreviewProvider {
    static var previews: some View {
        NIMSForm203View()
    }
}

struct NIMSForm204View_Previews: PreviewProvider {
    static var previews: some View {
        NIMSForm204View()
    }
}

struct NIMSForm205View_Previews: PreviewProvider {
    static var previews: some View {
        NIMSForm205View()
    }
}

struct NIMSForm214View_Previews: PreviewProvider {
    static var previews: some View {
        NIMSForm214View()
    }
}

struct NIMSForm215View_Previews: PreviewProvider {
    static var previews: some View {
        NIMSForm215View()
    }
}