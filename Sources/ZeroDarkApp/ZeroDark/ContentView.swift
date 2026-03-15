import SwiftUI
import PhotosUI
import MLXEdgeLLM
import MLXEdgeLLMUI
import MLXEdgeLLMVoice
import MLXEdgeLLMDocs

// MARK: - ContentView

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // ☢️ NUCLEAR DEMO - The main event
            NuclearDemoTab()
                .tabItem {
                    Label("Nuclear", systemImage: "atom")
                }
                .tag(0)
            
            // 💬 Text Chat
            TextChatTab()
                .tabItem {
                    Label("Chat", systemImage: "text.bubble")
                }
                .tag(1)
            
            // 🎤 Voice
            VoiceTab()
                .tabItem {
                    Label("Voice", systemImage: "mic.fill")
                }
                .tag(2)
            
            // 👁️ Vision
            VisionTab()
                .tabItem {
                    Label("Vision", systemImage: "eye")
                }
                .tag(3)
            
            // 👁️ Screen Agent (macOS)
            ScreenAgentTab()
                .tabItem {
                    Label("Screen", systemImage: "display")
                }
                .tag(4)
            
            // 🧠 Fine-Tuning
            FineTuningTab()
                .tabItem {
                    Label("Train", systemImage: "brain.head.profile")
                }
                .tag(5)
            
            // 📄 Docs RAG
            DocsTab()
                .tabItem {
                    Label("Docs", systemImage: "doc.text.magnifyingglass")
                }
                .tag(6)
            
            // 📷 OCR
            OCRTab()
                .tabItem {
                    Label("OCR", systemImage: "doc.viewfinder")
                }
                .tag(7)
            
            // 📦 Models
            ModelsTab()
                .tabItem {
                    Label("Models", systemImage: "square.stack.3d.up")
                }
                .tag(8)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Models Tab

public struct ModelsTab: View {
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                ModelSection(title: "Text", icon: "text.bubble", color: .green, models: Model.textModels)
                ModelSection(title: "Vision", icon: "eye", color: .blue, models: Model.visionModels)
                ModelSection(title: "Specialized OCR", icon: "doc.viewfinder", color: .orange, models: Model.specializedModels)
            }
            .navigationTitle("Models")
            .preferredColorScheme(.dark)
        }
    }
}

#Preview { ContentView() }
