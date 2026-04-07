import Foundation
import SwiftUI

// MARK: - Certification Model

struct Certification: Identifiable, Codable {
    let id = UUID()
    var name: String
    var expirationDate: Date
    var isExpired: Bool {
        expirationDate < Date()
    }
}

// MARK: - CertificationTrackerViewModel

class CertificationTrackerViewModel: ObservableObject {
    @Published var certifications: [Certification] = []
    
    init() {
        loadCertifications()
    }
    
    func addCertification(name: String, expirationDate: Date) {
        let newCertification = Certification(name: name, expirationDate: expirationDate)
        certifications.append(newCertification)
        saveCertifications()
    }
    
    func removeCertification(at indexSet: IndexSet) {
        certifications.remove(atOffsets: indexSet)
        saveCertifications()
    }
    
    private func loadCertifications() {
        if let data = UserDefaults.standard.data(forKey: "Certifications"),
           let certifications = try? JSONDecoder().decode([Certification].self, from: data) {
            self.certifications = certifications
        }
    }
    
    private func saveCertifications() {
        if let encoded = try? JSONEncoder().encode(certifications) {
            UserDefaults.standard.set(encoded, forKey: "Certifications")
        }
    }
}

// MARK: - CertificationTrackerView

struct CertificationTrackerView: View {
    @StateObject private var viewModel = CertificationTrackerViewModel()
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.certifications) { certification in
                    HStack {
                        Text(certification.name)
                        Spacer()
                        Text(certification.expirationDate, style: .date)
                        if certification.isExpired {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
                .onDelete(perform: viewModel.removeCertification)
            }
            .navigationTitle("Certifications")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add certification logic
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct CertificationTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        CertificationTrackerView()
    }
}