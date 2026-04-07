import SwiftUI
import Foundation

// MARK: - HelpSystem

class HelpSystem: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var filteredHelpItems: [HelpItem] = []
    @Published var selectedHelpItem: HelpItem? = nil
    
    private let helpItems: [HelpItem] = [
        HelpItem(title: "Context-sensitive Help", content: "Provides help based on the current context."),
        HelpItem(title: "Searchable Documentation", content: "Search through the documentation for quick answers."),
        HelpItem(title: "FAQ", content: "Frequently Asked Questions and their answers."),
        HelpItem(title: "Offline Available", content: "All help content is available offline.")
    ]
    
    init() {
        filteredHelpItems = helpItems
    }
    
    func searchHelpItems() {
        if searchQuery.isEmpty {
            filteredHelpItems = helpItems
        } else {
            filteredHelpItems = helpItems.filter { $0.title.lowercased().contains(searchQuery.lowercased()) }
        }
    }
}

// MARK: - HelpItem

struct HelpItem: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}

// MARK: - HelpView

struct HelpView: View {
    @StateObject private var helpSystem = HelpSystem()
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $helpSystem.searchQuery, onSearch: helpSystem.searchHelpItems)
                    .padding()
                
                List(helpSystem.filteredHelpItems) { item in
                    NavigationLink(value: item) {
                        Text(item.title)
                    }
                }
                .navigationDestination(for: HelpItem.self) { item in
                    HelpDetailView(item: item)
                }
            }
            .navigationTitle("Help")
        }
    }
}

// MARK: - HelpDetailView

struct HelpDetailView: View {
    let item: HelpItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.title)
                .font(.largeTitle)
                .padding(.top)
            
            Text(item.content)
                .font(.body)
        }
        .padding()
        .navigationTitle(item.title)
    }
}

// MARK: - SearchBar

struct SearchBar: View {
    @Binding var text: String
    let onSearch: () -> Void
    
    var body: some View {
        HStack {
            TextField("Search", text: $text, onCommit: onSearch)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .padding()
            }
        }
    }
}

// MARK: - Preview

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView()
    }
}