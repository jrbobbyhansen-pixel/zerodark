import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - ToolSelector

class ToolSelector: ObservableObject {
    @Published var selectedTools: [Tool] = []
    @Published var query: String = ""
    
    private let tools: [Tool]
    
    init(tools: [Tool]) {
        self.tools = tools
    }
    
    func selectTools(for query: String) {
        self.query = query
        let relevantTools = tools.filter { $0.isRelevant(for: query) }
        selectedTools = relevantTools
    }
    
    func explainSelection() -> String {
        guard !selectedTools.isEmpty else {
            return "No tools are relevant for the query: \(query)"
        }
        
        let explanations = selectedTools.map { tool in
            "\(tool.name) is selected because \(tool.reason(for: query))"
        }
        
        return explanations.joined(separator: "\n")
    }
}

// MARK: - Tool

protocol Tool {
    var name: String { get }
    func isRelevant(for query: String) -> Bool
    func reason(for query: String) -> String
}

// MARK: - Example Tools

struct MapTool: Tool {
    var name: String = "Map Tool"
    
    func isRelevant(for query: String) -> Bool {
        query.lowercased().contains("map") || query.lowercased().contains("location")
    }
    
    func reason(for query: String) -> String {
        "The query mentions 'map' or 'location'."
    }
}

struct ARTool: Tool {
    var name: String = "AR Tool"
    
    func isRelevant(for query: String) -> Bool {
        query.lowercased().contains("ar") || query.lowercased().contains("augmented reality")
    }
    
    func reason(for query: String) -> String {
        "The query mentions 'AR' or 'augmented reality'."
    }
}

struct AudioTool: Tool {
    var name: String = "Audio Tool"
    
    func isRelevant(for query: String) -> Bool {
        query.lowercased().contains("audio") || query.lowercased().contains("sound")
    }
    
    func reason(for query: String) -> String {
        "The query mentions 'audio' or 'sound'."
    }
}

// MARK: - SwiftUI View

struct ToolSelectorView: View {
    @StateObject private var toolSelector = ToolSelector(tools: [MapTool(), ARTool(), AudioTool()])
    @State private var query: String = ""
    
    var body: some View {
        VStack {
            TextField("Enter query", text: $query)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button("Select Tools") {
                toolSelector.selectTools(for: query)
            }
            .padding()
            
            if !toolSelector.selectedTools.isEmpty {
                Text("Selected Tools:")
                    .font(.headline)
                
                ForEach(toolSelector.selectedTools, id: \.name) { tool in
                    Text(tool.name)
                }
            } else {
                Text("No tools selected.")
            }
            
            Button("Explain Selection") {
                let explanation = toolSelector.explainSelection()
                print(explanation)
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct ToolSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        ToolSelectorView()
    }
}