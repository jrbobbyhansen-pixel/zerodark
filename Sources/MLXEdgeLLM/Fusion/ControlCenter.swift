// ControlCenter.swift — Control State and Focus Mode Integration

import SwiftUI
import AppIntents

// MARK: - Control State Manager

@MainActor
final class ZeroDarkControlState: ObservableObject {
    static let shared = ZeroDarkControlState()
    
    @Published var isEngineActive = false
    @Published var currentModel: String = "None"
    @Published var memoryUsage: Int = 0
    @Published var isProcessing = false
    @Published var lastQuery: String?
    
    private init() {
        Task {
            await refreshState()
        }
    }
    
    func setEngineActive(_ active: Bool) async {
        if active {
            isEngineActive = true
            currentModel = "Qwen3 8B"
        } else {
            isEngineActive = false
            currentModel = "None"
        }
    }
    
    func refreshState() async {
        // Tactical system (LLM removed)
        isEngineActive = true
        currentModel = "ZeroDark Tactical"
    }
    
    func startProcessing(query: String) {
        isProcessing = true
        lastQuery = query
    }
    
    func endProcessing() {
        isProcessing = false
    }
}

// MARK: - Focus Mode Integration

enum ZeroDarkFocusMode: String, AppEnum {
    case full = "full"
    case minimal = "minimal"
    case silent = "silent"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Focus Mode"
    static var caseDisplayRepresentations: [ZeroDarkFocusMode: DisplayRepresentation] = [
        .full: "Full Power",
        .minimal: "Minimal",
        .silent: "Silent"
    ]
}

@MainActor
final class ZeroDarkFocusManager {
    static let shared = ZeroDarkFocusManager()
    
    var currentMode: ZeroDarkFocusMode = .full
    var reduceNotifications = false
    
    private init() {}
    
    func applyFocusSettings(mode: ZeroDarkFocusMode, reduceNotifications: Bool) async {
        self.currentMode = mode
        self.reduceNotifications = reduceNotifications
        
        switch mode {
        case .full:
            // Enable all features - deep reasoning, background processing
            await ZeroDarkControlState.shared.setEngineActive(true)
            
        case .minimal:
            // Reduce background processing, use smaller model
            await ZeroDarkControlState.shared.setEngineActive(true)
            
        case .silent:
            // Disable notifications, minimal processing
            await ZeroDarkControlState.shared.setEngineActive(false)
        }
    }
}

// MARK: - Status View

struct ZeroDarkStatusView: View {
    @ObservedObject var state = ZeroDarkControlState.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Engine Status
            HStack {
                Circle()
                    .fill(state.isEngineActive ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(state.isEngineActive ? "Active" : "Inactive")
                    .font(.headline)
                
                Spacer()
                
                Text(state.currentModel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            
            // Processing Indicator
            if state.isProcessing {
                HStack {
                    ProgressView()
                        .tint(ZDDesign.forestGreen)
                    
                    if let query = state.lastQuery {
                        Text(query)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            
            // Quick Actions
            HStack(spacing: 12) {
                StatusActionButton(
                    title: "Toggle Engine",
                    icon: state.isEngineActive ? "power.circle.fill" : "power.circle",
                    color: state.isEngineActive ? .green : .gray
                ) {
                    Task {
                        await state.setEngineActive(!state.isEngineActive)
                    }
                }
                
                StatusActionButton(
                    title: "Refresh",
                    icon: "arrow.clockwise",
                    color: ZDDesign.forestGreen
                ) {
                    Task {
                        await state.refreshState()
                    }
                }
            }
        }
        .padding()
    }
}

struct StatusActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}
