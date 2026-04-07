import SwiftUI
import Foundation
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Models

struct DamageCategory: Identifiable {
    let id = UUID()
    let name: String
    let description: String
}

struct DamageReport: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let category: DamageCategory
    let severity: Int
    let photos: [UIImage]
    let costEstimate: Double
}

// MARK: - View Models

class DamageAssessmentViewModel: ObservableObject {
    @Published var categories: [DamageCategory] = [
        DamageCategory(name: "Structural", description: "Damage to buildings or infrastructure"),
        DamageCategory(name: "Electrical", description: "Damage to electrical systems"),
        DamageCategory(name: "Water", description: "Damage to water systems"),
        DamageCategory(name: "Communication", description: "Damage to communication systems")
    ]
    
    @Published var selectedCategory: DamageCategory?
    @Published var severity: Int = 1
    @Published var photos: [UIImage] = []
    @Published var costEstimate: Double = 0.0
    @Published var location: CLLocationCoordinate2D?
    
    func addPhoto(_ image: UIImage) {
        photos.append(image)
    }
    
    func removePhoto(at index: Int) {
        photos.remove(at: index)
    }
    
    func submitReport() {
        guard let location = location, let category = selectedCategory else { return }
        let report = DamageReport(location: location, category: category, severity: severity, photos: photos, costEstimate: costEstimate)
        // Submit report to server or local storage
    }
}

// MARK: - Views

struct DamageAssessmentView: View {
    @StateObject private var viewModel = DamageAssessmentViewModel()
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Category")) {
                    Picker("Select Category", selection: $viewModel.selectedCategory) {
                        ForEach(viewModel.categories) { category in
                            Text(category.name)
                        }
                    }
                }
                
                Section(header: Text("Severity")) {
                    Stepper("Severity: \(viewModel.severity)", value: $viewModel.severity, in: 1...5)
                }
                
                Section(header: Text("Photos")) {
                    ForEach(viewModel.photos.indices, id: \.self) { index in
                        Image(uiImage: viewModel.photos[index])
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .onTapGesture {
                                viewModel.removePhoto(at: index)
                            }
                    }
                    Button(action: {
                        // Open camera or photo library
                    }) {
                        Text("Add Photo")
                    }
                }
                
                Section(header: Text("Cost Estimate")) {
                    TextField("Cost Estimate", value: $viewModel.costEstimate, formatter: NumberFormatter())
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Damage Assessment")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.submitReport()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Submit")
                    }
                }
            }
        }
    }
}

// MARK: - Previews

struct DamageAssessmentView_Previews: PreviewProvider {
    static var previews: some View {
        DamageAssessmentView()
    }
}