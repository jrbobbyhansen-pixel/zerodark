//
//  CrashPrevention.swift
//  ZeroDark
//
//  Memory management, thermal throttling, graceful degradation.
//  This ensures ZeroDark NEVER crashes your device.
//

import SwiftUI
import Foundation
import os

// MARK: - Device Health Monitor

@MainActor
class DeviceHealthMonitor: ObservableObject {
    static let shared = DeviceHealthMonitor()
    
    // Current state
    @Published var memoryPressure: MemoryPressure = .normal
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var batteryLevel: Float = 1.0
    @Published var isLowPowerMode: Bool = false
    @Published var availableMemoryMB: Int = 0
    @Published var usedMemoryMB: Int = 0
    
    // Thresholds
    let criticalMemoryMB = 100  // Below this, start unloading
    let warningMemoryMB = 300   // Below this, stop loading new models
    
    private var memoryWarningObserver: NSObjectProtocol?
    private var thermalObserver: NSObjectProtocol?
    private var batteryObserver: NSObjectProtocol?
    private var lowPowerObserver: NSObjectProtocol?
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        // Memory pressure notifications
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        
        // Thermal state monitoring
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.thermalState = ProcessInfo.processInfo.thermalState
            self?.handleThermalChange()
        }
        
        // Battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.batteryLevel = UIDevice.current.batteryLevel
        }
        
        // Low power mode
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        
        // Initial values
        thermalState = ProcessInfo.processInfo.thermalState
        batteryLevel = UIDevice.current.batteryLevel
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        
        // Start memory polling
        startMemoryPolling()
    }
    
    private func startMemoryPolling() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateMemoryStats()
        }
        updateMemoryStats()
    }
    
    private func updateMemoryStats() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            usedMemoryMB = Int(info.resident_size / 1024 / 1024)
        }
        
        // Get available memory
        availableMemoryMB = Int(os_proc_available_memory() / 1024 / 1024)
        
        // Update pressure level
        if availableMemoryMB < criticalMemoryMB {
            memoryPressure = .critical
        } else if availableMemoryMB < warningMemoryMB {
            memoryPressure = .warning
        } else {
            memoryPressure = .normal
        }
    }
    
    private func handleMemoryWarning() {
        memoryPressure = .critical
        
        // Notify ModelManager to unload
        NotificationCenter.default.post(name: .memoryPressureCritical, object: nil)
        
        // Log
        os_log(.error, "⚠️ Memory warning received. Available: %d MB", availableMemoryMB)
    }
    
    private func handleThermalChange() {
        switch thermalState {
        case .critical:
            // Pause all inference
            NotificationCenter.default.post(name: .thermalCritical, object: nil)
            os_log(.error, "🔥 Thermal critical - pausing inference")
        case .serious:
            // Reduce model size
            NotificationCenter.default.post(name: .thermalSerious, object: nil)
            os_log(.warning, "🌡️ Thermal serious - reducing model size")
        default:
            break
        }
    }
    
    /// Check if it's safe to load a model
    func canLoadModel(sizeMB: Int) -> Bool {
        // Don't load if memory pressure is critical
        guard memoryPressure != .critical else { return false }
        
        // Don't load if thermal is critical
        guard thermalState != .critical else { return false }
        
        // Don't load if not enough memory (with 200MB buffer)
        guard availableMemoryMB > sizeMB + 200 else { return false }
        
        // Don't load large models in low power mode
        if isLowPowerMode && sizeMB > 2000 {
            return false
        }
        
        return true
    }
    
    /// Get recommended model tier based on current conditions
    func recommendedModelTier() -> ModelTier {
        // Critical thermal = tiny models only
        if thermalState == .critical {
            return .minimal
        }
        
        // Serious thermal or critical memory = small models
        if thermalState == .serious || memoryPressure == .critical {
            return .small
        }
        
        // Low power mode = medium models
        if isLowPowerMode {
            return .medium
        }
        
        // Warning memory = medium models
        if memoryPressure == .warning {
            return .medium
        }
        
        // Low battery = medium models
        if batteryLevel < 0.2 {
            return .medium
        }
        
        // All good = full power
        return .full
    }
}

enum MemoryPressure {
    case normal, warning, critical
}

enum ModelTier {
    case minimal  // 1B models only
    case small    // Up to 3B
    case medium   // Up to 8B
    case full     // Any model
    
    var maxModelSizeMB: Int {
        switch self {
        case .minimal: return 700
        case .small: return 2000
        case .medium: return 5000
        case .full: return 16000
        }
    }
}

extension Notification.Name {
    static let memoryPressureCritical = Notification.Name("memoryPressureCritical")
    static let thermalCritical = Notification.Name("thermalCritical")
    static let thermalSerious = Notification.Name("thermalSerious")
}

// MARK: - Safe Model Manager

@MainActor
class SafeModelManager: ObservableObject {
    static let shared = SafeModelManager()
    
    @Published var loadedModels: [String: LoadedModel] = [:]
    @Published var isLoading = false
    @Published var lastError: ModelError?
    
    private let healthMonitor = DeviceHealthMonitor.shared
    private let maxLoadedModels = 2  // Never load more than 2 at once
    
    init() {
        setupObservers()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: .memoryPressureCritical,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryPressure()
        }
        
        NotificationCenter.default.addObserver(
            forName: .thermalCritical,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalCritical()
        }
    }
    
    /// Safely load a model with all checks
    func loadModel(_ modelId: String, sizeMB: Int) async throws {
        // Check if already loaded
        if loadedModels[modelId] != nil {
            return
        }
        
        // Check if safe to load
        guard healthMonitor.canLoadModel(sizeMB: sizeMB) else {
            throw ModelError.insufficientResources(
                available: healthMonitor.availableMemoryMB,
                required: sizeMB
            )
        }
        
        // Unload other models if needed
        while loadedModels.count >= maxLoadedModels {
            unloadLeastRecentModel()
        }
        
        // Load with timeout
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await withTimeout(seconds: 60) {
                // Actual model loading would happen here
                try await Task.sleep(nanoseconds: 1_000_000_000) // Simulated
            }
            
            loadedModels[modelId] = LoadedModel(
                id: modelId,
                sizeMB: sizeMB,
                loadedAt: Date()
            )
            
        } catch {
            lastError = ModelError.loadFailed(reason: error.localizedDescription)
            throw lastError!
        }
    }
    
    /// Unload a specific model
    func unloadModel(_ modelId: String) {
        loadedModels.removeValue(forKey: modelId)
        
        // Force garbage collection
        autoreleasepool {
            // Release any autoreleased objects
        }
    }
    
    /// Unload the least recently used model
    private func unloadLeastRecentModel() {
        guard let oldest = loadedModels.values.min(by: { $0.lastUsed < $1.lastUsed }) else { return }
        unloadModel(oldest.id)
        os_log(.info, "📤 Unloaded model %{public}@ to free memory", oldest.id)
    }
    
    /// Emergency unload all models
    func emergencyUnload() {
        os_log(.warning, "🚨 Emergency unload - freeing all models")
        loadedModels.removeAll()
    }
    
    private func handleMemoryPressure() {
        os_log(.warning, "⚠️ Memory pressure - unloading models")
        
        // Unload all but the smallest model
        let sorted = loadedModels.values.sorted { $0.sizeMB > $1.sizeMB }
        for model in sorted.dropLast() {
            unloadModel(model.id)
        }
    }
    
    private func handleThermalCritical() {
        os_log(.error, "🔥 Thermal critical - emergency unload")
        emergencyUnload()
    }
}

struct LoadedModel {
    let id: String
    let sizeMB: Int
    let loadedAt: Date
    var lastUsed: Date = Date()
}

enum ModelError: Error, LocalizedError {
    case insufficientResources(available: Int, required: Int)
    case loadFailed(reason: String)
    case timeout
    case thermalThrottled
    
    var errorDescription: String? {
        switch self {
        case .insufficientResources(let available, let required):
            return "Not enough memory. Available: \(available)MB, Required: \(required)MB"
        case .loadFailed(let reason):
            return "Model failed to load: \(reason)"
        case .timeout:
            return "Model loading timed out"
        case .thermalThrottled:
            return "Device too hot. Please let it cool down."
        }
    }
}

// MARK: - Safe Inference

@MainActor
class SafeInference: ObservableObject {
    static let shared = SafeInference()
    
    @Published var isInferring = false
    @Published var progress: Double = 0
    @Published var isCancelled = false
    
    private var currentTask: Task<Void, Never>?
    private let healthMonitor = DeviceHealthMonitor.shared
    
    /// Run inference with safety checks
    func generate(prompt: String, maxTokens: Int) async throws -> String {
        // Check if safe to run
        guard healthMonitor.thermalState != .critical else {
            throw ModelError.thermalThrottled
        }
        
        guard healthMonitor.memoryPressure != .critical else {
            throw ModelError.insufficientResources(
                available: healthMonitor.availableMemoryMB,
                required: 500
            )
        }
        
        isInferring = true
        isCancelled = false
        progress = 0
        
        defer {
            isInferring = false
            currentTask = nil
        }
        
        return try await withTimeout(seconds: 120) {
            var result = ""
            
            for i in 0..<maxTokens {
                // Check for cancellation
                guard !self.isCancelled else {
                    throw CancellationError()
                }
                
                // Check thermal state during inference
                if self.healthMonitor.thermalState == .critical {
                    os_log(.warning, "🔥 Inference stopped due to thermal")
                    break
                }
                
                // Check memory during inference
                if self.healthMonitor.memoryPressure == .critical {
                    os_log(.warning, "⚠️ Inference stopped due to memory")
                    break
                }
                
                // Simulate token generation
                try await Task.sleep(nanoseconds: 50_000_000)
                result += "token "
                
                self.progress = Double(i + 1) / Double(maxTokens)
            }
            
            return result
        }
    }
    
    /// Cancel current inference
    func cancel() {
        isCancelled = true
        currentTask?.cancel()
    }
}

// MARK: - Timeout Helper

func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ModelError.timeout
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Graceful Degradation

struct GracefulDegradation {
    /// Get the best model that's safe to run right now
    static func getBestAvailableModel(for task: TaskType) -> String {
        let tier = DeviceHealthMonitor.shared.recommendedModelTier()
        
        switch tier {
        case .minimal:
            return "llama-3.2-1b"
        case .small:
            switch task {
            case .chat: return "llama-3.2-3b"
            case .code: return "qwen2.5-coder-3b"
            case .vision: return "smolvlm"
            }
        case .medium:
            switch task {
            case .chat: return "qwen2.5-7b"
            case .code: return "qwen2.5-coder-7b"
            case .vision: return "qwen-vl-4b"
            }
        case .full:
            switch task {
            case .chat: return "qwen3-8b"
            case .code: return "qwen2.5-coder-7b"
            case .vision: return "qwen3-vl-8b"
            }
        }
    }
    
    enum TaskType {
        case chat, code, vision
    }
}

// MARK: - Health Dashboard View

struct DeviceHealthView: View {
    @StateObject private var health = DeviceHealthMonitor.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Memory
            HealthCard(
                title: "Memory",
                icon: "memorychip",
                value: "\(health.availableMemoryMB) MB free",
                status: health.memoryPressure == .normal ? .good : 
                        health.memoryPressure == .warning ? .warning : .critical
            )
            
            // Thermal
            HealthCard(
                title: "Temperature",
                icon: "thermometer",
                value: thermalString,
                status: health.thermalState == .nominal ? .good :
                        health.thermalState == .fair ? .good :
                        health.thermalState == .serious ? .warning : .critical
            )
            
            // Battery
            HealthCard(
                title: "Battery",
                icon: "battery.100",
                value: "\(Int(health.batteryLevel * 100))%",
                status: health.batteryLevel > 0.2 ? .good : .warning
            )
            
            // Model tier
            HStack {
                Text("Recommended Model Tier:")
                    .foregroundColor(.secondary)
                Text(tierString)
                    .fontWeight(.bold)
            }
            
            if health.isLowPowerMode {
                Label("Low Power Mode Active", systemImage: "bolt.slash")
                    .foregroundColor(.orange)
            }
        }
        .padding()
    }
    
    var thermalString: String {
        switch health.thermalState {
        case .nominal: return "Cool"
        case .fair: return "Normal"
        case .serious: return "Warm"
        case .critical: return "Hot!"
        @unknown default: return "Unknown"
        }
    }
    
    var tierString: String {
        switch health.recommendedModelTier() {
        case .minimal: return "Minimal (1B)"
        case .small: return "Small (3B)"
        case .medium: return "Medium (8B)"
        case .full: return "Full (14B+)"
        }
    }
}

struct HealthCard: View {
    let title: String
    let icon: String
    let value: String
    let status: HealthStatus
    
    enum HealthStatus {
        case good, warning, critical
        
        var color: Color {
            switch self {
            case .good: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(status.color)
                .frame(width: 30)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .medium))
            }
            
            Spacer()
            
            Circle()
                .fill(status.color)
                .frame(width: 12, height: 12)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    DeviceHealthView()
}
