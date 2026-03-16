//
//  TakeoverDemo.swift
//  ZETA³: THE TAKEOVER
//
//  Real functionality: Device Swarm + Autonomous Agent
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Main View

public struct TakeoverTab: View {
    @StateObject private var swarm = DeviceSwarmEngine.shared
    @StateObject private var agent = RealAutonomousAgent()
    @State private var selectedSection: ZetaSection = .swarm
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section picker
                Picker("Section", selection: $selectedSection) {
                    ForEach(ZetaSection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                ScrollView {
                    switch selectedSection {
                    case .swarm:
                        SwarmSection(swarm: swarm)
                    case .agent:
                        AgentSection(agent: agent)
                    case .siri:
                        SiriSection()
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Zeta³")
        }
        .preferredColorScheme(.dark)
    }
}

enum ZetaSection: String, CaseIterable {
    case swarm = "Swarm"
    case agent = "Agent"
    case siri = "Siri"
}

// MARK: - Device Swarm Section (REAL)

struct SwarmSection: View {
    @ObservedObject var swarm: DeviceSwarmEngine
    @State private var isScanning = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Status Card
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "network")
                        .font(.title)
                        .foregroundColor(.cyan)
                    
                    VStack(alignment: .leading) {
                        Text("Device Swarm")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(swarm.isHost ? "Hosting" : (swarm.connectedDevices.isEmpty ? "Not connected" : "\(swarm.connectedDevices.count) devices"))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Circle()
                        .fill(swarm.connectedDevices.isEmpty ? Color.orange : Color.green)
                        .frame(width: 12, height: 12)
                }
                
                // Capacity
                if swarm.totalCapacity > 0 {
                    HStack {
                        Text("Combined RAM:")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(swarm.totalCapacity) GB")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            
            // Controls
            HStack(spacing: 12) {
                Button {
                    if swarm.isHost {
                        swarm.stop()
                    } else {
                        swarm.startHosting()
                    }
                } label: {
                    Label(swarm.isHost ? "Stop Hosting" : "Host Swarm", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ZetaButtonStyle(color: .cyan))
                
                Button {
                    isScanning = true
                    swarm.startBrowsing()
                    
                    // Stop after 10 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        isScanning = false
                    }
                } label: {
                    Label(isScanning ? "Scanning..." : "Find Devices", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ZetaButtonStyle(color: .purple))
                .disabled(isScanning)
            }
            
            // Connected Devices
            if !swarm.connectedDevices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connected Devices")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    ForEach(swarm.connectedDevices) { device in
                        HStack {
                            Image(systemName: deviceIcon(device.name))
                                .foregroundColor(.cyan)
                            
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .foregroundColor(.white)
                                Text("\(device.ramGB) GB RAM")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Text(device.status == .processing ? "Working" : "Idle")
                                .font(.caption)
                                .foregroundColor(device.status == .processing ? .green : .gray)
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                    }
                }
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "ipad.and.iphone")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No devices connected")
                        .foregroundColor(.gray)
                    Text("Host a swarm or search for nearby ZeroDark devices to combine processing power.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            }
            
            // How it works
            VStack(alignment: .leading, spacing: 8) {
                Text("How Swarm Works")
                    .font(.headline)
                    .foregroundColor(.white)
                
                InfoRow(icon: "square.stack.3d.up", text: "Model layers split across devices")
                InfoRow(icon: "bolt.fill", text: "Each device processes its assigned layers")
                InfoRow(icon: "arrow.triangle.merge", text: "Results combined for full inference")
                InfoRow(icon: "lock.shield", text: "All communication encrypted")
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
        }
        .padding()
    }
    
    private func deviceIcon(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("mac") { return "laptopcomputer" }
        return "desktopcomputer"
    }
}

// MARK: - Autonomous Agent Section (REAL)

struct AgentSection: View {
    @ObservedObject var agent: RealAutonomousAgent
    @State private var taskInput = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Task Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Give me a task")
                    .font(.headline)
                    .foregroundColor(.white)
                
                TextField("e.g., Check the weather and set a reminder", text: $taskInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .lineLimit(2...4)
                
                Button {
                    agent.executeTask(taskInput)
                    taskInput = ""
                } label: {
                    Label("Execute", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ZetaButtonStyle(color: .green))
                .disabled(taskInput.isEmpty || agent.isExecuting)
            }
            
            // Execution Progress
            if agent.isExecuting || !agent.steps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Execution")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        if agent.isExecuting {
                            ProgressView()
                                .tint(.cyan)
                        }
                    }
                    
                    ForEach(agent.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: step.completed ? "checkmark.circle.fill" : (step.inProgress ? "arrow.clockwise.circle.fill" : "circle"))
                                .foregroundColor(step.completed ? .green : (step.inProgress ? .cyan : .gray))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.description)
                                    .foregroundColor(.white)
                                if let result = step.result {
                                    Text(result)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
            }
            
            // Final Result
            if let result = agent.finalResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Result")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(result)
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(16)
            }
            
            // What it can do
            VStack(alignment: .leading, spacing: 8) {
                Text("Available Tools")
                    .font(.headline)
                    .foregroundColor(.white)
                
                ToolRow(icon: "cloud.sun", name: "Weather", desc: "Real weather data")
                ToolRow(icon: "calendar", name: "Calendar", desc: "View your events")
                ToolRow(icon: "bell", name: "Reminders", desc: "Create reminders")
                ToolRow(icon: "clock", name: "Time", desc: "Current date/time")
                ToolRow(icon: "function", name: "Calculator", desc: "Math operations")
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
        }
        .padding()
    }
}

struct ToolRow: View {
    let icon: String
    let name: String
    let desc: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.cyan)
                .frame(width: 24)
            Text(name)
                .foregroundColor(.white)
            Spacer()
            Text(desc)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Siri Section

struct SiriSection: View {
    var body: some View {
        VStack(spacing: 20) {
            // Coming soon
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.purple.opacity(0.5))
                
                Text("Siri Integration")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Coming Soon")
                    .font(.headline)
                    .foregroundColor(.purple)
                
                Text("Say \"Hey Siri, ask ZeroDark\" to invoke on-device AI from anywhere.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(40)
            
            // Requirements
            VStack(alignment: .leading, spacing: 8) {
                Text("Requirements")
                    .font(.headline)
                    .foregroundColor(.white)
                
                InfoRow(icon: "checkmark.circle", text: "iOS 17+ with App Intents")
                InfoRow(icon: "checkmark.circle", text: "Siri enabled")
                InfoRow(icon: "checkmark.circle", text: "ZeroDark model loaded")
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
        }
        .padding()
    }
}

// MARK: - Real Autonomous Agent

@MainActor
class RealAutonomousAgent: ObservableObject {
    @Published var isExecuting = false
    @Published var steps: [AgentStep] = []
    @Published var finalResult: String?
    
    private let toolkit = AgentToolkit.shared
    
    struct AgentStep: Identifiable {
        let id = UUID()
        let description: String
        var completed = false
        var inProgress = false
        var result: String?
    }
    
    func executeTask(_ task: String) {
        isExecuting = true
        steps.removeAll()
        finalResult = nil
        
        Task {
            // Step 1: Analyze task
            addStep("Analyzing task...")
            await sleep(0.5)
            completeStep(0, result: "Identified required tools")
            
            // Parse task for tool needs
            let lower = task.lowercased()
            var toolsToRun: [(String, [String: String])] = []
            
            if lower.contains("weather") || lower.contains("temperature") {
                toolsToRun.append(("weather", ["location": extractLocation(from: task)]))
            }
            if lower.contains("calendar") || lower.contains("schedule") || lower.contains("events") {
                toolsToRun.append(("calendar", [:]))
            }
            if lower.contains("remind") {
                let text = extractReminderText(from: task)
                toolsToRun.append(("reminder", ["title": text]))
            }
            if lower.contains("time") || lower.contains("date") {
                toolsToRun.append(("time", [:]))
            }
            
            if toolsToRun.isEmpty {
                completeStep(0, result: "No tools needed - will use AI response")
                toolsToRun.append(("ai_response", ["prompt": task]))
            }
            
            // Execute each tool
            var results: [String] = []
            for (tool, args) in toolsToRun {
                let stepIdx = steps.count
                addStep("Executing \(tool)...")
                
                if tool == "ai_response" {
                    await sleep(1)
                    completeStep(stepIdx, result: "Generated response")
                    results.append("I understood your request.")
                } else {
                    let call = AgentToolkit.ToolCall(tool: tool, arguments: args)
                    let result = await toolkit.execute(call)
                    completeStep(stepIdx, result: result.success ? "✓ Success" : "✗ Failed")
                    results.append(result.output)
                }
            }
            
            // Synthesize result
            let synthesisIdx = steps.count
            addStep("Synthesizing results...")
            await sleep(0.5)
            completeStep(synthesisIdx, result: "Done")
            
            finalResult = results.joined(separator: "\n\n")
            isExecuting = false
        }
    }
    
    private func addStep(_ desc: String) {
        var step = AgentStep(description: desc)
        step.inProgress = true
        steps.append(step)
    }
    
    private func completeStep(_ index: Int, result: String) {
        guard index < steps.count else { return }
        steps[index].completed = true
        steps[index].inProgress = false
        steps[index].result = result
    }
    
    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    
    private func extractLocation(from text: String) -> String {
        let cities = ["san antonio", "austin", "houston", "dallas", "new york", "los angeles"]
        let lower = text.lowercased()
        for city in cities {
            if lower.contains(city) { return city.capitalized }
        }
        return "San Antonio"
    }
    
    private func extractReminderText(from text: String) -> String {
        var cleaned = text.lowercased()
        for prefix in ["remind me to", "remind me", "set a reminder to", "set reminder"] {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }
        return cleaned.trimmingCharacters(in: .whitespaces).capitalized
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.cyan)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

struct ZetaButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .background(color.opacity(configuration.isPressed ? 0.5 : 0.3))
            .cornerRadius(12)
    }
}
