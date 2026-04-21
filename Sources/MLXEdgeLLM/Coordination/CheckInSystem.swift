// CheckInSystem.swift — Scheduled team check-in with mesh sync and escalation
// Broadcasts check-in requests via mesh, tracks per-peer responses,
// fires overdue alerts (UNNotification + in-app banner) on configurable intervals.

import Foundation
import SwiftUI
import CoreLocation
import UserNotifications
import Combine
import CryptoKit

// MARK: - Mesh payload (wire format)

/// Typed Codable payload for check-in messages — replaces the brittle text-prefix
/// parsing from older builds. Transported inside an AES-256-GCM-encrypted
/// ZDMeshMessage of type .checkIn, so lat/lon are never exposed on the wire.
/// The `request` variant carries no coordinates.
struct CheckInMeshPayload: Codable {
    enum Kind: String, Codable { case request, response }

    let kind: Kind
    let callsign: String
    let timestamp: TimeInterval
    let latitude: Double?
    let longitude: Double?
}

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

// MARK: - CheckInStatus (per peer)

struct CheckInStatus: Identifiable {
    let id: UUID = UUID()
    let callsign: String
    var lastCheckIn: Date?
    var isOverdue: Bool = false

    var statusLabel: String {
        guard let last = lastCheckIn else { return "No check-in" }
        return "Last: \(last.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - CheckInSystem

@MainActor
final class CheckInSystem: ObservableObject {
    static let shared = CheckInSystem()

    @Published var checkIns: [CheckIn] = []
    @Published var overdueCheckIns: [CheckIn] = []
    @Published var peerStatuses: [CheckInStatus] = []
    @Published var intervalMinutes: Int = 30
    @Published var isActive: Bool = false

    private let locationManager = CLLocationManager()
    private var checkInTimer: Timer?
    private var overdueTimer: Timer?
    private var meshCancellable: AnyCancellable?

    private let meshReqPrefix  = "[checkin-req]"
    private let meshRspPrefix  = "[checkin-rsp]"

    private init() {
        locationManager.requestWhenInUseAuthorization()
        requestNotificationPermission()
        subscribeMesh()
    }

    // MARK: - Start / Stop

    func start(intervalMinutes: Int = 30) {
        self.intervalMinutes = intervalMinutes
        isActive = true
        scheduleCheckInTimer(interval: TimeInterval(intervalMinutes * 60))
        overdueTimer?.invalidate()
        overdueTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkOverdue() }
        }
        // Immediately send the first check-in request to team
        broadcastCheckInRequest()
    }

    func stop() {
        checkInTimer?.invalidate()
        overdueTimer?.invalidate()
        isActive = false
    }

    private func scheduleCheckInTimer(interval: TimeInterval) {
        checkInTimer?.invalidate()
        checkInTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.broadcastCheckInRequest()
                self?.recordSelfCheckIn()
            }
        }
    }

    // MARK: - Self Check-In

    func manualCheckIn() {
        recordSelfCheckIn()
        respondViaMesh()
    }

    private func recordSelfCheckIn() {
        locationManager.startUpdatingLocation()
        let location = locationManager.location ?? CLLocation(latitude: 0, longitude: 0)
        let checkIn = CheckIn(location: location)
        checkIns.append(checkIn)
        checkOverdue()
        // Redact coordinates in the local audit log — store only a coarsened cell
        // plus a hash of the exact position. Forensic read of Documents can't
        // recover the exact location, but the audit trail still proves activity.
        AuditLogger.shared.log(
            .checkInRecorded,
            detail: Self.redactedLocation(lat: checkIn.latitude, lon: checkIn.longitude)
        )
    }

    // MARK: - Audit Redaction

    /// Coarsen to ~1 km cell (2 decimal places) and append a short SHA-256 hash
    /// of the exact coord. Audit integrity preserved without exposing team positions.
    static func redactedLocation(lat: Double, lon: Double) -> String {
        let coarseLat = (lat * 100).rounded() / 100
        let coarseLon = (lon * 100).rounded() / 100
        let raw = "\(lat),\(lon)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return String(format: "cell:%.2f,%.2f hash:%@", coarseLat, coarseLon, hex)
    }

    // MARK: - Mesh Broadcast

    /// Send a typed check-in request to all peers over the encrypted mesh.
    private func broadcastCheckInRequest() {
        guard MeshService.shared.isActive else { return }
        let payload = CheckInMeshPayload(
            kind: .request,
            callsign: AppConfig.deviceCallsign,
            timestamp: Date().timeIntervalSince1970,
            latitude: nil,
            longitude: nil
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        MeshService.shared.broadcastData(data, type: .checkIn)
    }

    /// Respond to a received check-in request (answer for self).
    private func respondViaMesh() {
        guard MeshService.shared.isActive else { return }
        let location = locationManager.location ?? CLLocation(latitude: 0, longitude: 0)
        let payload = CheckInMeshPayload(
            kind: .response,
            callsign: AppConfig.deviceCallsign,
            timestamp: Date().timeIntervalSince1970,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        MeshService.shared.broadcastData(data, type: .checkIn)
    }

    // MARK: - Mesh Receive

    private func subscribeMesh() {
        // Primary path: typed .checkIn messages posted by MeshService after decrypt.
        meshCancellable = NotificationCenter.default
            .publisher(for: Notification.Name("ZD.checkInReceived"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let data = notification.userInfo?["data"] as? Data else { return }
                self?.handleCheckInPayload(data)
            }

        // Legacy compatibility: older peers still speak text-prefix format.
        // Kept so a mixed-version deployment keeps working during rollout.
        _ = NotificationCenter.default.addObserver(
            forName: Notification.Name("ZD.meshMessage"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let text = notification.userInfo?["text"] as? String else { return }
            Task { @MainActor in self?.handleLegacyTextMessage(text) }
        }
    }

    private func handleCheckInPayload(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(CheckInMeshPayload.self, from: data) else { return }
        switch payload.kind {
        case .request:
            if payload.callsign != AppConfig.deviceCallsign { respondViaMesh() }
        case .response:
            guard let lat = payload.latitude, let lon = payload.longitude else { return }
            applyPeerCheckIn(callsign: payload.callsign, lat: lat, lon: lon, ts: payload.timestamp)
        }
    }

    private func handleLegacyTextMessage(_ text: String) {
        if text.hasPrefix(meshReqPrefix) {
            let requester = String(text.dropFirst(meshReqPrefix.count))
            if requester != AppConfig.deviceCallsign {
                respondViaMesh()
            }
        } else if text.hasPrefix(meshRspPrefix) {
            let jsonStr = String(text.dropFirst(meshRspPrefix.count))
            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let callsign = obj["callsign"] as? String,
                  let lat = obj["lat"] as? Double,
                  let lon = obj["lon"] as? Double,
                  let ts = obj["ts"] as? Double else { return }
            applyPeerCheckIn(callsign: callsign, lat: lat, lon: lon, ts: ts)
        }
    }

    private func applyPeerCheckIn(callsign: String, lat: Double, lon: Double, ts: TimeInterval) {
        let checkIn = CheckIn(
            location: CLLocation(latitude: lat, longitude: lon),
            callsign: callsign
        )
        // Avoid duplicate (same callsign + same ~minute)
        let isDuplicate = checkIns.contains {
            $0.callsign == callsign && abs($0.timestamp.timeIntervalSince(checkIn.timestamp)) < 60
        }
        if !isDuplicate {
            checkIns.append(checkIn)
        }

        // Update peer status table
        if let idx = peerStatuses.firstIndex(where: { $0.callsign == callsign }) {
            peerStatuses[idx].lastCheckIn = Date(timeIntervalSince1970: ts)
            peerStatuses[idx].isOverdue = false
        } else {
            var s = CheckInStatus(callsign: callsign)
            s.lastCheckIn = Date(timeIntervalSince1970: ts)
            peerStatuses.append(s)
        }
        checkOverdue()
    }

    // MARK: - Overdue Detection

    func checkOverdue() {
        let overdueWindow = TimeInterval(intervalMinutes * 60) * 1.5
        let cutoff = Date().addingTimeInterval(-overdueWindow)

        // Overdue = check-ins older than 1.5× interval (only one per callsign)
        var seenCallsigns = Set<String>()
        var overdue: [CheckIn] = []
        for ci in checkIns.sorted(by: { $0.timestamp > $1.timestamp }) {
            guard !seenCallsigns.contains(ci.callsign) else { continue }
            seenCallsigns.insert(ci.callsign)
            if ci.timestamp < cutoff { overdue.append(ci) }
        }

        if overdue.count != overdueCheckIns.count {
            overdueCheckIns = overdue
            if !overdue.isEmpty { alertOverdue() }
        }

        // Update peerStatuses.isOverdue
        for idx in peerStatuses.indices {
            let last = peerStatuses[idx].lastCheckIn ?? .distantPast
            peerStatuses[idx].isOverdue = last < cutoff
        }
    }

    // MARK: - Overdue Alerts

    private func alertOverdue() {
        guard !overdueCheckIns.isEmpty else { return }
        let count = overdueCheckIns.count
        let names = overdueCheckIns.map { $0.callsign }.joined(separator: ", ")

        let content = UNMutableNotificationContent()
        content.title = "Overdue Check-In"
        content.body = "\(count) member\(count == 1 ? "" : "s") overdue: \(names)"
        content.sound = .defaultCritical
        content.interruptionLevel = .critical
        content.categoryIdentifier = "CHECKIN_OVERDUE"
        let request = UNNotificationRequest(
            identifier: "checkin.overdue.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }

        NotificationCenter.default.post(
            name: Notification.Name("ZD.inAppAlert"),
            object: nil,
            userInfo: [
                "title": "Overdue Check-In",
                "body": "\(names) — \(Int(Double(intervalMinutes) * 1.5)) min overdue",
                "severity": "warning"
            ]
        )

        // Callsigns identify peers but expose no coordinates.
        AuditLogger.shared.log(.checkInRecorded, detail: "OVERDUE count:\(count) callsigns:\(names)")
        // No lat/lon in overdue audit — only counts + callsigns, consistent with
        // the coordinate-redaction policy applied in recordSelfCheckIn.
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { _, _ in }
    }
}

// MARK: - CheckInView

struct CheckInView: View {
    @ObservedObject private var system = CheckInSystem.shared
    @State private var intervalMinutes = 30

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List {
                    Section {
                        Stepper("Interval: \(intervalMinutes) min", value: $intervalMinutes, in: 5...120, step: 5)
                            .onChange(of: intervalMinutes) { _, v in
                                system.start(intervalMinutes: v)
                            }
                        HStack {
                            Button("Start Monitoring") { system.start(intervalMinutes: intervalMinutes) }
                                .foregroundColor(ZDDesign.cyanAccent)
                                .disabled(system.isActive)
                            Spacer()
                            Button("Stop") { system.stop() }
                                .foregroundColor(.red)
                                .disabled(!system.isActive)
                        }
                        Button("Manual Check-In") { system.manualCheckIn() }
                            .fontWeight(.bold)
                            .foregroundColor(ZDDesign.cyanAccent)
                    } header: {
                        Text("Configuration")
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    if !system.peerStatuses.isEmpty {
                        Section("Team Status (\(system.peerStatuses.count))") {
                            ForEach(system.peerStatuses) { status in
                                HStack {
                                    Image(systemName: status.isOverdue ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                        .foregroundColor(status.isOverdue ? .red : .green)
                                    Text(status.callsign).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                                    Spacer()
                                    Text(status.statusLabel).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .listRowBackground(ZDDesign.darkCard)
                    }

                    if !system.overdueCheckIns.isEmpty {
                        Section {
                            ForEach(system.overdueCheckIns) { ci in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ci.callsign).font(.headline).foregroundColor(ZDDesign.signalRed)
                                    Text("Last seen: \(ci.timestamp, style: .relative) ago")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        } header: {
                            Text("Overdue (\(system.overdueCheckIns.count))")
                                .foregroundColor(.red)
                        }
                        .listRowBackground(ZDDesign.darkCard)
                    }

                    Section("Recent Check-Ins (\(system.checkIns.count))") {
                        ForEach(system.checkIns.suffix(15).reversed()) { ci in
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text(ci.callsign).foregroundColor(ZDDesign.pureWhite)
                                Spacer()
                                Text(ci.timestamp, style: .time).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Check-In System")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
    }
}
