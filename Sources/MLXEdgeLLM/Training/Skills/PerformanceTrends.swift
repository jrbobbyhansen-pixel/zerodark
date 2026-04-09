import Foundation
import SwiftUI

// MARK: - PerformanceTrends

class PerformanceTrends: ObservableObject {
    @Published var performanceData: [PerformanceEntry] = []
    @Published var trendAnalysis: TrendAnalysis?

    func recordPerformance(entry: PerformanceEntry) {
        performanceData.append(entry)
        analyzeTrends()
    }

    private func analyzeTrends() {
        guard performanceData.count > 1 else {
            trendAnalysis = nil
            return
        }

        let sortedData = performanceData.sorted { $0.timestamp < $1.timestamp }
        let firstEntry = sortedData.first!
        let lastEntry = sortedData.last!

        let improvement = lastEntry.score - firstEntry.score
        let trend = improvement > 0 ? .improving : improvement < 0 ? .degrading : .stable

        trendAnalysis = TrendAnalysis(improvement: improvement, trend: trend)
    }
}

// MARK: - PerformanceEntry

struct PerformanceEntry: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let score: Double
}

// MARK: - TrendAnalysis

struct TrendAnalysis {
    let improvement: Double
    let trend: Trend

    enum Trend {
        case improving
        case degrading
        case stable
    }
}

// MARK: - PerformanceTrendsView

struct PerformanceTrendsView: View {
    @StateObject private var viewModel = PerformanceTrends()

    var body: some View {
        VStack {
            if let analysis = viewModel.trendAnalysis {
                Text("Performance Trend: \(analysis.trend.description)")
                    .font(.headline)
                Text("Improvement: \(String(format: "%.2f", analysis.improvement))")
                    .font(.subheadline)
            } else {
                Text("No trend data available.")
                    .font(.subheadline)
            }

            Button("Record Performance") {
                let newEntry = PerformanceEntry(timestamp: Date(), score: Double.random(in: 0...100))
                viewModel.recordPerformance(entry: newEntry)
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
    }
}

// MARK: - Preview

struct PerformanceTrendsView_Previews: PreviewProvider {
    static var previews: some View {
        PerformanceTrendsView()
    }
}