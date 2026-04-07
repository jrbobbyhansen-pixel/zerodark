import Foundation
import SwiftUI

// MARK: - Communication Log Entry

struct CommsLogEntry: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let sender: String
    let channel: String
    let type: String
    let content: String
}

// MARK: - Communication Log Service

class CommsLogService: ObservableObject {
    @Published private(set) var entries: [CommsLogEntry] = []
    
    func addEntry(sender: String, channel: String, type: String, content: String) {
        let entry = CommsLogEntry(timestamp: Date(), sender: sender, channel: channel, type: type, content: content)
        entries.append(entry)
    }
    
    func filterBySender(_ sender: String) -> [CommsLogEntry] {
        entries.filter { $0.sender == sender }
    }
    
    func filterByChannel(_ channel: String) -> [CommsLogEntry] {
        entries.filter { $0.channel == channel }
    }
    
    func filterByType(_ type: String) -> [CommsLogEntry] {
        entries.filter { $0.type == type }
    }
    
    func searchContent(_ query: String) -> [CommsLogEntry] {
        entries.filter { $0.content.lowercased().contains(query.lowercased()) }
    }
    
    func exportForAnalysis() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(entries)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error exporting log: \(error.localizedDescription)"
        }
    }
}

// MARK: - Communication Log View Model

class CommsLogViewModel: ObservableObject {
    @Published var logService: CommsLogService
    @Published var filteredEntries: [CommsLogEntry] = []
    @Published var searchQuery: String = ""
    
    init(logService: CommsLogService) {
        self.logService = logService
        self.filteredEntries = logService.entries
    }
    
    func filterBySender(_ sender: String) {
        filteredEntries = logService.filterBySender(sender)
    }
    
    func filterByChannel(_ channel: String) {
        filteredEntries = logService.filterByChannel(channel)
    }
    
    func filterByType(_ type: String) {
        filteredEntries = logService.filterByType(type)
    }
    
    func searchContent(_ query: String) {
        searchQuery = query
        filteredEntries = logService.searchContent(query)
    }
}

// MARK: - Communication Log View

struct CommsLogView: View {
    @StateObject private var viewModel: CommsLogViewModel
    
    init(logService: CommsLogService) {
        _viewModel = StateObject(wrappedValue: CommsLogViewModel(logService: logService))
    }
    
    var body: some View {
        VStack {
            SearchBar(text: $viewModel.searchQuery, onSearch: viewModel.searchContent)
            
            List(viewModel.filteredEntries) { entry in
                VStack(alignment: .leading) {
                    Text("Sender: \(entry.sender)")
                        .font(.headline)
                    Text("Channel: \(entry.channel)")
                        .font(.subheadline)
                    Text("Type: \(entry.type)")
                        .font(.subheadline)
                    Text("Content: \(entry.content)")
                        .font(.body)
                }
            }
        }
        .navigationTitle("Communication Log")
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String
    var onSearch: (String) -> Void
    
    var body: some View {
        HStack {
            TextField("Search", text: $text, onCommit: {
                onSearch(text)
            })
            .padding(7)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            Button(action: {
                onSearch(text)
            }) {
                Image(systemName: "magnifyingglass")
                    .padding(7)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Preview

struct CommsLogView_Previews: PreviewProvider {
    static var previews: some View {
        CommsLogView(logService: CommsLogService())
    }
}