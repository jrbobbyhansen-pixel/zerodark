import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - CrossSection

struct CrossSection {
    let path: [CLLocationCoordinate2D]
    let elevationProfile: [Double]
    
    func exportAsProfile() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        
        var profileString = "Cross Section Profile:\n"
        for (index, coordinate) in path.enumerated() {
            let elevation = elevationProfile[index]
            profileString += "Point \(index + 1): \(coordinate.latitude), \(coordinate.longitude), \(formatter.string(from: elevation as NSNumber) ?? "N/A")\n"
        }
        return profileString
    }
}

// MARK: - CrossSectionService

class CrossSectionService: ObservableObject {
    @Published var crossSections: [CrossSection] = []
    
    func extractCrossSection(path: [CLLocationCoordinate2D]) async {
        // Simulate elevation data extraction
        let elevationProfile = path.map { _ in Double.random(in: 0...100) }
        let crossSection = CrossSection(path: path, elevationProfile: elevationProfile)
        await MainActor.run {
            crossSections.append(crossSection)
        }
    }
    
    func compareSections(_ section1: CrossSection, _ section2: CrossSection) -> String {
        // Simple comparison logic
        var comparisonResult = "Comparison of Cross Sections:\n"
        for i in 0..<min(section1.elevationProfile.count, section2.elevationProfile.count)) {
            comparisonResult += "Point \(i + 1): Section 1 = \(section1.elevationProfile[i]), Section 2 = \(section2.elevationProfile[i])\n"
        }
        return comparisonResult
    }
}

// MARK: - CrossSectionView

struct CrossSectionView: View {
    @StateObject private var viewModel = CrossSectionViewModel()
    
    var body: some View {
        VStack {
            Button("Extract Cross Section") {
                Task {
                    await viewModel.extractCrossSection()
                }
            }
            
            List(viewModel.crossSections, id: \.self) { section in
                VStack(alignment: .leading) {
                    Text("Path: \(section.path.map { "\($0.latitude), \($0.longitude)" }.joined(separator: " -> "))")
                    Text("Profile: \(section.exportAsProfile())")
                }
            }
            
            Button("Compare Sections") {
                if let firstSection = viewModel.crossSections.first, let secondSection = viewModel.crossSections.last {
                    let comparison = viewModel.compareSections(firstSection, secondSection)
                    print(comparison)
                }
            }
        }
        .padding()
    }
}

// MARK: - CrossSectionViewModel

class CrossSectionViewModel: ObservableObject {
    @Published var crossSections: [CrossSection] = []
    private let service = CrossSectionService()
    
    func extractCrossSection() async {
        let path = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195),
            CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4196)
        ]
        await service.extractCrossSection(path: path)
        crossSections = service.crossSections
    }
    
    func compareSections(_ section1: CrossSection, _ section2: CrossSection) -> String {
        return service.compareSections(section1, section2)
    }
}