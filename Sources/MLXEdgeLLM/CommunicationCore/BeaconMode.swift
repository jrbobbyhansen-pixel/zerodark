// BeaconMode.swift — Periodic location/status beacon broadcaster
// Configurable interval, battery-optimized, includes heading/speed/battery.
// Receiver tracks history per peer. Wires into MeshService for transmission.

import Foundation
import SwiftUI
import CoreLocation
import CoreMotion

// MARK: - BeaconPacket

struct BeaconPacket: Codable, Identifiable {
    var id: UUID = UUID()
    var callsign: String
    var timestamp: Date = Date()
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double
    var headingDegrees: Double?    // nil if unknown
    var speedMPS: Double?          // nil if unknown
    var batteryPercent: Int
    var note: String               // optional free-text status

    var locationString: String {
        MGRSConverter.toMGRS(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), precision: 4)
    }

    var speedKPH: Double? { speedMPS.map { $0 * 3.6 } }
    var headingCardinal: String? {
        guard let h = headingDegrees else { return nil }
        let dirs = ["N","NE","E","SE","S","SW","W","NW","N"]
        return dirs[Int((h + 22.5) / 45) % 8]
    }
}

// MARK: - BeaconHistory (per peer)

struct BeaconHistory: Identifiable {
    var id: String { callsign }
    var callsign: String
    var packets: [BeaconPacket]   // newest first, max 50

    mutating func add(_ packet: BeaconPacket) {
        packets.insert(packet, at: 0)
        if packets.count > 50 { packets = Array(packets.prefix(50)) }
    }

    var latest: BeaconPacket? { packets.first }
    var isStale: Bool {
        guard let ts = latest?.timestamp else { return true }
        return Date().timeIntervalSince(ts) > 300   // 5 min
    }
}

// MARK: - BeaconMode

@MainActor
final class BeaconMode: ObservableObject {
    static let shared = BeaconMode()

    // MARK: - Config

    @Published var isActive = false
    @Published var intervalSeconds: Int = 60    // 1 min default
    @Published var statusNote: String = ""

    // MARK: - State

    @Published var lastTransmitTime: Date?
    @Published var transmitCount: Int = 0
    @Published var receivedHistory: [String: BeaconHistory] = [:]   // callsign → history

    private var timer: Timer?
    private let motionManager = CMMotionManager()
    private var heading: Double?
    private var speed: Double?
    private let meshPrefix = "[beacon]"

    private init() {
        subscribeMesh()
        startMotion()
    }

    // MARK: - Start / Stop

    func start() {
        guard !isActive else { return }
        isActive = true
        transmitNow()
        scheduleNext()
        AuditLogger.shared.log(.meshJoined, detail: "beacon_mode_started interval:\(intervalSeconds)s")
    }

    func stop() {
        isActive = false
        timer?.invalidate()
        timer = nil
        AuditLogger.shared.log(.meshLeft, detail: "beacon_mode_stopped")
    }

    func transmitNow() {
        guard let loc = LocationManager.shared.currentLocation else { return }

        let battery: Int = {
            #if canImport(UIKit)
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            return level < 0 ? 100 : Int(level * 100)
            #else
            return 100
            #endif
        }()

        let packet = BeaconPacket(
            callsign: AppConfig.deviceCallsign,
            latitude: loc.latitude,
            longitude: loc.longitude,
            altitudeMeters: 0,
            headingDegrees: heading,
            speedMPS: speed,
            batteryPercent: battery,
            note: statusNote
        )

        if let data = try? JSONEncoder().encode(packet),
           let jsonStr = String(data: data, encoding: .utf8) {
            MeshService.shared.sendText(meshPrefix + jsonStr)
        }

        lastTransmitTime = Date()
        transmitCount += 1
    }

    // MARK: - Timer

    private func scheduleNext() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.isActive == true else { return }
                self?.transmitNow()
            }
        }
    }

    func updateInterval(_ newInterval: Int) {
        intervalSeconds = max(10, min(3600, newInterval))
        if isActive { scheduleNext() }
    }

    // MARK: - Receive

    private func subscribeMesh() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ZD.meshMessage"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let text = note.userInfo?["text"] as? String,
                  text.hasPrefix("[beacon]") else { return }
            let jsonStr = String(text.dropFirst("[beacon]".count))
            guard let data = jsonStr.data(using: .utf8),
                  let packet = try? JSONDecoder().decode(BeaconPacket.self, from: data) else { return }

            Task { @MainActor [weak self] in
                self?.handleReceived(packet)
            }
        }
    }

    private func handleReceived(_ packet: BeaconPacket) {
        var history = receivedHistory[packet.callsign] ?? BeaconHistory(callsign: packet.callsign, packets: [])
        history.add(packet)
        receivedHistory[packet.callsign] = history
    }

    // MARK: - Motion (heading + speed)

    private func startMotion() {
        // Heading from location manager (observed via shared)
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ZD.locationHeadingUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let h = note.userInfo?["heading"] as? Double { self?.heading = h }
            if let s = note.userInfo?["speed"] as? Double { self?.speed = max(0, s) }
        }
    }

    // MARK: - Battery optimization notes
    // intervalSeconds >= 300 uses significant-change location (handled by LocationManager)
    // intervalSeconds < 300 uses standard GPS updates

    var batteryImpactLabel: String {
        switch intervalSeconds {
        case 0..<30:   return "High"
        case 30..<120: return "Medium"
        default:       return "Low"
        }
    }

    var batteryImpactColor: Color {
        switch intervalSeconds {
        case 0..<30:   return ZDDesign.signalRed
        case 30..<120: return ZDDesign.safetyYellow
        default:       return ZDDesign.successGreen
        }
    }
}

// MARK: - BeaconModeView

struct BeaconModeView: View {
    @ObservedObject private var beacon = BeaconMode.shared
    @State private var intervalInput: Double = Double(BeaconMode.shared.intervalSeconds)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        controlCard
                        if !beacon.receivedHistory.isEmpty {
                            receivedSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Beacon Mode")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Control Card

    private var controlCard: some View {
        VStack(spacing: 16) {
            // Status header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(beacon.isActive ? ZDDesign.successGreen : ZDDesign.mediumGray)
                            .frame(width: 10, height: 10)
                        Text(beacon.isActive ? "BEACONING" : "INACTIVE")
                            .font(.caption.bold())
                            .foregroundColor(beacon.isActive ? ZDDesign.successGreen : .secondary)
                    }
                    if let last = beacon.lastTransmitTime {
                        Text("Last TX: \(last.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    if beacon.transmitCount > 0 {
                        Text("\(beacon.transmitCount) packets sent")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button {
                    if beacon.isActive { beacon.stop() } else { beacon.start() }
                } label: {
                    Text(beacon.isActive ? "Stop" : "Start")
                        .font(.subheadline.bold())
                        .foregroundColor(beacon.isActive ? .white : .black)
                        .padding(.horizontal, 20).padding(.vertical, 8)
                        .background(beacon.isActive ? ZDDesign.signalRed : ZDDesign.successGreen)
                        .cornerRadius(8)
                }
            }

            Divider().background(ZDDesign.mediumGray.opacity(0.3))

            // Interval slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Interval").font(.caption.bold()).foregroundColor(.secondary)
                    Spacer()
                    Text(formatInterval(Int(intervalInput)))
                        .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                    HStack(spacing: 4) {
                        Image(systemName: "battery.50percent")
                            .font(.caption2).foregroundColor(beacon.batteryImpactColor)
                        Text(beacon.batteryImpactLabel)
                            .font(.caption2).foregroundColor(beacon.batteryImpactColor)
                    }
                }
                Slider(value: $intervalInput, in: 10...3600, step: 10)
                    .accentColor(ZDDesign.cyanAccent)
                    .onChange(of: intervalInput) { _, v in
                        beacon.updateInterval(Int(v))
                    }
                HStack {
                    Text("10s").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("1h").font(.caption2).foregroundColor(.secondary)
                }
            }

            Divider().background(ZDDesign.mediumGray.opacity(0.3))

            // Status note
            VStack(alignment: .leading, spacing: 4) {
                Text("Status Note").font(.caption.bold()).foregroundColor(.secondary)
                TextField("Optional status text included in beacon", text: $beacon.statusNote)
                    .font(.subheadline)
                    .foregroundColor(ZDDesign.pureWhite)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
            }

            Divider().background(ZDDesign.mediumGray.opacity(0.3))

            // Transmit now button
            Button {
                beacon.transmitNow()
            } label: {
                Label("Transmit Now", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(ZDDesign.cyanAccent)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Received Section

    private var receivedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECEIVED BEACONS")
                .font(.caption.bold()).foregroundColor(.secondary)

            ForEach(Array(beacon.receivedHistory.values).sorted { $0.callsign < $1.callsign }) { history in
                BeaconHistoryCard(history: history)
            }
        }
    }

    private func formatInterval(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60, r = s % 60
        return r > 0 ? "\(m)m \(r)s" : "\(m)m"
    }
}

// MARK: - Beacon History Card

struct BeaconHistoryCard: View {
    let history: BeaconHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(history.isStale ? ZDDesign.mediumGray : ZDDesign.successGreen)
                    .frame(width: 8, height: 8)
                Text(history.callsign).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                Spacer()
                Text("\(history.packets.count) pkts").font(.caption2).foregroundColor(.secondary)
                if history.isStale {
                    Text("STALE").font(.system(size: 8, weight: .bold)).foregroundColor(.red)
                }
            }

            if let latest = history.latest {
                HStack(spacing: 12) {
                    Label(latest.locationString, systemImage: "location").font(.caption2).foregroundColor(.secondary)
                    if let h = latest.headingCardinal {
                        Label(h, systemImage: "arrow.up").font(.caption2).foregroundColor(.secondary)
                    }
                    if let spd = latest.speedKPH {
                        Label(String(format: "%.0f km/h", spd), systemImage: "speedometer")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Label("\(latest.batteryPercent)%", systemImage: "battery.50percent")
                        .font(.caption2)
                        .foregroundColor(latest.batteryPercent < 20 ? .red : .secondary)
                }

                if !latest.note.isEmpty {
                    Text(latest.note).font(.caption).foregroundColor(ZDDesign.mediumGray).lineLimit(1)
                }

                Text(latest.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundColor(.secondary)
            }

            // Mini track (last 5 packets - show lat/lon change direction)
            if history.packets.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(history.packets.prefix(8).reversed()) { pkt in
                            Circle()
                                .fill(ZDDesign.cyanAccent.opacity(0.6))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }
}
