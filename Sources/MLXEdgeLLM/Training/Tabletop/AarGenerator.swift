import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - AAR Generator

class AarGenerator: ObservableObject {
    @Published var report: AfterActionReport = AfterActionReport()
    @Published var photos: [UIImage] = []
    @Published var videos: [AVAsset] = []
    
    func generateReport() -> String {
        var reportString = "After Action Report\n\n"
        reportString += "Date: \(report.date.formatted(date: .long, time: .short))\n"
        reportString += "Location: \(report.location?.description ?? "N/A")\n"
        reportString += "Participants: \(report.participants.joined(separator: ", "))\n\n"
        reportString += "Findings:\n\(report.findings)\n\n"
        reportString += "Recommendations:\n\(report.recommendations)\n"
        return reportString
    }
    
    func addPhoto(_ photo: UIImage) {
        photos.append(photo)
    }
    
    func addVideo(_ video: AVAsset) {
        videos.append(video)
    }
}

// MARK: - Models

struct AfterActionReport {
    var date: Date = Date()
    var location: CLLocationCoordinate2D?
    var participants: [String] = []
    var findings: String = ""
    var recommendations: String = ""
}

// MARK: - SwiftUI View

struct AarView: View {
    @StateObject private var viewModel = AarGenerator()
    
    var body: some View {
        VStack {
            Text("After Action Report")
                .font(.largeTitle)
                .padding()
            
            Form {
                Section(header: Text("Date and Location")) {
                    DatePicker("Date", selection: $viewModel.report.date, displayedComponents: .date)
                    $name(location: $viewModel.report.location)
                }
                
                Section(header: Text("Participants")) {
                    ForEach($viewModel.report.participants, id: \.self) { $participant in
                        TextField("Participant", text: $participant)
                    }
                    Button(action: {
                        viewModel.report.participants.append("")
                    }) {
                        Text("Add Participant")
                    }
                }
                
                Section(header: Text("Findings")) {
                    TextEditor(text: $viewModel.report.findings)
                }
                
                Section(header: Text("Recommendations")) {
                    TextEditor(text: $viewModel.report.recommendations)
                }
                
                Section(header: Text("Media")) {
                    HStack {
                        Button(action: {
                            // Add photo logic
                        }) {
                            Image(systemName: "photo")
                            Text("Add Photo")
                        }
                        Button(action: {
                            // Add video logic
                        }) {
                            Image(systemName: "video.fill")
                            Text("Add Video")
                        }
                    }
                }
            }
            
            Button(action: {
                let report = viewModel.generateReport()
                print(report)
            }) {
                Text("Generate Report")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}

// MARK: - Map View

struct AarMapSnippet: UIViewRepresentable {
    @Binding var location: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        if let location = location {
            let coordinateRegion = MKCoordinateRegion(center: location, latitudinalMeters: 1000, longitudinalMeters: 1000)
            mapView.setRegion(coordinateRegion, animated: true)
        }
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let location = location {
            let coordinateRegion = MKCoordinateRegion(center: location, latitudinalMeters: 1000, longitudinalMeters: 1000)
            uiView.setRegion(coordinateRegion, animated: true)
        }
    }
}

// MARK: - Preview

struct AarView_Previews: PreviewProvider {
    static var previews: some View {
        AarView()
    }
}