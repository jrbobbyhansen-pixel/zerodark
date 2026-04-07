import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - QualificationCard Model

struct QualificationCard: Identifiable {
    let id = UUID()
    let name: String
    let skills: [String]
    let certifications: [String]
    let qrCode: String
}

// MARK: - QualificationCardViewModel

class QualificationCardViewModel: ObservableObject {
    @Published var qualificationCards: [QualificationCard] = []
    
    init() {
        // Load qualification cards from a data source
        loadQualificationCards()
    }
    
    private func loadQualificationCards() {
        // Example data
        qualificationCards = [
            QualificationCard(name: "John Doe", skills: ["AI", "Machine Learning"], certifications: ["Certified AI Developer"], qrCode: "QR12345"),
            QualificationCard(name: "Jane Smith", skills: ["iOS Development", "Swift"], certifications: ["Apple Developer"], qrCode: "QR67890")
        ]
    }
}

// MARK: - QualificationCardView

struct QualificationCardView: View {
    @StateObject private var viewModel = QualificationCardViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.qualificationCards) { card in
                NavigationLink(destination: QualificationCardDetailView(card: card)) {
                    VStack(alignment: .leading) {
                        Text(card.name)
                            .font(.headline)
                        Text("Skills: \(card.skills.joined(separator: ", "))")
                            .font(.subheadline)
                        Text("Certifications: \(card.certifications.joined(separator: ", "))")
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Qualification Cards")
        }
    }
}

// MARK: - QualificationCardDetailView

struct QualificationCardDetailView: View {
    let card: QualificationCard
    
    var body: some View {
        VStack {
            Text(card.name)
                .font(.largeTitle)
                .padding()
            
            Text("Skills: \(card.skills.joined(separator: ", "))")
                .font(.subheadline)
                .padding()
            
            Text("Certifications: \(card.certifications.joined(separator: ", "))")
                .font(.subheadline)
                .padding()
            
            QRCodeView(data: card.qrCode)
                .padding()
        }
        .navigationTitle("Qualification Card")
    }
}

// MARK: - QRCodeView

struct QRCodeView: View {
    let data: String
    
    var body: some View {
        Image(uiImage: generateQRCode(from: data))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: .ascii)
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("Q", forKey: "inputCorrectionLevel")
            if let output = filter.outputImage {
                let scaleX = 10.0
                let scaleY = 10.0
                let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
                let outputImage = output.transformed(by: transform)
                return UIImage(ciImage: outputImage)
            }
        }
        return nil
    }
}

// MARK: - Preview

struct QualificationCardView_Previews: PreviewProvider {
    static var previews: some View {
        QualificationCardView()
    }
}