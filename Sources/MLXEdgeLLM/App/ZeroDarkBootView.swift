// ZeroDarkBootView.swift — Tactical startup screen with phase progress
// Replaces silent 8-phase startup with visible, graceful-degradation boot sequence
// Each phase has 5s timeout — non-critical failures logged and skipped

import SwiftUI

// MARK: - Boot Phase

struct BootPhase: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let critical: Bool      // If true + fails, mark with warning but continue
}

enum BootPhaseState {
    case pending
    case running
    case done
    case failed(String)
    case skipped
}

// MARK: - ZeroDarkBootViewModel

@MainActor
final class ZeroDarkBootViewModel: ObservableObject {
    @Published var phases: [(phase: BootPhase, state: BootPhaseState)] = []
    @Published var currentIndex: Int = 0
    @Published var isComplete: Bool = false
    @Published var warnings: [String] = []

    let allPhases: [BootPhase] = [
        BootPhase(name: "AI Model",           symbol: "brain",                     critical: false),
        BootPhase(name: "Vision Engine",      symbol: "eye.fill",                  critical: false),
        BootPhase(name: "Safety Monitor",     symbol: "checkmark.shield.fill",     critical: false),
        BootPhase(name: "Secure Transport",   symbol: "lock.fill",                 critical: false),
        BootPhase(name: "Session Keys",       symbol: "key.fill",                  critical: false),
        BootPhase(name: "Geofencing",         symbol: "map.fill",                  critical: false),
        BootPhase(name: "Intel Corpus",       symbol: "doc.text.fill",             critical: false),
        BootPhase(name: "Navigation Sync",    symbol: "location.north.fill",       critical: false),
        BootPhase(name: "Mesh Relay",         symbol: "antenna.radiowaves.left.and.right", critical: false),
    ]

    func start() async {
        phases = allPhases.map { (.init(name: $0.name, symbol: $0.symbol, critical: $0.critical), .pending) }

        for (i, phase) in allPhases.enumerated() {
            currentIndex = i
            updateState(at: i, to: .running)

            do {
                try await withTimeout(seconds: 5) { [weak self] in
                    await self?.execute(phase: phase)
                }
                updateState(at: i, to: .done)
            } catch {
                let message = "\(phase.name): \(error.localizedDescription)"
                if phase.critical {
                    updateState(at: i, to: .failed(message))
                } else {
                    updateState(at: i, to: .skipped)
                    warnings.append(message)
                    AuditLogger.shared.log(.appLaunched, detail: "boot_skipped:\(phase.name)")
                }
            }

            // Small delay between phases for visual feedback
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }

        isComplete = true
        AuditLogger.shared.log(.appLaunched, detail: "boot_complete warnings:\(warnings.count)")
    }

    private func execute(phase: BootPhase) async {
        switch phase.name {
        case "AI Model":
            if LocalInferenceEngine.shared.modelFileExists {
                await LocalInferenceEngine.shared.loadModel()
            }
        case "Vision Engine":
            if VisionInferenceEngine.shared.modelFileExists {
                try? await VisionInferenceEngine.shared.loadModel()
            }
        case "Safety Monitor":
            RuntimeSafetyMonitor.shared.start()
        case "Secure Transport":
            DTNDeliveryManager.shared.start()
        case "Session Keys":
            _ = await SessionKeyManager.shared.generateSessionKey()
        case "Geofencing":
            GeofenceMonitor.shared.start()
            _ = TelemetryStore.shared
        case "Intel Corpus":
            AppState.shared.setupThreatSync()
            _ = IntelCorpus.shared
        case "Navigation Sync":
            AppState.shared.setupNavSync()
            BreadcrumbEngine.shared.startRecording()
        case "Mesh Relay":
            MeshRelay.shared.start()
        default:
            break
        }
    }

    private func updateState(at index: Int, to state: BootPhaseState) {
        guard index < phases.count else { return }
        phases[index] = (phase: phases[index].phase, state: state)
    }

    private func withTimeout(seconds: TimeInterval, operation: @escaping () async -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw BootError.timeout
            }
            try await group.next()
            group.cancelAll()
        }
    }

    enum BootError: LocalizedError {
        case timeout
        var errorDescription: String? { "Timed out after 5s" }
    }
}

// MARK: - ZeroDarkBootView

struct ZeroDarkBootView: View {
    @StateObject private var vm = ZeroDarkBootViewModel()
    @State private var showWarnings = false
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo / title
                VStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundColor(ZDDesign.cyanAccent)

                    Text("ZERO DARK")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundColor(ZDDesign.pureWhite)
                        .tracking(8)

                    Text("OFFLINE TACTICAL PLATFORM")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(ZDDesign.mediumGray)
                        .tracking(3)
                }

                // Phase list
                VStack(spacing: 6) {
                    ForEach(Array(vm.phases.enumerated()), id: \.element.phase.id) { index, item in
                        PhaseRow(phase: item.phase, state: item.state, isActive: index == vm.currentIndex)
                    }
                }
                .padding(.horizontal, 40)

                // Overall progress bar
                ProgressView(value: Double(vm.currentIndex + 1), total: Double(vm.allPhases.count))
                    .tint(ZDDesign.cyanAccent)
                    .padding(.horizontal, 40)

                // Warning count badge
                if !vm.warnings.isEmpty {
                    Button { showWarnings = true } label: {
                        Label("\(vm.warnings.count) warning\(vm.warnings.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(ZDDesign.safetyYellow)
                    }
                }

                Spacer()
            }
        }
        .task { await vm.start() }
        .onChange(of: vm.isComplete) { _, complete in
            if complete {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    onComplete()
                }
            }
        }
        .sheet(isPresented: $showWarnings) {
            BootWarningsSheet(warnings: vm.warnings)
        }
    }
}

// MARK: - PhaseRow

private struct PhaseRow: View {
    let phase: BootPhase
    let state: BootPhaseState
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            stateIcon
                .frame(width: 20)

            Image(systemName: phase.symbol)
                .foregroundColor(foregroundColor)
                .frame(width: 16)

            Text(phase.name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(foregroundColor)

            Spacer()

            if isActive {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(ZDDesign.cyanAccent)
            }
        }
        .opacity(opacity)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .pending:
            Circle().fill(Color.gray.opacity(0.3)).frame(width: 6, height: 6)
        case .running:
            Circle().fill(ZDDesign.cyanAccent).frame(width: 6, height: 6)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(ZDDesign.successGreen)
        case .failed:
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(ZDDesign.signalRed)
        case .skipped:
            Image(systemName: "minus").font(.system(size: 10, weight: .bold)).foregroundColor(ZDDesign.safetyYellow)
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .pending: return .gray
        case .running: return ZDDesign.cyanAccent
        case .done: return ZDDesign.pureWhite
        case .failed: return ZDDesign.signalRed
        case .skipped: return ZDDesign.safetyYellow
        }
    }

    private var opacity: Double {
        if case .pending = state { return 0.4 }
        return 1.0
    }
}

// MARK: - BootWarningsSheet

private struct BootWarningsSheet: View {
    let warnings: [String]
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            List(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(ZDDesign.safetyYellow)
            }
            .navigationTitle("Boot Warnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
