import Foundation
import SwiftUI

// MARK: - IntelligenceReport

struct IntelligenceReport: Identifiable {
    let id = UUID()
    let source: String
    let reliability: Double
    let analysis: String
    let distributionControls: [String]
}

// MARK: - IntelligenceReportViewModel

class IntelligenceReportViewModel: ObservableObject {
    @Published var reports: [IntelligenceReport] = []
    
    func addReport(source: String, reliability: Double, analysis: String, distributionControls: [String]) {
        let newReport = IntelligenceReport(source: source, reliability: reliability, analysis: analysis, distributionControls: distributionControls)
        reports.append(newReport)
    }
}

// MARK: - IntelligenceReportView

struct IntelligenceReportView: View {
    @StateObject private var viewModel = IntelligenceReportViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.reports) { report in
                VStack(alignment: .leading) {
                    Text("Source: \(report.source)")
                        .font(.headline)
                    Text("Reliability: \(String(format: "%.2f", report.reliability))")
                        .font(.subheadline)
                    Text("Analysis: \(report.analysis)")
                        .font(.body)
                    Text("Distribution Controls: \(report.distributionControls.joined(separator: ", "))")
                        .font(.caption)
                }
            }
            .navigationTitle("Intelligence Reports")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new report logic here
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct IntelligenceReportView_Previews: PreviewProvider {
    static var previews: some View {
        IntelligenceReportView()
    }
}