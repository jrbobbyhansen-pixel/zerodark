import SwiftUI
import MLXEdgeLLM

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Cross-Platform Toolbar Helpers

extension View {
    @ViewBuilder
    func beastNavBarInline() -> some View {
        #if os(iOS) || os(visionOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    
    @ViewBuilder
    func beastToolbarDone(_ dismiss: DismissAction) -> some View {
        #if os(iOS) || os(visionOS)
        self.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        #else
        self.toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #endif
    }
    
    @ViewBuilder
    func beastToolbarCancel(_ dismiss: DismissAction) -> some View {
        #if os(iOS) || os(visionOS)
        self.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        #else
        self.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        #endif
    }
}

// MARK: - Cross-Platform Colors
extension Color {
    #if os(iOS) || os(visionOS)
    static let beastGray6 = Color(uiColor: .systemGray6)
    static let beastGray5 = Color(uiColor: .systemGray5)
    #else
    static let beastGray6 = Color(nsColor: .controlBackgroundColor)
    static let beastGray5 = Color(nsColor: .separatorColor)
    #endif
}

// MARK: - Performance Overlay

/// Real-time performance overlay showing tok/s, memory, thermal state
struct PerformanceOverlay: View {
    @ObservedObject var monitor = SystemMonitor.shared
    let stats: GenerationStats?
    let isGenerating: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Tokens per second
            if let stats, stats.tokensPerSecond > 0 {
                StatBadge(
                    icon: "bolt.fill",
                    value: String(format: "%.1f", stats.tokensPerSecond),
                    unit: "tok/s",
                    color: tokenSpeedColor(stats.tokensPerSecond)
                )
            }
            
            // Memory usage
            StatBadge(
                icon: "memorychip",
                value: "\(monitor.gpuMemoryMB)",
                unit: "MB",
                color: memoryColor
            )
            
            // Thermal state (iOS only)
            #if os(iOS)
            Text(monitor.thermalState.emoji)
                .font(.system(size: 16))
            #endif
            
            // Generation indicator
            if isGenerating {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
    
    private func tokenSpeedColor(_ speed: Double) -> Color {
        if speed > 30 { return .green }
        if speed > 15 { return .yellow }
        return .orange
    }
    
    private var memoryColor: Color {
        switch monitor.memoryPressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .orange
        case .terminal: return .red
        }
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
            
            Text(unit)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Parameter Controls Sheet

struct ParameterControlsSheet: View {
    @Binding var params: BeastModeParams
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                // Presets
                Section("Presets") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            PresetButton(name: "Precise", icon: "scope") {
                                params = .precise
                            }
                            PresetButton(name: "Balanced", icon: "slider.horizontal.3") {
                                params = .balanced
                            }
                            PresetButton(name: "Creative", icon: "paintbrush.pointed") {
                                params = .creative
                            }
                            PresetButton(name: "Coder", icon: "chevron.left.forwardslash.chevron.right") {
                                params = .coder
                            }
                            PresetButton(name: "Reasoning", icon: "brain") {
                                params = .reasoning
                            }
                            PresetButton(name: "Uncensored", icon: "lock.open") {
                                params = .uncensored
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Temperature
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", params.temperature))
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                        Slider(value: $params.temperature, in: 0...2, step: 0.05)
                            .tint(.cyan)
                        Text("Lower = focused & deterministic. Higher = creative & random.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Sampling", systemImage: "dice")
                }
                
                // Top-P
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Top-P (Nucleus)")
                            Spacer()
                            Text(String(format: "%.2f", params.topP))
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                        Slider(value: $params.topP, in: 0.1...1, step: 0.05)
                            .tint(.cyan)
                    }
                }
                
                // Top-K
                Section {
                    Stepper("Top-K: \(params.topK)", value: $params.topK, in: 1...200, step: 5)
                }
                
                // Repetition Penalty
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Repetition Penalty")
                            Spacer()
                            Text(String(format: "%.2f", params.repetitionPenalty))
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                        Slider(value: $params.repetitionPenalty, in: 1...2, step: 0.05)
                            .tint(.orange)
                    }
                } header: {
                    Label("Repetition Control", systemImage: "arrow.triangle.2.circlepath")
                }
                
                // Max Tokens
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Max Tokens")
                            Spacer()
                            Text("\(params.maxTokens)")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                        Slider(
                            value: Binding(
                                get: { Double(params.maxTokens) },
                                set: { params.maxTokens = Int($0) }
                            ),
                            in: 64...8192,
                            step: 64
                        )
                        .tint(.green)
                    }
                } header: {
                    Label("Output Length", systemImage: "text.justify.left")
                }
                
                // Reasoning (for DeepSeek R1)
                Section {
                    Toggle("Enable Thinking", isOn: $params.enableThinking)
                    
                    if params.enableThinking {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Thinking Budget")
                                Spacer()
                                Text("\(params.thinkingBudget)")
                                    .foregroundColor(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(params.thinkingBudget) },
                                    set: { params.thinkingBudget = Int($0) }
                                ),
                                in: 256...4096,
                                step: 256
                            )
                            .tint(.purple)
                        }
                    }
                } header: {
                    Label("Reasoning (DeepSeek R1)", systemImage: "brain.head.profile")
                }
            }
            .navigationTitle("⚙️ Beast Mode")
            .beastNavBarInline()
            .beastToolbarDone(dismiss)
        }
    }
}

struct PresetButton: View {
    let name: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(name)
                    .font(.caption)
            }
            .frame(width: 70, height: 60)
            .background(Color.beastGray6)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - System Prompt Picker

struct SystemPromptPicker: View {
    @Binding var selectedTemplate: SystemPromptTemplate
    @Binding var customPrompt: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(SystemPromptTemplate.allCases) { template in
                    Button {
                        selectedTemplate = template
                        if template != .custom {
                            dismiss()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.rawValue)
                                    .foregroundColor(.primary)
                                
                                if template != .custom {
                                    Text(template.prompt.prefix(100) + "...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedTemplate == template {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.cyan)
                            }
                        }
                    }
                }
                
                if selectedTemplate == .custom {
                    Section("Custom System Prompt") {
                        TextEditor(text: $customPrompt)
                            .frame(minHeight: 150)
                    }
                }
            }
            .navigationTitle("System Prompt")
            .beastNavBarInline()
            .beastToolbarDone(dismiss)
        }
    }
}

// MARK: - Model Picker with Descriptions

struct BeastModelPicker: View {
    @Binding var selectedModel: Model
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var monitor = SystemMonitor.shared
    
    var body: some View {
        NavigationStack {
            List {
                // Text Models
                Section {
                    ForEach(Model.textModels, id: \.rawValue) { model in
                        ModelRow(
                            model: model,
                            isSelected: selectedModel == model,
                            canLoad: canLoad(model)
                        ) {
                            selectedModel = model
                            dismiss()
                        }
                    }
                } header: {
                    Label("Text Models", systemImage: "text.bubble")
                }
                
                // Vision Models
                Section {
                    ForEach(Model.visionModels, id: \.rawValue) { model in
                        ModelRow(
                            model: model,
                            isSelected: selectedModel == model,
                            canLoad: canLoad(model)
                        ) {
                            selectedModel = model
                            dismiss()
                        }
                    }
                } header: {
                    Label("Vision Models", systemImage: "eye")
                }
                
                // Specialized Models
                Section {
                    ForEach(Model.specializedModels, id: \.rawValue) { model in
                        ModelRow(
                            model: model,
                            isSelected: selectedModel == model,
                            canLoad: canLoad(model)
                        ) {
                            selectedModel = model
                            dismiss()
                        }
                    }
                } header: {
                    Label("OCR / Document", systemImage: "doc.text.viewfinder")
                }
                
                // Memory info
                Section {
                    HStack {
                        Label("Available Memory", systemImage: "memorychip")
                        Spacer()
                        Text("\(monitor.memoryAvailableMB) MB")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Recommended", systemImage: "star")
                        Spacer()
                        Text(monitor.recommendedModelSize)
                            .foregroundColor(.cyan)
                    }
                } header: {
                    Text("System")
                }
            }
            .navigationTitle("Select Model")
            .beastNavBarInline()
            .beastToolbarCancel(dismiss)
        }
    }
    
    private func canLoad(_ model: Model) -> Bool {
        model.approximateSizeMB < monitor.memoryAvailableMB
    }
}

struct ModelRow: View {
    let model: Model
    let isSelected: Bool
    let canLoad: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.displayName)
                            .foregroundColor(canLoad ? .primary : .secondary)
                        
                        if model.isDownloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                    
                    Text(model.modelDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Text("\(model.approximateSizeMB / 1000).\((model.approximateSizeMB % 1000) / 100) GB")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(4)
                        
                        if model.isUncensored {
                            Text("🔓 Uncensored")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        if model.isReasoningModel {
                            Text("🧠 Reasoning")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cyan)
                }
            }
        }
        .disabled(!canLoad)
        .opacity(canLoad ? 1 : 0.5)
    }
}

// MARK: - Export Sheet

struct ExportSheet: View {
    let conversation: Conversation
    let turns: [Turn]
    @State private var selectedFormat: ExportFormat = .markdown
    @State private var exportedContent: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Format picker
                Picker("Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases, id: \.rawValue) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: selectedFormat) { _, _ in
                    generateExport()
                }
                
                // Preview
                ScrollView {
                    Text(exportedContent)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.beastGray6)
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = exportedContent
                        #else
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(exportedContent, forType: .string)
                        #endif
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    ShareLink(item: exportedContent) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Export")
            .beastNavBarInline()
            .beastToolbarDone(dismiss)
            .onAppear { generateExport() }
        }
    }
    
    private func generateExport() {
        exportedContent = ConversationExporter.export(
            conversation: conversation,
            turns: turns,
            format: selectedFormat
        )
    }
}

// MARK: - Stop Button

struct StopGenerationButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "stop.fill")
                Text("Stop")
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Thinking View (for DeepSeek R1)

struct ThinkingView: View {
    let thinking: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "brain.head.profile")
                    Text("Thinking Process")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
                .foregroundColor(.purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            }
            
            if isExpanded {
                Text(thinking)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .background(Color.beastGray6)
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Memory Warning Banner

struct MemoryWarningBanner: View {
    @ObservedObject var monitor = SystemMonitor.shared
    
    var body: some View {
        if monitor.memoryPressure == .critical || monitor.memoryPressure == .terminal {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(monitor.memoryPressure == .terminal 
                     ? "Critical memory! Close apps now." 
                     : "Low memory warning")
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.white)
            .padding(10)
            .background(monitor.memoryPressure == .terminal ? Color.red : Color.orange)
            .cornerRadius(8)
        }
    }
}
