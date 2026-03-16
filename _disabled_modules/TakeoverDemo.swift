// TakeoverDemo.swift
// ZETA³: THE TAKEOVER
// "Hey Siri" hijack + Autonomous agents + Device swarm

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct TakeoverTab: View {
    @StateObject private var vm = TakeoverViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero
                    heroSection
                    
                    // Siri Integration
                    siriSection
                    
                    // Autonomous Agent
                    agentSection
                    
                    // Device Swarm
                    swarmSection
                    
                    // Quick Actions
                    quickActionsSection
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [Color.black, Color.purple.opacity(0.3), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationTitle("⚡ Takeover")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Hero
    
    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.purple, .cyan, .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 150, height: 150)
                    .blur(radius: 30)
                
                Text("⚡")
                    .font(.system(size: 70))
            }
            
            Text("ZETA³")
                .font(.system(size: 48, weight: .black, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text("THE TAKEOVER")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.gray)
                .tracking(8)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Siri Integration
    
    private var siriSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title)
                    .foregroundColor(.purple)
                Text("Siri Integration")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                
                StatusChip(
                    text: vm.siriEnabled ? "Active" : "Setup Required",
                    color: vm.siriEnabled ? .green : .orange
                )
            }
            
            Text("Say \"Hey Siri, ask Zero Dark...\" to use your on-device AI")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Example phrases
            VStack(alignment: .leading, spacing: 8) {
                PhraseRow(phrase: "Hey Siri, ask Zero Dark what's on my calendar")
                PhraseRow(phrase: "Hey Siri, have Zero Dark plan my day")
                PhraseRow(phrase: "Hey Siri, ask Zero Dark to remind me about the meeting")
            }
            
            Button {
                vm.setupSiri()
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Configure Shortcuts")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Autonomous Agent
    
    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title)
                    .foregroundColor(.cyan)
                Text("Autonomous Agent")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            Text("AI that PLANS and EXECUTES multi-step tasks without human intervention")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Task input
            VStack(spacing: 12) {
                TextField("Enter a complex task...", text: $vm.taskInput)
                    .textFieldStyle(.roundedBorder)
                
                if vm.isExecuting {
                    // Progress view
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: vm.executionProgress)
                            .tint(.cyan)
                        
                        Text("Step \(vm.currentStep): \(vm.currentAction)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
                
                if !vm.executionResult.isEmpty {
                    ScrollView {
                        Text(vm.executionResult)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    .frame(maxHeight: 150)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
                
                HStack {
                    Button {
                        vm.executeTask()
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Execute")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(vm.taskInput.isEmpty || vm.isExecuting)
                    
                    Button("Plan My Day") {
                        vm.planDay()
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .disabled(vm.isExecuting)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Device Swarm
    
    private var swarmSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "network")
                    .font(.title)
                    .foregroundColor(.green)
                Text("Device Swarm")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                
                StatusChip(
                    text: "\(vm.swarmDevices.count) devices",
                    color: vm.swarmDevices.count > 1 ? .green : .gray
                )
            }
            
            Text("Connect multiple Apple devices to run larger models together")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Device list
            if !vm.swarmDevices.isEmpty {
                VStack(spacing: 8) {
                    ForEach(vm.swarmDevices, id: \.id) { device in
                        HStack {
                            Image(systemName: device.type == .mac ? "desktopcomputer" : device.type == .iPad ? "ipad" : "iphone")
                                .foregroundColor(.cyan)
                            Text(device.name)
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(device.memoryGB) GB")
                                .foregroundColor(.gray)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
            
            // Capacity
            HStack {
                Text("Total Capacity:")
                    .foregroundColor(.gray)
                Spacer()
                Text("\(vm.totalSwarmMemory) GB")
                    .foregroundColor(.cyan)
                    .fontWeight(.bold)
                Text("→ Can run \(vm.maxModelName)")
                    .foregroundColor(.green)
            }
            .font(.caption)
            
            Button {
                vm.scanForDevices()
            } label: {
                HStack {
                    Image(systemName: vm.isScanning ? "antenna.radiowaves.left.and.right" : "magnifyingglass")
                    Text(vm.isScanning ? "Scanning..." : "Find Nearby Devices")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .disabled(vm.isScanning)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try These")
                .font(.headline)
                .foregroundColor(.white)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickAction(title: "Plan My Week", icon: "calendar.badge.clock", color: .purple) {
                    vm.taskInput = "Plan my week based on my calendar and priorities"
                    vm.executeTask()
                }
                
                QuickAction(title: "Morning Routine", icon: "sun.horizon", color: .orange) {
                    vm.taskInput = "Run my morning routine: check weather, read calendar, summarize news"
                    vm.executeTask()
                }
                
                QuickAction(title: "Health Report", icon: "heart.fill", color: .red) {
                    vm.taskInput = "Analyze my health data and suggest improvements"
                    vm.executeTask()
                }
                
                QuickAction(title: "Clear Inbox", icon: "tray.full", color: .blue) {
                    vm.taskInput = "Process my inbox: categorize, flag important, draft responses"
                    vm.executeTask()
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - View Model

@MainActor
class TakeoverViewModel: ObservableObject {
    @Published var siriEnabled = false
    @Published var taskInput = ""
    @Published var isExecuting = false
    @Published var executionProgress: Double = 0
    @Published var currentStep = 0
    @Published var currentAction = ""
    @Published var executionResult = ""
    
    @Published var swarmDevices: [SwarmDevice] = []
    @Published var totalSwarmMemory = 0
    @Published var isScanning = false
    
    var maxModelName: String {
        let maxGB = Double(totalSwarmMemory) * 0.6
        if maxGB >= 40 { return "70B" }
        if maxGB >= 20 { return "40B" }
        if maxGB >= 8 { return "14B" }
        return "8B"
    }
    
    init() {
        // Add local device
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        #if os(iOS)
        let type: SwarmDevice.DeviceType = .iPhone
        let name = UIDevice.current.name
        #else
        let type: SwarmDevice.DeviceType = .mac
        let name = "This Mac"
        #endif
        
        swarmDevices = [
            SwarmDevice(
                id: "local",
                name: name,
                type: type,
                memoryGB: memoryGB,
                isLocal: true,
                connectionQuality: .local
            )
        ]
        totalSwarmMemory = memoryGB
    }
    
    func setupSiri() {
        // Would open Settings to configure Shortcuts
        siriEnabled = true
    }
    
    func executeTask() {
        guard !taskInput.isEmpty else { return }
        
        isExecuting = true
        executionProgress = 0
        currentStep = 0
        executionResult = ""
        
        Task {
            let agent = await AutonomousAgent.shared
            
            // Simulate step-by-step execution
            let steps = ["Analyzing request", "Creating plan", "Executing step 1", "Executing step 2", "Generating summary"]
            
            for (index, step) in steps.enumerated() {
                currentStep = index + 1
                currentAction = step
                executionProgress = Double(index + 1) / Double(steps.count)
                
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            // Get actual result
            do {
                let result = try await agent.startTask(description: taskInput)
                executionResult = """
                ✓ Task Complete
                
                \(result)
                """
            } catch {
                executionResult = "Error: \(error.localizedDescription)"
            }
            
            isExecuting = false
        }
    }
    
    func planDay() {
        taskInput = "Plan my day"
        executeTask()
    }
    
    func scanForDevices() {
        isScanning = true
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            // Simulate finding devices
            let newDevice = SwarmDevice(
                id: UUID().uuidString,
                name: "iPad Pro",
                type: .iPad,
                memoryGB: 16,
                isLocal: false,
                connectionQuality: .excellent
            )
            
            swarmDevices.append(newDevice)
            totalSwarmMemory += newDevice.memoryGB
            
            isScanning = false
        }
    }
}

// MARK: - Components

struct StatusChip: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .cornerRadius(8)
    }
}

struct PhraseRow: View {
    let phrase: String
    
    var body: some View {
        HStack {
            Image(systemName: "quote.opening")
                .foregroundColor(.purple.opacity(0.5))
                .font(.caption)
            Text(phrase)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .italic()
        }
    }
}

struct QuickAction: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
}

#Preview {
    TakeoverTab()
}
