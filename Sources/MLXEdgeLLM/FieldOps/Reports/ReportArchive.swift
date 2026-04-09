import Foundation
import SwiftUI
import CoreLocation

// MARK: - Models

struct Report: Identifiable, Codable {
    let id: UUID
    let title: String
    let content: String
    let location: CLLocationCoordinate2D
    let timestamp: Date
}

// MARK: - Services

class ReportService: ObservableObject {
    @Published private(set) var reports: [Report] = []
    
    private let fileManager = FileManager.default
    private let archiveURL: URL
    
    init() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        archiveURL = documentsURL.appendingPathComponent("reports.archive")
        loadReports()
    }
    
    func addReport(_ report: Report) {
        reports.append(report)
        saveReports()
    }
    
    func removeReport(_ report: Report) {
        reports.removeAll { $0.id == report.id }
        saveReports()
    }
    
    func searchReports(query: String) -> [Report] {
        return reports.filter { $0.content.lowercased().contains(query.lowercased()) }
    }
    
    private func saveReports() {
        do {
            let data = try JSONEncoder().encode(reports)
            try data.write(to: archiveURL)
        } catch {
            print("Failed to save reports: \(error)")
        }
    }
    
    private func loadReports() {
        do {
            let data = try Data(contentsOf: archiveURL)
            reports = try JSONDecoder().decode([Report].self, from: data)
        } catch {
            print("Failed to load reports: \(error)")
        }
    }
}

// MARK: - Views

struct ReportArchiveView: View {
    @StateObject private var viewModel = ReportService()
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $searchText)
                    .padding()
                
                List(filteredReports, id: \.id) { report in
                    ReportRow(report: report)
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Report Archive")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addReport) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
    
    private var filteredReports: [Report] {
        if searchText.isEmpty {
            return viewModel.reports
        } else {
            return viewModel.searchReports(query: searchText)
        }
    }
    
    private func addReport() {
        let newReport = Report(id: UUID(), title: "New Report", content: "", location: CLLocationCoordinate2D(), timestamp: Date())
        viewModel.addReport(newReport)
    }
}

struct ReportRow: View {
    let report: Report
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(report.title)
                .font(.headline)
            Text(report.content)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Location: \(report.location.latitude), \(report.location.longitude)")
                .font(.caption)
                .foregroundColor(.gray)
            Text("Timestamp: \(report.timestamp, style: .date)")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            TextField("Search", text: $text)
                .padding(7)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.trailing, 10)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - Preview

struct ReportArchiveView_Previews: PreviewProvider {
    static var previews: some View {
        ReportArchiveView()
    }
}