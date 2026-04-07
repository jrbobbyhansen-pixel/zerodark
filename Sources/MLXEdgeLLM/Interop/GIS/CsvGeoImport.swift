import Foundation
import SwiftUI
import CoreLocation

// MARK: - CSV Geo Importer

struct CsvGeoImport {
    let csvData: Data
    let coordinateFormatter: CoordinateFormatter
    
    init(csvData: Data, coordinateFormatter: CoordinateFormatter = CoordinateFormatter()) {
        self.csvData = csvData
        self.coordinateFormatter = coordinateFormatter
    }
    
    func importLocations() throws -> [CLLocationCoordinate2D] {
        let decoder = CSVDecoder()
        let rows = try decoder.decode([CsvGeoRow].self, from: csvData)
        
        return rows.compactMap { row in
            guard let latitude = coordinateFormatter.parse(row.latitude),
                  let longitude = coordinateFormatter.parse(row.longitude) else {
                return nil
            }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}

// MARK: - CSV Geo Row

struct CsvGeoRow: Codable {
    let latitude: String
    let longitude: String
}

// MARK: - Coordinate Formatter

class CoordinateFormatter {
    func parse(_ coordinateString: String) -> CLLocationDegrees? {
        let components = coordinateString.split(separator: ",")
        guard components.count == 2,
              let latitude = Double(components[0]),
              let longitude = Double(components[1]) else {
            return nil
        }
        return CLLocationDegrees(latitude: latitude, longitude: longitude)
    }
}

// MARK: - SwiftUI View

struct CsvGeoImportView: View {
    @StateObject private var viewModel = CsvGeoImportViewModel()
    
    var body: some View {
        VStack {
            Button("Import CSV") {
                viewModel.importCsv()
            }
            
            if let locations = viewModel.locations {
                List(locations) { location in
                    Text("Lat: \(location.latitude), Lon: \(location.longitude)")
                }
            }
        }
        .padding()
    }
}

// MARK: - View Model

class CsvGeoImportViewModel: ObservableObject {
    @Published var locations: [CLLocationCoordinate2D]? = nil
    
    func importCsv() {
        guard let csvData = "latitude,longitude\n37.7749,-122.4194\n34.0522,-118.2437".data(using: .utf8) else {
            return
        }
        
        let importer = CsvGeoImport(csvData: csvData)
        do {
            locations = try importer.importLocations()
        } catch {
            print("Error importing CSV: \(error)")
        }
    }
}