import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - KnowledgeBase

class KnowledgeBase: ObservableObject {
    @Published var firstAidInfo: String = ""
    @Published var navigationInfo: String = ""
    @Published var signalingInfo: String = ""
    @Published var shelterInfo: String = ""
    @Published var waterProcurementInfo: String = ""
    
    init() {
        loadKnowledgeBase()
    }
    
    private func loadKnowledgeBase() {
        // Simulate loading knowledge base from local storage
        firstAidInfo = "First Aid: Clean wound, apply bandage, use antiseptic."
        navigationInfo = "Navigation: Use map, compass, or GPS device."
        signalingInfo = "Signaling: Use whistle, mirror, or signal flare."
        shelterInfo = "Shelter: Find cover, build a lean-to, use natural shelters."
        waterProcurementInfo = "Water Procurement: Find a clean source, boil or filter water."
    }
}

// MARK: - KnowledgeBaseView

struct KnowledgeBaseView: View {
    @StateObject private var knowledgeBase = KnowledgeBase()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("First Aid")
                .font(.headline)
            Text(knowledgeBase.firstAidInfo)
                .font(.body)
            
            Text("Navigation")
                .font(.headline)
            Text(knowledgeBase.navigationInfo)
                .font(.body)
            
            Text("Signaling")
                .font(.headline)
            Text(knowledgeBase.signalingInfo)
                .font(.body)
            
            Text("Shelter")
                .font(.headline)
            Text(knowledgeBase.shelterInfo)
                .font(.body)
            
            Text("Water Procurement")
                .font(.headline)
            Text(knowledgeBase.waterProcurementInfo)
                .font(.body)
        }
        .padding()
        .navigationTitle("Tactical Knowledge Base")
    }
}

// MARK: - Preview

struct KnowledgeBaseView_Previews: PreviewProvider {
    static var previews: some View {
        KnowledgeBaseView()
    }
}