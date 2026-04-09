// TourniquetTimer.swift — Multi-tourniquet elapsed timer with alerts
// Color-coded urgency: green <1hr, yellow 1-2hr, red >2hr
// Vibration + local notification at 2hr mark

import Foundation
import SwiftUI
import AudioToolbox
import UserNotifications

// MARK: - Limb

enum Limb: String, CaseIterable, Identifiable {
    case leftArm  = "Left Arm"
    case rightArm = "Right Arm"
    case leftLeg  = "Left Leg"
    case rightLeg = "Right Leg"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .leftArm, .rightArm: return "hand.raised.fill"
        case .leftLeg, .rightLeg: return "figure.walk"
        }
    }
}

// MARK: - ActiveTourniquet

struct ActiveTourniquet: Identifiable {
    let id = UUID()
    let limb: Limb
    let appliedAt: Date

    var elapsed: TimeInterval { Date().timeIntervalSince(appliedAt) }

    var elapsedFormatted: String {
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    var urgencyColor: String {
        switch elapsed {
        case ..<3600:      return "successGreen"   // <1hr
        case 3600..<7200:  return "safetyYellow"   // 1-2hr
        default:           return "signalRed"      // >2hr
        }
    }

    var timeOnForehead: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "T-\(formatter.string(from: appliedAt))"
    }
}

// MARK: - TourniquetTimer

@MainActor
final class TourniquetTimer: ObservableObject {
    @Published var activeTourniquets: [ActiveTourniquet] = []
    private var displayTimer: Timer?
    private var alertedIDs: Set<UUID> = []

    init() {
        requestNotificationPermission()
    }

    func apply(to limb: Limb) {
        // Don't allow duplicate on same limb
        guard !activeTourniquets.contains(where: { $0.limb == limb }) else { return }
        let tq = ActiveTourniquet(limb: limb, appliedAt: Date())
        activeTourniquets.append(tq)
        scheduleAlert(for: tq)
        startDisplayTimer()
        AuditLogger.shared.log(.tourniquetApplied, detail: limb.rawValue)
    }

    func remove(id: UUID) {
        activeTourniquets.removeAll { $0.id == id }
        alertedIDs.remove(id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        if activeTourniquets.isEmpty { stopDisplayTimer() }
    }

    // MARK: - Timer for UI refresh

    private func startDisplayTimer() {
        guard displayTimer == nil else { return }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
                self?.checkAlerts()
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Alerts

    private func checkAlerts() {
        for tq in activeTourniquets where tq.elapsed >= 7200 && !alertedIDs.contains(tq.id) {
            alertedIDs.insert(tq.id)
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

            NotificationCenter.default.post(
                name: Notification.Name("ZD.inAppAlert"),
                object: nil,
                userInfo: [
                    "title": "Tourniquet Alert",
                    "body": "\(tq.limb.rawValue) — 2 hours elapsed. Reassess or evacuate.",
                    "severity": "critical"
                ]
            )
        }
    }

    private func scheduleAlert(for tq: ActiveTourniquet) {
        let content = UNMutableNotificationContent()
        content.title = "Tourniquet Alert"
        content.body = "\(tq.limb.rawValue) tourniquet has been applied for 2 hours. Reassess limb viability."
        content.sound = .defaultCritical
        content.interruptionLevel = .critical

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 7200, repeats: false)
        let request = UNNotificationRequest(identifier: tq.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { _, _ in }
    }
}

// MARK: - TourniquetTimerView

struct TourniquetTimerView: View {
    @StateObject private var timer = TourniquetTimer()
    @State private var selectedLimb: Limb = .leftArm

    var body: some View {
        Form { _ in
            Section("Apply Tourniquet") {
                Picker("Limb", selection: $selectedLimb) {
                    ForEach(Limb.allCases) { limb in
                        Label(limb.rawValue, systemImage: limb.icon).tag(limb)
                    }
                }
                Button {
                    timer.apply(to: selectedLimb)
                } label: {
                    Label("Apply Tourniquet", systemImage: "bandage.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZDDesign.signalRed)
                .disabled(timer.activeTourniquets.contains { $0.limb == selectedLimb })
            }

            if !timer.activeTourniquets.isEmpty {
                Section("Active Tourniquets (\(timer.activeTourniquets.count))") {
                    ForEach(timer.activeTourniquets) { tq in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(colorForUrgency(tq.urgencyColor))
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tq.limb.rawValue).font(.headline)
                                Text("Mark forehead: \(tq.timeOnForehead)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(tq.elapsedFormatted)
                                .font(.system(.title3, design: .monospaced).bold())
                                .foregroundColor(colorForUrgency(tq.urgencyColor))
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                timer.remove(id: tq.id)
                            } label: {
                                Label("Remove", systemImage: "xmark.circle")
                            }
                        }
                    }
                }

                Section {
                    Text("Green: <1hr | Yellow: 1-2hr | Red: >2hr")
                        .font(.caption).foregroundColor(.secondary)
                    Text("Notification fires automatically at 2 hours.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Tourniquet Timer")
        .navigationBarTitleDisplayMode(.large)
    }

    private func colorForUrgency(_ name: String) -> Color {
        switch name {
        case "successGreen": return ZDDesign.successGreen
        case "safetyYellow": return ZDDesign.safetyYellow
        case "signalRed":    return ZDDesign.signalRed
        default:             return .gray
        }
    }
}

#Preview {
    NavigationStack { TourniquetTimerView() }
}
