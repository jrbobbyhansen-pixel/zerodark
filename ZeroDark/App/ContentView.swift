import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TranscriptionView()
                .tabItem {
                    Label("Transcribe", systemImage: "waveform.and.mic")
                }

            DTMFLoggerView()
                .tabItem {
                    Label("DTMF", systemImage: "phone.and.waveform")
                }

            EnvironmentMonitorView()
                .tabItem {
                    Label("Environment", systemImage: "barometer")
                }

            LLMAssistantView()
                .tabItem {
                    Label("Assistant", systemImage: "brain")
                }
        }
    }
}
