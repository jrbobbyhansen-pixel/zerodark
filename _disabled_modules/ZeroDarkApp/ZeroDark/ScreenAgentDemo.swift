// ScreenAgentDemo.swift
// AI that SEES your screen and ACTS

import SwiftUI
import MLXEdgeLLM

#if os(macOS)

public struct ScreenAgentTab: View {
    @StateObject private var agent = ScreenAgentViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    
                    Text("Screen Agent")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    
                    Text("AI that sees your screen and acts")
                        .foregroundColor(.gray)
                }
                .padding(.top, 40)
                
                // Status
                HStack(spacing: 20) {
                    StatusPill(
                        icon: "checkmark.circle",
                        text: agent.permissionStatus,
                        color: agent.hasPermission ? .green : .orange
                    )
                    
                    StatusPill(
                        icon: "display",
                        text: "\(agent.captureCount) captures",
                        color: .cyan
                    )
                }
                
                // Last capture preview
                if let capture = agent.lastCapture {
                    VStack(spacing: 8) {
                        Image(nsImage: NSImage(cgImage: capture.image, size: NSSize(width: 400, height: 250)))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 250)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                            )
                        
                        Text("Captured \(capture.timestamp.formatted())")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                // Analysis results
                if let analysis = agent.lastAnalysis {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Analysis")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(analysis.description)
                            .foregroundColor(.gray)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                        
                        if !analysis.text.isEmpty {
                            Text("Detected Text:")
                                .font(.subheadline)
                                .foregroundColor(.cyan)
                            
                            ForEach(analysis.text.prefix(5), id: \.text) { block in
                                Text("• \(block.text)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                // Actions
                HStack(spacing: 16) {
                    Button {
                        agent.captureScreen()
                    } label: {
                        Label("Capture", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    
                    Button {
                        agent.analyzeAndAct()
                    } label: {
                        Label("Analyze & Act", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding()
            .background(Color.black)
            .navigationTitle("👁️ Screen Agent")
        }
        .preferredColorScheme(.dark)
    }
}

@MainActor
class ScreenAgentViewModel: ObservableObject {
    @Published var hasPermission = false
    @Published var permissionStatus = "Checking..."
    @Published var captureCount = 0
    @Published var lastCapture: ScreenUnderstanding.ScreenCapture?
    @Published var lastAnalysis: ScreenUnderstanding.ScreenAnalysis?
    
    private let screen = ScreenUnderstanding.shared
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        hasPermission = screen.isAvailable
        permissionStatus = hasPermission ? "Authorized" : "Need Permission"
    }
    
    func captureScreen() {
        guard #available(macOS 12.3, *) else { return }
        
        Task {
            do {
                let capture = try await screen.captureScreen()
                lastCapture = capture
                captureCount += 1
            } catch {
                permissionStatus = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    func analyzeAndAct() {
        guard let capture = lastCapture else {
            captureScreen()
            return
        }
        
        Task {
            do {
                let analysis = try await screen.analyzeScreen(capture)
                lastAnalysis = analysis
                
                // Here we would send to AI for action
                // let ai = ZeroDarkAI.shared
                // let action = try await ai.process(prompt: "Based on this screen: \(analysis.description), what action should I take?")
            } catch {
                permissionStatus = "Analysis failed"
            }
        }
    }
}

struct StatusPill: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .foregroundColor(.white)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.2))
        .cornerRadius(20)
    }
}

#else

// iOS placeholder - Screen capture not available
public struct ScreenAgentTab: View {
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("Screen Agent")
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                Text("Available on macOS only")
                    .foregroundColor(.gray)
                
                Text("Screen capture requires macOS 12.3+ and ScreenCaptureKit")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("👁️ Screen Agent")
        }
        .preferredColorScheme(.dark)
    }
}

#endif

#Preview {
    ScreenAgentTab()
}
