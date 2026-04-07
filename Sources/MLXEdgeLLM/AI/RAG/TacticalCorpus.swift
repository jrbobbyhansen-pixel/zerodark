import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - TacticalCorpus

class TacticalCorpus: ObservableObject {
    static let shared = TacticalCorpus()

    @Published var firstAidKnowledge: [String: String] = [:]
    @Published var survivalKnowledge: [String: String] = [:]
    @Published var navigationKnowledge: [String: String] = [:]
    @Published var radioProcedures: [String: String] = [:]
    @Published var sarProtocols: [String: String] = [:]
    @Published var weatherPatterns: [String: String] = [:]

    init() {
        loadKnowledgeBase()
    }

    // MARK: - Indexable Documents (v6 — for multi-modal RAG fusion)

    func allDocuments() -> [(key: String, content: String, category: String)] {
        var docs: [(key: String, content: String, category: String)] = []
        for (key, value) in firstAidKnowledge {
            docs.append((key: key, content: value, category: "First Aid"))
        }
        for (key, value) in survivalKnowledge {
            docs.append((key: key, content: value, category: "Survival"))
        }
        for (key, value) in navigationKnowledge {
            docs.append((key: key, content: value, category: "Navigation"))
        }
        for (key, value) in radioProcedures {
            docs.append((key: key, content: value, category: "Radio"))
        }
        for (key, value) in sarProtocols {
            docs.append((key: key, content: value, category: "SAR"))
        }
        for (key, value) in weatherPatterns {
            docs.append((key: key, content: value, category: "Weather"))
        }
        return docs
    }

    private func loadKnowledgeBase() {
        firstAidKnowledge = [
            "CPR": "Cardiopulmonary resuscitation involves chest compressions and rescue breaths to manually preserve intact brain function until further measures are taken to restore spontaneous blood circulation and breathing in a person who is in cardiac arrest.",
            "Tourniquet": "A tourniquet is a device used to stop severe bleeding by applying pressure to the limb above the wound."
        ]

        survivalKnowledge = [
            "Water Purification": "Boiling water is the most effective way to purify water. Bring water to a rolling boil for at least one minute.",
            "Fire Building": "To build a fire, gather tinder, kindling, and fuel wood. Arrange the tinder in a teepee shape, add kindling, and then add fuel wood."
        ]

        navigationKnowledge = [
            "Map Reading": "Use a map to determine your location and plan your route. Pay attention to scale, symbols, and compass orientation.",
            "GPS Navigation": "Use a GPS device to get real-time location and directions. Ensure the device is charged and has a clear view of the sky."
        ]

        radioProcedures = [
            "Channel Selection": "Select the appropriate channel for your communication needs. Avoid using channels that are likely to be crowded.",
            "Signal Check": "Before starting a transmission, perform a signal check to ensure the other party can hear you."
        ]

        sarProtocols = [
            "Search and Rescue": "Search and rescue operations involve locating and rescuing individuals in distress. Follow established protocols and coordinate with local authorities.",
            "Evacuation": "In case of an emergency, follow the evacuation plan and move to a safe location."
        ]

        weatherPatterns = [
            "Rain": "Rain can cause slippery roads and flooding. Ensure you have appropriate gear and be cautious of standing water.",
            "Wind": "Strong winds can cause damage and make it difficult to navigate. Stay informed about wind conditions and adjust your plans accordingly."
        ]
    }
}

// MARK: - TacticalCorpusView

struct TacticalCorpusView: View {
    @StateObject private var viewModel = TacticalCorpus()

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("First Aid")) {
                    ForEach(viewModel.firstAidKnowledge.keys.sorted(), id: \.self) { key in
                        NavigationLink(destination: DetailView(title: key, content: viewModel.firstAidKnowledge[key] ?? "")) {
                            Text(key)
                        }
                    }
                }

                Section(header: Text("Survival")) {
                    ForEach(viewModel.survivalKnowledge.keys.sorted(), id: \.self) { key in
                        NavigationLink(destination: DetailView(title: key, content: viewModel.survivalKnowledge[key] ?? "")) {
                            Text(key)
                        }
                    }
                }

                Section(header: Text("Navigation")) {
                    ForEach(viewModel.navigationKnowledge.keys.sorted(), id: \.self) { key in
                        NavigationLink(destination: DetailView(title: key, content: viewModel.navigationKnowledge[key] ?? "")) {
                            Text(key)
                        }
                    }
                }

                Section(header: Text("Radio Procedures")) {
                    ForEach(viewModel.radioProcedures.keys.sorted(), id: \.self) { key in
                        NavigationLink(destination: DetailView(title: key, content: viewModel.radioProcedures[key] ?? "")) {
                            Text(key)
                        }
                    }
                }

                Section(header: Text("SAR Protocols")) {
                    ForEach(viewModel.sarProtocols.keys.sorted(), id: \.self) { key in
                        NavigationLink(destination: DetailView(title: key, content: viewModel.sarProtocols[key] ?? "")) {
                            Text(key)
                        }
                    }
                }

                Section(header: Text("Weather Patterns")) {
                    ForEach(viewModel.weatherPatterns.keys.sorted(), id: \.self) { key in
                        NavigationLink(destination: DetailView(title: key, content: viewModel.weatherPatterns[key] ?? "")) {
                            Text(key)
                        }
                    }
                }
            }
            .navigationTitle("Tactical Knowledge Corpus")
        }
    }
}

// MARK: - DetailView

struct DetailView: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 8)

            Text(content)
                .font(.body)
        }
        .padding()
        .navigationTitle(title)
    }
}

// MARK: - Preview

struct TacticalCorpusView_Previews: PreviewProvider {
    static var previews: some View {
        TacticalCorpusView()
    }
}