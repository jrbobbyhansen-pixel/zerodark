import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - SopAssistant

class SopAssistant: ObservableObject {
    @Published var query: String = ""
    @Published var results: [SopResult] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?

    private let knowledgeBase: KnowledgeBase

    init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    func performQuery() {
        isLoading = true
        error = nil
        results = []

        Task {
            do {
                let results = try await knowledgeBase.querySop(query: query)
                DispatchQueue.main.async {
                    self.results = results
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - SopResult

struct SopResult: Identifiable {
    let id: UUID
    let section: String
    let citation: String
}

// MARK: - KnowledgeBase

actor KnowledgeBase {
    private let sopData: [SopSection]

    init(sopData: [SopSection]) {
        self.sopData = sopData
    }

    func querySop(query: String) async throws -> [SopResult] {
        // Simulate async query
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay

        // Basic search logic
        let lowercasedQuery = query.lowercased()
        let filteredSections = sopData.filter { section in
            section.content.lowercased().contains(lowercasedQuery)
        }

        return filteredSections.map { section in
            SopResult(id: UUID(), section: section.title, citation: section.citation)
        }
    }
}

// MARK: - SopSection

struct SopSection {
    let title: String
    let content: String
    let citation: String
}

// MARK: - SopQueryView

struct SopQueryView: View {
    @StateObject private var assistant = SopAssistant(knowledgeBase: KnowledgeBase(sopData: []))

    var body: some View {
        VStack {
            TextField("Enter query", text: $assistant.query)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button(action: assistant.performQuery) {
                Text("Query")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(assistant.isLoading)

            if assistant.isLoading {
                ProgressView()
                    .padding()
            }

            if let error = assistant.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .padding()
            }

            List(assistant.results) { result in
                VStack(alignment: .leading) {
                    Text(result.section)
                        .font(.headline)
                    Text(result.citation)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .navigationTitle("SOP Query Assistant")
    }
}

// MARK: - Preview

struct SopQueryView_Previews: PreviewProvider {
    static var previews: some View {
        SopQueryView()
    }
}