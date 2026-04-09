// CheckInSystem.swift — Periodic team check-in with real overdue alerts
// Fires UNUserNotificationCenter local notification + AppState in-app banner

import Foundation
import SwiftUI
import CoreLocation
import UserNotifications
import Combine

// MARK: - CheckIn

struct CheckIn: Identifiable, Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let callsign: String

    init(location: CLLocation, callsign: String = AppConfig.deviceCallsign) {
        self.id = UUID()
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.timestamp = Date()
        self.callsign = callsign
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - CheckInSystem

@MainActor
final class CheckInSystem: ObservableObject {
    static let shared = CheckInSystem()

    @Published var checkIns: [CheckIn] = []
    @Published var overdueCheckIns: [CheckIn] = []
    @Published var intervalMinutes: Int = 30

    private let locationManager = CLLocationManager()
    private var checkInTimer: Timer?
    private var overdueTimer: Timer?

    private init() {
        locationManager.requestWhenInUseAuthorization()
        requestNotificationPermission()
    }

    // MARK: - Scheduling

    func start(intervalMinutes: Int = 30) {
        self.intervalMinutes = intervalMinutes
        scheduleCheckIn(interval: TimeInterval(intervalMinutes * 60))
        // Check for overdue every 2 minutes
        overdueTimer?.invalidate()
        overdueTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkOverdueCheckIns() }
        }
    }

    func stop() {
        checkInTimer?.invalidate()
        overdueTimer?.invalidate()
    }

    private func scheduleCheckIn(interval: TimeInterval) {
        checkInTimer?.invalidate()
        checkInTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestCheckIn() }
        }
    }

    // MARK: - Check-In Recording

    func requestCheckIn() {
        locationManager.startUpdatingLocation()
        let location = locationManager.location ?? CLLocation(latitude: 0, longitude: 0)
        let checkIn = CheckIn(location: location)
        checkIns.append(checkIn)
        checkOverdueCheckIns()
        AuditLogger.shared.log(.credentialAccess, detail: "checkin recorded lat:\(checkIn.latitude) lon:\(checkIn.longitude)")
    }

    func manualCheckIn() {
        requestCheckIn()
    }

    // MARK: - Overdue Detection

    func checkOverdueCheckIns() {
        let overdueWindow = TimeInterval(intervalMinutes * 60) * 1.5 // 150% of interval
        let cutoff = Date().addingTimeInterval(-overdueWindow)
        let overdue = checkIns.filter { $0.timestamp < cutoff }
        if overdue.count != overdueCheckIns.count {
            overdueCheckIns = overdue
            if !overdue.isEmpty { alertOverdueCheckIns() }
        }
    }

    // MARK: - Overdue Alerts (REAL IMPLEMENTATION)

    func alertOverdueCheckIns() {
        guard !overdueCheckIns.isEmpty else { return }

        let count = overdueCheckIns.count
        let names = overdueCheckIns.map { $0.callsign }.joined(separator: ", ")

        // 1. Local push notification
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Overdue Check-In"
        content.body = "\(count) team member\(count == 1 ? "" : "s") overdue: \(names)"
        content.sound = .defaultCritical
        content.interruptionLevel = .critical
        content.categoryIdentifier = "CHECKIN_OVERDUE"

        let request = UNNotificationRequest(
            identifier: "checkin.overdue.\(UUID().uuidString)",
            content: content,
            trigger: nil // immediate
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("CheckIn notification error: \(error)") }
        }

        // 2. In-app banner via AppState notification queue
        NotificationCenter.default.post(
            name: Notification.Name("ZD.inAppAlert"),
            object: nil,
            userInfo: [
                "title": "Overdue Check-In",
                "body": "\(names) — \(Int(intervalMinutes * 3 / 2)) min overdue",
                "severity": "warning"
            ]
        )

        AuditLogger.shared.log(.credentialAccess, detail: "checkin_overdue count:\(count) callsigns:\(names)")
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { _, _ in }
    }
}

// MARK: - CheckInView

struct CheckInView: View {
    @StateObject private var system = CheckInSystem.shared
    @State private var intervalMinutes = 30

    var body: some View {
        NavigationStack {
            List {
                Section("Configuration") {
                    Stepper("Interval: \(intervalMinutes) min", value: $intervalMinutes, in: 5...120, step: 5)
                        .onChange(of: intervalMinutes) { _, v in
                            system.start(intervalMinutes: v)
                        }
                    Button("Manual Check-In") { system.manualCheckIn() }
                        .foregroundColor(ZDDesign.cyanAccent)
                }

                if !system.overdueCheckIns.isEmpty {
                    Section("⚠️ Overdue (\(system.overdueCheckIns.count))") {
                        ForEach(system.overdueCheckIns) { ci in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ci.callsign).font(.headline).foregroundColor(ZDDesign.signalRed)
                                Text("Last seen: \(ci.timestamp, style: .relative) ago")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("Recent Check-Ins (\(system.checkIns.count))") {
                    ForEach(system.checkIns.suffix(10).reversed()) { ci in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(ci.callsign)
                            Spacer()
                            Text(ci.timestamp, style: .time).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Check-In System")
        }
    }
}
