import Foundation
import SwiftUI

// MARK: - EmsProtocol

struct EmsProtocol: Identifiable, Codable {
    let id: UUID
    let title: String
    let jurisdiction: String
    let guidelines: String
    let drugDosages: [DrugDosage]
}

// MARK: - DrugDosage

struct DrugDosage: Identifiable, Codable {
    let id: UUID
    let drugName: String
    let dosage: String
}

// MARK: - EmsProtocolsService

class EmsProtocolsService: ObservableObject {
    @Published private(set) var protocols: [EmsProtocol] = []
    
    init() {
        loadProtocols()
    }
    
    private func loadProtocols() {
        guard let url = Bundle.main.url(forResource: "emsProtocols", withExtension: "json") else {
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decodedProtocols = try JSONDecoder().decode([EmsProtocol].self, from: data)
            protocols = decodedProtocols
        } catch {
            print("Failed to load EMS protocols: \(error)")
        }
    }
    
    func searchProtocols(by query: String, in jurisdiction: String? = nil) -> [EmsProtocol] {
        var filteredProtocols = protocols.filter { $0.title.lowercased().contains(query.lowercased()) }
        
        if let jurisdiction = jurisdiction {
            filteredProtocols = filteredProtocols.filter { $0.jurisdiction.lowercased() == jurisdiction.lowercased() }
        }
        
        return filteredProtocols
    }
}

// MARK: - EmsProtocolsView

struct EmsProtocolsView: View {
    @StateObject private var viewModel = EmsProtocolsService()
    @State private var searchQuery = ""
    @State private var selectedJurisdiction: String?
    
    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    TextField("Search protocols...", text: $searchQuery)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    Picker("Jurisdiction", selection: $selectedJurisdiction) {
                        Text("All").tag(nil as String?)
                        ForEach(Array(Set(viewModel.protocols.map { $0.jurisdiction })), id: \.self) { jurisdiction in
                            Text(jurisdiction).tag(jurisdiction)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding()
                }
                
                List(viewModel.searchProtocols(by: searchQuery, in: selectedJurisdiction), id: \.id) { protocol in
                    NavigationLink(destination: EmsProtocolDetailView(protocol: protocol)) {
                        VStack(alignment: .leading) {
                            Text(protocol.title)
                                .font(.headline)
                            Text(protocol.jurisdiction)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("EMS Protocols")
        }
    }
}

// MARK: - EmsProtocolDetailView

struct EmsProtocolDetailView: View {
    let protocol: EmsProtocol
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(protocol.title)
                .font(.largeTitle)
                .padding(.bottom)
            
            Text(protocol.jurisdiction)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom)
            
            Text(protocol.guidelines)
                .font(.body)
                .padding(.bottom)
            
            if !protocol.drugDosages.isEmpty {
                Text("Drug Dosages")
                    .font(.headline)
                    .padding(.top)
                
                ForEach(protocol.drugDosages, id: \.id) { dosage in
                    Text("\(dosage.drugName): \(dosage.dosage)")
                        .font(.body)
                }
            }
        }
        .padding()
        .navigationTitle(protocol.title)
    }
}

// MARK: - Preview

struct EmsProtocolsView_Previews: PreviewProvider {
    static var previews: some View {
        EmsProtocolsView()
    }
}