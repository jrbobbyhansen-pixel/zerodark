import SwiftUI
import Foundation

struct QuickReferenceCard: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let contact: String
}

class QuickReferenceViewModel: ObservableObject {
    @Published var cards: [QuickReferenceCard] = [
        QuickReferenceCard(title: "Emergency Procedures", content: "Step 1: Activate emergency protocol. Step 2: Notify command center. Step 3: Evacuate the area.", contact: "Emergency Contact: 911"),
        QuickReferenceCard(title: "Field AI Operations", content: "Step 1: Deploy ARKit for navigation. Step 2: Use MLXEdgeLLM for analysis. Step 3: Monitor AI feedback.", contact: "AI Support: ai@zerodark.com"),
        QuickReferenceCard(title: "Communication Protocols", content: "Step 1: Use secure channels. Step 2: Encrypt all data. Step 3: Regularly update protocols.", contact: "Comms Support: comms@zerodark.com")
    ]
}

struct QuickReferenceView: View {
    @StateObject private var viewModel = QuickReferenceViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.cards) { card in
                NavigationLink(destination: CardDetailView(card: card)) {
                    VStack(alignment: .leading) {
                        Text(card.title)
                            .font(.headline)
                        Text(card.content)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Quick Reference Cards")
        }
    }
}

struct CardDetailView: View {
    let card: QuickReferenceCard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.title)
                .font(.largeTitle)
                .padding(.bottom)
            
            Text(card.content)
                .font(.body)
            
            Text("Contact: \(card.contact)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle(card.title)
    }
}

struct QuickReference_Previews: PreviewProvider {
    static var previews: some View {
        QuickReferenceView()
    }
}