// FineTuningDemo.swift
// Train LoRA adapters on YOUR data, on YOUR device

import SwiftUI

public struct FineTuningTab: View {
    @StateObject private var vm = FineTuningViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero
                    heroSection
                    
                    // Config
                    configSection
                    
                    // Training Data
                    dataSection
                    
                    // Training Progress
                    if vm.isTraining {
                        progressSection
                    }
                    
                    // Saved Adapters
                    adaptersSection
                    
                    // Start Training Button
                    trainingButton
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("🧠 Fine-Tune")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 50))
                    .foregroundColor(.white)
            }
            
            Text("On-Device Fine-Tuning")
                .font(.title.bold())
                .foregroundColor(.white)
            
            Text("Train LoRA adapters on your data.\nEverything stays on your device.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Config Section
    
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader2(title: "Configuration", icon: "slider.horizontal.3")
            
            // Preset selector
            HStack {
                Text("Preset")
                    .foregroundColor(.white)
                Spacer()
                Picker("", selection: $vm.selectedPreset) {
                    Text("Small (Quick)").tag(FineTuningPreset.small)
                    Text("Standard").tag(FineTuningPreset.standard)
                    Text("Large (Quality)").tag(FineTuningPreset.large)
                }
                .pickerStyle(.menu)
                .tint(.cyan)
            }
            
            // Config details
            HStack(spacing: 16) {
                ConfigBadge(label: "Rank", value: "\(vm.configRank)")
                ConfigBadge(label: "Steps", value: "\(vm.configMaxSteps)")
                ConfigBadge(label: "LR", value: vm.configLR)
                ConfigBadge(label: "Batch", value: "\(vm.configBatch)")
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Data Section
    
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader2(title: "Training Data", icon: "doc.text")
            
            // Add examples
            VStack(spacing: 12) {
                ForEach(vm.examples.indices, id: \.self) { index in
                    ExampleRow(example: vm.examples[index]) {
                        vm.examples.remove(at: index)
                    }
                }
                
                if vm.examples.isEmpty {
                    Text("Add training examples below")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            
            // Add new example
            VStack(spacing: 8) {
                TextField("Prompt", text: $vm.newPrompt)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Expected completion", text: $vm.newCompletion)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    vm.addExample()
                } label: {
                    Label("Add Example", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
                .disabled(vm.newPrompt.isEmpty || vm.newCompletion.isEmpty)
            }
            
            // Import options
            HStack {
                Button {
                    vm.importFromJSONL()
                } label: {
                    Label("Import JSONL", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .tint(.gray)
                
                Button {
                    vm.importFromConversations()
                } label: {
                    Label("From History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader2(title: "Training Progress", icon: "chart.line.uptrend.xyaxis")
            
            // Progress bar
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: vm.progress)
                    .tint(.orange)
                
                HStack {
                    Text("Step \(vm.currentStep) / \(vm.configMaxSteps)")
                    Spacer()
                    Text(String(format: "%.1f%%", vm.progress * 100))
                }
                .font(.caption)
                .foregroundColor(.gray)
            }
            
            // Stats
            HStack(spacing: 16) {
                StatBox(label: "Loss", value: String(format: "%.4f", vm.currentLoss))
                StatBox(label: "Time", value: vm.elapsedTime)
                StatBox(label: "ETA", value: vm.estimatedTime)
            }
            
            // Cancel button
            Button("Cancel Training") {
                vm.cancelTraining()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Adapters Section
    
    private var adaptersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader2(title: "Saved Adapters", icon: "archivebox")
            
            if vm.savedAdapters.isEmpty {
                Text("No adapters trained yet")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(vm.savedAdapters) { adapter in
                    AdapterRow(adapter: adapter) {
                        vm.loadAdapter(adapter)
                    } onDelete: {
                        vm.deleteAdapter(adapter)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Training Button
    
    private var trainingButton: some View {
        Button {
            vm.startTraining()
        } label: {
            HStack {
                Image(systemName: "flame.fill")
                Text("Start Training")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(vm.examples.count < 3 || vm.isTraining)
        .padding(.vertical)
    }
}

// MARK: - View Model

enum FineTuningPreset {
    case small, standard, large
}

@MainActor
class FineTuningViewModel: ObservableObject {
    @Published var selectedPreset: FineTuningPreset = .standard {
        didSet { updateConfig() }
    }
    @Published var config = OnDeviceFineTuning.LoRAConfig()
    @Published var examples: [TrainingExample] = []
    @Published var newPrompt = ""
    @Published var newCompletion = ""
    
    @Published var isTraining = false
    @Published var progress: Double = 0
    @Published var currentStep = 0
    @Published var currentLoss: Float = 0
    @Published var elapsedTime = "0:00"
    @Published var estimatedTime = "--:--"
    
    @Published var savedAdapters: [SavedAdapter] = []
    
    // Computed properties for UI binding
    var configRank: Int { config.rank }
    var configMaxSteps: Int { config.maxSteps }
    var configLR: String { String(format: "%.0e", config.learningRate) }
    var configBatch: Int { config.batchSize }
    
    struct TrainingExample: Identifiable {
        let id = UUID()
        let prompt: String
        let completion: String
    }
    
    struct SavedAdapter: Identifiable {
        let id = UUID()
        let name: String
        let date: Date
        let examples: Int
        let steps: Int
    }
    
    private func updateConfig() {
        switch selectedPreset {
        case .small:
            config = OnDeviceFineTuning.LoRAConfig.small
        case .standard:
            config = OnDeviceFineTuning.LoRAConfig.standard
        case .large:
            config = OnDeviceFineTuning.LoRAConfig.large
        }
    }
    
    func addExample() {
        let example = TrainingExample(prompt: newPrompt, completion: newCompletion)
        examples.append(example)
        newPrompt = ""
        newCompletion = ""
    }
    
    func importFromJSONL() {
        // Would open file picker
    }
    
    func importFromConversations() {
        // Would pull from conversation history
    }
    
    func startTraining() {
        isTraining = true
        progress = 0
        currentStep = 0
        
        // Simulate training progress
        Task {
            for step in 1...config.maxSteps {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s per step
                currentStep = step
                progress = Double(step) / Double(config.maxSteps)
                currentLoss = 2.5 - (Float(step) / Float(config.maxSteps) * 2.0) + Float.random(in: -0.1...0.1)
                elapsedTime = formatTime(step)
                estimatedTime = formatTime(config.maxSteps - step)
            }
            
            // Training complete
            let adapter = SavedAdapter(
                name: "adapter_\(Date().formatted(.dateTime.month().day().hour().minute()))",
                date: Date(),
                examples: examples.count,
                steps: config.maxSteps
            )
            savedAdapters.insert(adapter, at: 0)
            isTraining = false
        }
    }
    
    func cancelTraining() {
        isTraining = false
    }
    
    func loadAdapter(_ adapter: SavedAdapter) {
        // Would load the LoRA weights
    }
    
    func deleteAdapter(_ adapter: SavedAdapter) {
        savedAdapters.removeAll { $0.id == adapter.id }
    }
    
    private func formatTime(_ steps: Int) -> String {
        let seconds = steps / 10
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Components

struct SectionHeader2: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.orange)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
        }
    }
}

struct ConfigBadge: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.orange)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ExampleRow: View {
    let example: FineTuningViewModel.TrainingExample
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(example.prompt)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text(example.completion)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

struct StatBox: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

struct AdapterRow: View {
    let adapter: FineTuningViewModel.SavedAdapter
    let onLoad: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(adapter.name)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text("\(adapter.examples) examples • \(adapter.steps) steps • \(adapter.date.formatted(.dateTime.month().day()))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button("Load", action: onLoad)
                .buttonStyle(.bordered)
                .tint(.cyan)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    FineTuningTab()
}
