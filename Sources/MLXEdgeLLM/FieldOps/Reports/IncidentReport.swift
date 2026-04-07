import SwiftUI
import Foundation
import CoreLocation
import AVFoundation

// MARK: - Models

struct Incident {
    var id = UUID()
    var title: String
    var description: String
    var location: CLLocationCoordinate2D
    var timestamp: Date
    var media: [MediaItem]
    var chainOfCustody: [String]
}

struct MediaItem {
    var id = UUID()
    var type: MediaType
    var data: Data
}

enum MediaType {
    case photo
    case video
}

// MARK: - View Models

class IncidentReportViewModel: ObservableObject {
    @Published var incident: Incident
    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0

    init(incident: Incident) {
        self.incident = incident
    }

    func addMedia(_ mediaItem: MediaItem) {
        incident.media.append(mediaItem)
    }

    func updateChainOfCustody(_ entry: String) {
        incident.chainOfCustody.append(entry)
    }

    func exportReport() async {
        isExporting = true
        // Simulate export process
        for i in 0...100 {
            exportProgress = Double(i) / 100.0
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        isExporting = false
        exportProgress = 0.0
    }
}

// MARK: - Views

struct IncidentReportView: View {
    @StateObject private var viewModel: IncidentReportViewModel

    init(incident: Incident) {
        _viewModel = StateObject(wrappedValue: IncidentReportViewModel(incident: incident))
    }

    var body: some View {
        VStack {
            Text("Incident Report")
                .font(.largeTitle)
                .padding()

            Form {
                Section(header: Text("Incident Details")) {
                    TextField("Title", text: Binding(
                        get: { viewModel.incident.title },
                        set: { viewModel.incident.title = $0 }
                    ))
                    TextField("Description", text: Binding(
                        get: { viewModel.incident.description },
                        set: { viewModel.incident.description = $0 }
                    ))
                    Text("Location: \(viewModel.incident.location.description)")
                    Text("Timestamp: \(viewModel.incident.timestamp, style: .date)")
                }

                Section(header: Text("Media")) {
                    ForEach(viewModel.incident.media) { mediaItem in
                        HStack {
                            Text(mediaItem.type.description)
                            Spacer()
                            Button(action: {
                                // Handle media preview
                            }) {
                                Text("Preview")
                            }
                        }
                    }
                    Button(action: {
                        // Handle media capture
                    }) {
                        Text("Add Media")
                    }
                }

                Section(header: Text("Chain of Custody")) {
                    ForEach(viewModel.incident.chainOfCustody, id: \.self) { entry in
                        Text(entry)
                    }
                    Button(action: {
                        // Handle chain of custody entry
                    }) {
                        Text("Add Entry")
                    }
                }
            }

            Button(action: {
                Task {
                    await viewModel.exportReport()
                }
            }) {
                Text("Export Report")
            }
            .disabled(viewModel.isExporting)
            .padding()
        }
        .navigationTitle("Incident Report")
    }
}

// MARK: - Previews

struct IncidentReportView_Previews: PreviewProvider {
    static var previews: some View {
        IncidentReportView(incident: Incident(
            title: "Test Incident",
            description: "This is a test incident report.",
            location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            timestamp: Date(),
            media: [],
            chainOfCustody: []
        ))
    }
}