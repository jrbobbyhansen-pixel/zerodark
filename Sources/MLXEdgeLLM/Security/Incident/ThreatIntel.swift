import Foundation
import SwiftUI
import Combine

// MARK: - ThreatIntelService

class ThreatIntelService: ObservableObject {
    @Published private(set) var threatIntelligence: [ThreatIntelItem] = []
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadThreatIntelligence()
    }
    
    func loadThreatIntelligence() {
        // Simulate fetching from a local cache or network
        let sampleData = [
            ThreatIntelItem(id: UUID(), title: "Vulnerability Alert", description: "A new vulnerability has been discovered in the OpenSSL library."),
            ThreatIntelItem(id: UUID(), title: "IOC Update", description: "New indicators of compromise have been identified in recent cyber attacks.")
        ]
        
        DispatchQueue.main.async {
            self.threatIntelligence = sampleData
        }
    }
}

// MARK: - ThreatIntelItem

struct ThreatIntelItem: Identifiable {
    let id: UUID
    let title: String
    let description: String
}

// MARK: - ThreatIntelView

struct ThreatIntelView: View {
    @StateObject private var viewModel = ThreatIntelService()
    
    var body: some View {
        NavigationView {
            List(viewModel.threatIntelligence) { item in
                ThreatIntelRow(item: item)
            }
            .navigationTitle("Threat Intelligence Feed")
        }
    }
}

// MARK: - ThreatIntelRow

struct ThreatIntelRow: View {
    let item: ThreatIntelItem
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(item.title)
                .font(.headline)
            Text(item.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

struct ThreatIntelView_Previews: PreviewProvider {
    static var previews: some View {
        ThreatIntelView()
    }
}